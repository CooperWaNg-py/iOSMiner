//
//  MiningManager.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import Foundation

@Observable
final class MiningManager {
    nonisolated enum MiningState: Sendable {
        case idle
        case connecting
        case mining
    }

    let stratum = StratumClient()
    let engine = MiningEngine()
    let backgroundHelper = BackgroundHelper()
    let devFee = DevFeeManager()
    let stats = MiningStats()
    let globalStats = GlobalStats()

    private(set) var state: MiningState = .idle
    private(set) var elapsedSeconds: Int = 0
    /// Incremented each time a share is submitted to the pool (before acceptance).
    private(set) var sharesSubmitted: Int = 0
    /// Number of auto-reconnects this session.
    private(set) var reconnectCount: Int = 0

    var backgroundMining: Bool = false {
        didSet {
            if backgroundMining && state == .mining {
                backgroundHelper.enableBackground()
            } else if !backgroundMining {
                backgroundHelper.disableBackground()
            }
        }
    }

    /// Silent mode: disables stats sampling, log accumulation, widget writes.
    /// Mining continues at full speed with minimal overhead.
    var silentMode: Bool = false {
        didSet {
            if silentMode {
                stats.stopSampling()
            } else if state == .mining {
                stats.startSampling(engine: engine, stratum: stratum)
            }
        }
    }

    private var timer: Timer?
    private var globalStatsTimer: Timer?
    private var reconnectTimer: Timer?
    private var authPollTimer: Timer?
    /// Track shares at start so we can compute delta for global stats
    private var sessionStartAccepted: Int = 0
    private var sessionStartRejected: Int = 0
    private var lastRecordedHashes: UInt64 = 0
    /// Whether a user-initiated stop was requested (vs connection drop)
    private var userStopped = false

    // Reconnect backoff: 3s, 6s, 12s, 24s, capped at 30s
    private var reconnectDelay: TimeInterval = 3.0
    private let maxReconnectDelay: TimeInterval = 30.0
    private let maxReconnectAttempts = 50

    var isRunning: Bool {
        state == .mining || state == .connecting
    }

    var statusText: String {
        switch state {
        case .idle:       return "Idle"
        case .connecting:
            return reconnectCount > 0 ? "Reconnecting (\(reconnectCount))..." : "Connecting..."
        case .mining:     return devFee.isDevMining ? "Dev Fee" : "Mining"
        }
    }

    var formattedElapsedTime: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var formattedHashRate: String {
        let rate = engine.hashesPerSecond
        if rate >= 1_000_000_000 {
            return String(format: "%.2f GH/s", rate / 1_000_000_000)
        } else if rate >= 1_000_000 {
            return String(format: "%.2f MH/s", rate / 1_000_000)
        } else if rate >= 1_000 {
            return String(format: "%.2f KH/s", rate / 1_000)
        } else {
            return String(format: "%.0f H/s", rate)
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard state == .idle else { return }

        loadSettings()

        guard !stratum.poolHost.isEmpty, !stratum.walletAddress.isEmpty else {
            return
        }

        userStopped = false
        state = .connecting
        elapsedSeconds = 0
        sharesSubmitted = 0
        reconnectCount = 0
        reconnectDelay = 3.0
        sessionStartAccepted = 0
        sessionStartRejected = 0
        lastRecordedHashes = 0

        // Request notification permission (no-op if already granted)
        NotificationManager.shared.requestPermission()
        NotificationManager.shared.reset()

        // Record session in global stats
        globalStats.recordSessionStart()

        // Wire up callbacks
        stratum.onNewJob = { [weak self] job in
            self?.handleNewJob(job)
        }

        engine.onShareFound = { [weak self] share in
            self?.handleShareFound(share)
        }

        stratum.onDisconnect = { [weak self] in
            self?.handleDisconnect()
        }

        // Enable background if toggled
        if backgroundMining {
            backgroundHelper.enableBackground()
        }

        stratum.resetShareCounts()
        connectAndAuth()
    }

    func stop() {
        guard state != .idle else { return }

        userStopped = true

        // Cancel any pending reconnect
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        authPollTimer?.invalidate()
        authPollTimer = nil

        // Flush final global stats before stopping
        flushGlobalStats()

        engine.stopMining()
        timer?.invalidate()
        timer = nil
        globalStatsTimer?.invalidate()
        globalStatsTimer = nil
        stratum.onNewJob = nil
        stratum.onDisconnect = nil
        engine.onShareFound = nil
        stratum.disconnect()
        devFee.stop()
        stats.stopSampling()
        backgroundHelper.disableBackground()
        state = .idle

        // Update widget to show stopped state
        SharedMiningData.writeStopped()
        SharedMiningData.reloadWidgets()
    }

    // MARK: - Connection

    /// Connect to pool and poll for authorization. Used for both initial connect and reconnects.
    private func connectAndAuth() {
        stratum.disconnect()
        stratum.connect()

        // Poll for authorization
        authPollTimer?.invalidate()
        authPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] pollTimer in
            guard let self else { pollTimer.invalidate(); return }

            if self.stratum.connectionState == .authorized {
                pollTimer.invalidate()
                self.authPollTimer = nil

                // Reset backoff on success
                self.reconnectDelay = 3.0

                if self.state == .connecting {
                    // First connection or reconnect succeeded
                    self.state = .mining

                    // Only start timers if they aren't already running (reconnect case)
                    if self.timer == nil {
                        self.startTimer()
                    }
                    if self.globalStatsTimer == nil {
                        self.startGlobalStatsTracking()
                    }

                    if !self.silentMode {
                        self.stats.startSampling(engine: self.engine, stratum: self.stratum)
                        SharedMiningData.reloadWidgets()
                    }
                }

                // Resume mining with current or pending job
                if let job = self.stratum.currentJob {
                    self.handleNewJob(job)
                }
            } else if case .error = self.stratum.connectionState {
                pollTimer.invalidate()
                self.authPollTimer = nil
                // Don't go idle — let handleDisconnect manage reconnect
            } else if self.userStopped {
                pollTimer.invalidate()
                self.authPollTimer = nil
            }
        }
    }

    // MARK: - Auto-Reconnect

    private func handleDisconnect() {
        // Don't reconnect if user explicitly stopped
        guard !userStopped else { return }
        guard reconnectCount < maxReconnectAttempts else {
            stratum.log("Max reconnect attempts (\(maxReconnectAttempts)) reached — giving up")
            NotificationManager.shared.notifyError("Mining stopped: too many reconnect failures")
            // Go idle
            engine.stopMining()
            state = .idle
            return
        }

        // Stop mining engine while disconnected (it would produce shares with no connection)
        engine.stopMining()
        state = .connecting
        reconnectCount += 1

        let delay = reconnectDelay
        stratum.log("Reconnecting in \(Int(delay))s (attempt \(reconnectCount))...")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, !self.userStopped else { return }
            self.connectAndAuth()
        }

        // Increase backoff for next time
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
    }

    // MARK: - Job Handling

    private func handleNewJob(_ job: StratumJob) {
        guard state == .mining else { return }

        engine.startMining(
            job: job,
            extranonce1: stratum.extranonce1,
            extranonce2Size: stratum.extranonce2Size,
            difficulty: stratum.difficulty
        )
    }

    private func handleShareFound(_ share: ShareResult) {
        sharesSubmitted += 1

        stratum.submitShare(
            jobId: share.jobId,
            extranonce2: share.extranonce2,
            ntime: share.ntime,
            nonce: share.nonce
        )

        // Check dev fee after share is submitted
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            let _ = self.devFee.onUserShareAccepted(userAcceptedTotal: self.stratum.acceptedShares)
        }
    }

    // MARK: - Global Stats Tracking

    private func startGlobalStatsTracking() {
        globalStatsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.flushGlobalStats()
        }
    }

    private func flushGlobalStats() {
        // Hashes delta
        let currentHashes = engine.totalHashes
        if currentHashes > lastRecordedHashes {
            globalStats.addHashes(currentHashes - lastRecordedHashes)
            lastRecordedHashes = currentHashes
        }

        // Shares delta
        let currentAccepted = stratum.acceptedShares
        let currentRejected = stratum.rejectedShares
        while sessionStartAccepted < currentAccepted {
            sessionStartAccepted += 1
            globalStats.addAcceptedShare()
        }
        while sessionStartRejected < currentRejected {
            sessionStartRejected += 1
            globalStats.addRejectedShare()
        }

        // Mining time
        globalStats.addMiningSeconds(5)

        // Best hashrate
        globalStats.updateBestHashrate(engine.hashesPerSecond)

        globalStats.save()

        // Write shared data for widget (skip in silent mode)
        if !silentMode {
            SharedMiningData.write(
                isMining: state == .mining,
                hashrate: engine.hashesPerSecond,
                accepted: stratum.acceptedShares,
                rejected: stratum.rejectedShares,
                pool: "\(stratum.poolHost):\(stratum.poolPort)",
                uptime: elapsedSeconds,
                totalHashes: globalStats.formattedTotalHashes,
                totalAccepted: globalStats.totalAcceptedShares,
                bestHashrate: globalStats.bestHashrate
            )
        }
    }

    // MARK: - Private

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        stratum.poolHost = defaults.string(forKey: "poolHost") ?? ""
        stratum.poolPort = UInt16(defaults.string(forKey: "poolPort") ?? "3333") ?? 3333
        stratum.walletAddress = defaults.string(forKey: "walletAddress") ?? ""
        stratum.workerName = defaults.string(forKey: "workerName") ?? ""
        stratum.workerPassword = defaults.string(forKey: "workerPassword") ?? "x"

        // Load thread / mode settings
        let maxThreads = ProcessInfo.processInfo.activeProcessorCount
        let modeRaw = defaults.string(forKey: "miningMode") ?? MiningMode.eco.rawValue
        let mode = MiningMode(rawValue: modeRaw) ?? .eco
        let savedThreads = defaults.integer(forKey: "threadCount")
        engine.threadCount = savedThreads > 0
            ? min(savedThreads, maxThreads)
            : mode.defaultThreadCount(maxThreads: maxThreads)

        backgroundMining = defaults.bool(forKey: "backgroundMining")
        silentMode = defaults.bool(forKey: "silentMode")
    }
}

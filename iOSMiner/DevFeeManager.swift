//
//  DevFeeManager.swift
//  iOSMiner
//
//  1% dev fee: every 100 accepted shares, 1 share is mined for the dev wallet.
//  Uses a separate stratum connection to hmpool.io:3337.
//
//  The dev fee runs in the background without interrupting user mining.
//  It connects, mines until one share is accepted, then disconnects.
//

import Foundation

@Observable
final class DevFeeManager {
    // Dev fee config — hardcoded
    static let devWallet = "16JXoJL46hAZSjtWrKYyoMcur1VtwWAbeB"
    static let devPool = "hmpool.io"
    static let devPort: UInt16 = 3337
    static let feeInterval = 100  // 1 in every 100 shares

    private(set) var devSharesSubmitted: Int = 0
    private(set) var isDevMining = false

    private var devStratum: StratumClient?
    private var devEngine: MiningEngine?
    private var lastTriggeredAt: Int = 0  // last userAcceptedTotal that triggered a cycle
    private var retryTimer: Timer?
    private var watchTimer: Timer?

    /// Call this every time a user share is accepted.
    /// Returns true if this share triggered a dev fee cycle.
    func onUserShareAccepted(userAcceptedTotal: Int) -> Bool {
        // Every feeInterval accepted shares, we owe 1 dev share
        let owedShares = userAcceptedTotal / Self.feeInterval
        if owedShares > devSharesSubmitted && !isDevMining {
            startDevMining()
            return true
        }
        return false
    }

    func stop() {
        cleanup()
    }

    // MARK: - Private

    private func cleanup() {
        devEngine?.stopMining()
        devEngine?.onShareFound = nil
        devStratum?.onNewJob = nil
        devStratum?.disconnect()
        devEngine = nil
        devStratum = nil
        retryTimer?.invalidate()
        retryTimer = nil
        watchTimer?.invalidate()
        watchTimer = nil
        isDevMining = false
    }

    private func startDevMining() {
        guard !isDevMining else { return }
        isDevMining = true

        print("[DevFee] Starting dev fee cycle (submitted so far: \(devSharesSubmitted))")

        // Create fresh instances each cycle to avoid stale state
        let stratum = StratumClient()
        let engine = MiningEngine()
        self.devStratum = stratum
        self.devEngine = engine

        stratum.poolHost = Self.devPool
        stratum.poolPort = Self.devPort
        stratum.walletAddress = Self.devWallet
        stratum.workerName = "iosminer"
        stratum.workerPassword = "x"

        stratum.onNewJob = { [weak self] job in
            self?.handleDevJob(job)
        }

        engine.onShareFound = { [weak self] share in
            self?.handleDevShareFound(share)
        }

        engine.threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)

        stratum.connect()

        // Poll for auth with a timeout
        var pollCount = 0
        retryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard let stratum = self.devStratum else { timer.invalidate(); return }

            pollCount += 1

            if stratum.connectionState == .authorized {
                timer.invalidate()
                self.retryTimer = nil
                print("[DevFee] Authorized on dev pool, mining...")
                if let job = stratum.currentJob {
                    self.handleDevJob(job)
                }
                // Start a watchdog: if no share accepted in 3 minutes, give up
                self.startWatchdog()
            } else if case .error = stratum.connectionState {
                timer.invalidate()
                self.retryTimer = nil
                print("[DevFee] Connection failed, skipping dev share")
                self.cleanup()
            } else if pollCount > 20 { // 10 seconds timeout
                timer.invalidate()
                self.retryTimer = nil
                print("[DevFee] Auth timeout, skipping dev share")
                self.cleanup()
            }
        }
    }

    private func startWatchdog() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: false) { [weak self] _ in
            guard let self, self.isDevMining else { return }
            print("[DevFee] Watchdog timeout (3 min), ending dev cycle")
            self.devSharesSubmitted += 1 // count it anyway to avoid blocking
            self.cleanup()
        }
    }

    private func handleDevJob(_ job: StratumJob) {
        guard isDevMining, let engine = devEngine, let stratum = devStratum else { return }

        engine.startMining(
            job: job,
            extranonce1: stratum.extranonce1,
            extranonce2Size: stratum.extranonce2Size,
            difficulty: stratum.difficulty
        )
    }

    private func handleDevShareFound(_ share: ShareResult) {
        guard isDevMining, let stratum = devStratum else { return }

        stratum.submitShare(
            jobId: share.jobId,
            extranonce2: share.extranonce2,
            ntime: share.ntime,
            nonce: share.nonce
        )

        // Poll for acceptance — check multiple times over a few seconds
        var checks = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard let stratum = self.devStratum else { timer.invalidate(); return }
            checks += 1

            if stratum.acceptedShares > 0 {
                timer.invalidate()
                self.devSharesSubmitted += 1
                print("[DevFee] Dev share ACCEPTED (\(self.devSharesSubmitted) total)")
                self.cleanup()
            } else if checks >= 10 { // 5 seconds
                timer.invalidate()
                // Share might have been rejected, but keep trying with next share
                print("[DevFee] Dev share not confirmed after 5s, continuing to mine...")
            }
        }
    }
}

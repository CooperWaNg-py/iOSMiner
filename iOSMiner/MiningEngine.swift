//
//  MiningEngine.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import Foundation
import CryptoKit

// MARK: - Share Result

struct ShareResult: Sendable {
    let jobId: String
    let extranonce2: String
    let ntime: String
    let nonce: String
    let hashHex: String
}

// MARK: - Mining Engine

/// Performs actual SHA-256d proof-of-work mining on background threads.
/// Each thread gets a unique extranonce2 value and iterates the full 4-byte
/// nonce space. This ensures every submitted share has a unique
/// (extranonce2, nonce) pair so pools don't reject duplicates.
@Observable
final class MiningEngine: @unchecked Sendable {

    private(set) var hashesPerSecond: Double = 0
    private(set) var totalHashes: UInt64 = 0
    private(set) var isMining = false

    /// Called on the main thread when a valid share is found.
    @ObservationIgnored var onShareFound: ((ShareResult) -> Void)?

    @ObservationIgnored private var workerTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hashCounter: UInt64 = 0
    @ObservationIgnored private var hashRateTimer: Timer?
    @ObservationIgnored private let hashCounterLock = NSLock()
    @ObservationIgnored private var _shouldStop = false

    /// Global extranonce2 counter — incremented across jobs so we never reuse values.
    @ObservationIgnored private var extranonce2Counter: UInt64 = 0

    /// Number of CPU threads to use for mining.
    var threadCount: Int = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

    // MARK: - Start / Stop

    func startMining(
        job: StratumJob,
        extranonce1: String,
        extranonce2Size: Int,
        difficulty: Double
    ) {
        stopMining()
        isMining = true
        _shouldStop = false
        hashCounter = 0
        totalHashes = 0
        hashesPerSecond = 0

        let target = DifficultyUtil.targetBytes(for: difficulty)
        let jobId = job.jobId
        let ntime = job.ntime

        print("[MiningEngine] Starting job \(jobId) diff=\(difficulty) target=\(HexUtil.hex(from: target).prefix(16))... threads=\(threadCount)")
        print("[MiningEngine] version(BE)=\(job.version) ntime(BE)=\(job.ntime) nbits(BE)=\(job.nbits)")

        // Build header fields in little-endian for the block header.
        // Stratum sends version, ntime, nbits as BIG-ENDIAN hex.
        // The Bitcoin block header needs them in LITTLE-ENDIAN, so we reverse each.
        guard let versionBE = HexUtil.data(from: job.version),
              let ntimeBE = HexUtil.data(from: job.ntime),
              let nbitsBE = HexUtil.data(from: job.nbits),
              let prevHashData = decodePrevHash(job.prevHash)
        else {
            isMining = false
            return
        }

        let versionLE = Data(versionBE.reversed())  // BE → LE
        let ntimeLE = Data(ntimeBE.reversed())      // BE → LE
        let nbitsLE = Data(nbitsBE.reversed())      // BE → LE

        // Start hash rate sampling timer
        startHashRateTimer()

        // Each thread gets a unique extranonce2 and mines the full 4-byte nonce range.
        for _ in 0..<threadCount {
            // Assign a unique extranonce2 to this thread
            let en2Value = extranonce2Counter
            extranonce2Counter += 1

            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }

                // Build extranonce2 hex for this thread
                let en2Hex = Self.formatExtranonce2(en2Value, size: extranonce2Size)

                // Build this thread's unique header (different extranonce2 → different merkle root)
                guard let header76 = Self.buildHeader(
                    job: job,
                    extranonce1: extranonce1,
                    extranonce2Hex: en2Hex,
                    versionLE: versionLE,
                    prevHashData: prevHashData,
                    ntimeLE: ntimeLE,
                    nbitsLE: nbitsLE
                ) else { return }

                self.mineRange(
                    headerData: header76,
                    startNonce: 0,
                    endNonce: UInt32.max,
                    target: target,
                    jobId: jobId,
                    extranonce2Hex: en2Hex,
                    ntime: ntime
                )
            }
            workerTasks.append(task)
        }
    }

    func stopMining() {
        _shouldStop = true
        isMining = false
        for task in workerTasks {
            task.cancel()
        }
        workerTasks.removeAll()
        hashRateTimer?.invalidate()
        hashRateTimer = nil
    }

    // MARK: - Extranonce2 Formatting

    /// Format a UInt64 counter into a zero-padded hex string of the given byte size.
    /// e.g. value=5, size=4 → "00000005"
    private nonisolated static func formatExtranonce2(_ value: UInt64, size: Int) -> String {
        let hexChars = size * 2
        let hex = String(value, radix: 16)
        if hex.count >= hexChars {
            return String(hex.suffix(hexChars))
        }
        return String(repeating: "0", count: hexChars - hex.count) + hex
    }

    // MARK: - Header Construction

    /// Build a 76-byte block header in standard Bitcoin little-endian format.
    /// This matches NightMiner and other reference implementations.
    ///
    /// Block header (80 bytes):
    ///   version     (4 bytes, LE)
    ///   prevHash    (32 bytes, internal byte order from chunk-swapping stratum prevhash)
    ///   merkleRoot  (32 bytes, raw SHA256d output = internal byte order)
    ///   ntime       (4 bytes, LE)
    ///   nbits       (4 bytes, LE)
    ///   nonce       (4 bytes, LE)   ← we iterate this
    private nonisolated static func buildHeader(
        job: StratumJob,
        extranonce1: String,
        extranonce2Hex: String,
        versionLE: Data,
        prevHashData: Data,
        ntimeLE: Data,
        nbitsLE: Data
    ) -> Data? {
        // 1. Construct coinbase transaction
        let coinbaseHex = job.coinbase1 + extranonce1 + extranonce2Hex + job.coinbase2
        guard let coinbaseData = HexUtil.data(from: coinbaseHex) else { return nil }

        // 2. Hash coinbase → merkle root (raw SHA256d output, internal byte order)
        var merkleHash = SHA256d.hash(coinbaseData)
        for branchHex in job.merkleBranch {
            guard let branchData = HexUtil.data(from: branchHex) else { return nil }
            var combined = Data()
            combined.append(merkleHash)
            combined.append(branchData)
            merkleHash = SHA256d.hash(combined)
        }

        // 3. Assemble 76-byte header (without nonce)
        var header = Data(capacity: 76)
        header.append(contentsOf: versionLE)         // 4 bytes (little-endian)
        header.append(contentsOf: prevHashData)       // 32 bytes (chunk-swapped)
        header.append(contentsOf: merkleHash)         // 32 bytes (raw hash)
        header.append(contentsOf: ntimeLE)            // 4 bytes (little-endian)
        header.append(contentsOf: nbitsLE)            // 4 bytes (little-endian)

        guard header.count == 76 else { return nil }
        return header
    }

    /// Decode stratum prevhash: reverse each 4-byte word.
    /// Stratum sends prevhash in a word-swapped format.
    /// swap_endian_words() reverses each 4-byte chunk to get internal byte order.
    private func decodePrevHash(_ hex: String) -> Data? {
        guard let raw = HexUtil.data(from: hex), raw.count == 32 else { return nil }
        var result = Data(capacity: 32)
        for i in stride(from: 0, to: 32, by: 4) {
            // Reverse each 4-byte chunk
            result.append(raw[i + 3])
            result.append(raw[i + 2])
            result.append(raw[i + 1])
            result.append(raw[i + 0])
        }
        return result
    }

    // MARK: - Mining Loop

    private nonisolated func mineRange(
        headerData: Data,
        startNonce: UInt32,
        endNonce: UInt32,
        target: Data,
        jobId: String,
        extranonce2Hex: String,
        ntime: String
    ) {
        var header = headerData
        // Append 4 placeholder bytes for nonce
        header.append(contentsOf: [0, 0, 0, 0])

        let nonceOffset = 76
        var localCount: UInt64 = 0
        let reportInterval: UInt64 = 65536
        var debugged = false

        var nonce = startNonce

        while nonce <= endNonce {
            if Task.isCancelled || _shouldStop { return }

            // Write nonce (little-endian) into header bytes 76..79
            header[nonceOffset + 0] = UInt8(nonce & 0xFF)
            header[nonceOffset + 1] = UInt8((nonce >> 8) & 0xFF)
            header[nonceOffset + 2] = UInt8((nonce >> 16) & 0xFF)
            header[nonceOffset + 3] = UInt8((nonce >> 24) & 0xFF)

            // Double SHA-256 directly on the 80-byte LE header
            let hash = SHA256d.hash(header)

            localCount += 1

            // Debug: print first header for verification
            if !debugged {
                let headerHex = HexUtil.hex(from: header)
                let hashHex = HexUtil.hex(from: Data(hash.reversed()))
                print("[MiningEngine] DEBUG header (80B LE): \(headerHex)")
                print("[MiningEngine] DEBUG hash (BE disp): \(hashHex)")
                debugged = true
            }

            // Check against target (hash is in internal byte order; reverse to BE for comparison)
            if DifficultyUtil.hashMeetsTarget(hash: hash, target: target) {
                // Submit nonce as BIG-ENDIAN hex.
                // NightMiner: hexlify(nonce_bin[::-1]) — reverse the LE bytes to BE for submission.
                // nonce_bin (LE) = [lo, ..., hi], reversed = [hi, ..., lo] = BE
                let nonceBE = String(format: "%08x", nonce)
                let hashHex = HexUtil.hex(from: Data(hash.reversed()))

                let share = ShareResult(
                    jobId: jobId,
                    extranonce2: extranonce2Hex,
                    ntime: ntime,
                    nonce: nonceBE,
                    hashHex: hashHex
                )

                print("[MiningEngine] SHARE FOUND! nonce=\(nonceBE) (value=\(nonce)) hash=\(hashHex.prefix(16))...")

                let callback = self.onShareFound
                DispatchQueue.main.async {
                    callback?(share)
                }
            }

            // Report hashes periodically for hashrate calculation
            if localCount % reportInterval == 0 {
                self.hashCounterLock.lock()
                self.hashCounter += reportInterval
                self.hashCounterLock.unlock()
            }

            if nonce == endNonce { break }
            nonce &+= 1
        }

        // Report remaining hashes
        let remainder = localCount % reportInterval
        if remainder > 0 {
            self.hashCounterLock.lock()
            self.hashCounter += remainder
            self.hashCounterLock.unlock()
        }
    }

    // MARK: - Hash Rate Tracking

    private func startHashRateTimer() {
        var lastCount: UInt64 = 0

        hashRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.hashCounterLock.lock()
            let currentCount = self.hashCounter
            self.hashCounterLock.unlock()

            let delta = currentCount - lastCount
            lastCount = currentCount
            self.totalHashes = currentCount
            self.hashesPerSecond = Double(delta)
        }
    }
}

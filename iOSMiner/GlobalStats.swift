//
//  GlobalStats.swift
//  iOSMiner
//
//  Persistent lifetime mining statistics across all sessions.
//  Stored in UserDefaults and updated live during mining.
//

import Foundation

@Observable
final class GlobalStats {
    // Persisted lifetime totals
    private(set) var totalHashes: UInt64 = 0
    private(set) var totalAcceptedShares: Int = 0
    private(set) var totalRejectedShares: Int = 0
    private(set) var totalMiningSeconds: Int = 0
    private(set) var totalSessions: Int = 0
    private(set) var bestHashrate: Double = 0

    // Keys
    private enum Keys {
        static let totalHashes = "global_totalHashes"
        static let totalAccepted = "global_totalAccepted"
        static let totalRejected = "global_totalRejected"
        static let totalSeconds = "global_totalSeconds"
        static let totalSessions = "global_totalSessions"
        static let bestHashrate = "global_bestHashrate"
    }

    init() {
        load()
    }

    // MARK: - Load / Save

    private func load() {
        let d = UserDefaults.standard
        // UInt64 doesn't have a native UserDefaults method; store as two Int32 or as String
        if let hashStr = d.string(forKey: Keys.totalHashes), let val = UInt64(hashStr) {
            totalHashes = val
        }
        totalAcceptedShares = d.integer(forKey: Keys.totalAccepted)
        totalRejectedShares = d.integer(forKey: Keys.totalRejected)
        totalMiningSeconds = d.integer(forKey: Keys.totalSeconds)
        totalSessions = d.integer(forKey: Keys.totalSessions)
        bestHashrate = d.double(forKey: Keys.bestHashrate)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(String(totalHashes), forKey: Keys.totalHashes)
        d.set(totalAcceptedShares, forKey: Keys.totalAccepted)
        d.set(totalRejectedShares, forKey: Keys.totalRejected)
        d.set(totalMiningSeconds, forKey: Keys.totalSeconds)
        d.set(totalSessions, forKey: Keys.totalSessions)
        d.set(bestHashrate, forKey: Keys.bestHashrate)
    }

    // MARK: - Update Methods

    func recordSessionStart() {
        totalSessions += 1
        save()
    }

    func addHashes(_ count: UInt64) {
        totalHashes += count
    }

    func addAcceptedShare() {
        totalAcceptedShares += 1
        save()
    }

    func addRejectedShare() {
        totalRejectedShares += 1
        save()
    }

    func addMiningSeconds(_ seconds: Int) {
        totalMiningSeconds += seconds
        save()
    }

    func updateBestHashrate(_ rate: Double) {
        if rate > bestHashrate {
            bestHashrate = rate
            save()
        }
    }

    // MARK: - Formatted Strings

    var formattedTotalHashes: String {
        formatLargeNumber(Double(totalHashes))
    }

    var formattedTotalTime: String {
        let days = totalMiningSeconds / 86400
        let hours = (totalMiningSeconds % 86400) / 3600
        let minutes = (totalMiningSeconds % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var formattedBestHashrate: String {
        formatHashrate(bestHashrate)
    }

    var shareAcceptRate: String {
        let total = totalAcceptedShares + totalRejectedShares
        guard total > 0 else { return "—" }
        let rate = Double(totalAcceptedShares) / Double(total) * 100.0
        return String(format: "%.1f%%", rate)
    }

    private func formatHashrate(_ rate: Double) -> String {
        if rate >= 1_000_000_000 {
            return String(format: "%.2f GH/s", rate / 1_000_000_000)
        } else if rate >= 1_000_000 {
            return String(format: "%.2f MH/s", rate / 1_000_000)
        } else if rate >= 1_000 {
            return String(format: "%.1f KH/s", rate / 1_000)
        }
        return String(format: "%.0f H/s", rate)
    }

    private func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2fT", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "%.2fG", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    func resetAll() {
        totalHashes = 0
        totalAcceptedShares = 0
        totalRejectedShares = 0
        totalMiningSeconds = 0
        totalSessions = 0
        bestHashrate = 0
        save()
    }
}

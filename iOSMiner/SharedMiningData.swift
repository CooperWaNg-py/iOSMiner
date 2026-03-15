//
//  SharedMiningData.swift
//  iOSMiner
//
//  Writes mining state to a shared file so the WidgetKit widget
//  extension can read and display it.
//
//  On jailbreak, App Group UserDefaults(suiteName:) doesn't reliably
//  cross the app/extension boundary without a real provisioning profile.
//  Instead we use a shared JSON file at a known path that both the app
//  and the widget can access (jailbreak removes sandbox restrictions).
//

import Foundation
import WidgetKit

nonisolated enum SharedMiningData {

    /// Shared file path — accessible by both app and widget on jailbreak.
    /// /var/jb/var/mobile/Library/ is writable by the mobile user.
    static let sharedDir  = "/var/jb/var/mobile/Library/iOSMiner"
    static let sharedFile = "/var/jb/var/mobile/Library/iOSMiner/widget.json"

    /// Also try App Group suite as a secondary mechanism
    static let suiteName = "group.com.cooperwang.iosminer"

    // MARK: - Write (called by main app)

    static func write(
        isMining: Bool,
        hashrate: Double,
        accepted: Int,
        rejected: Int,
        pool: String,
        uptime: Int,
        totalHashes: String,
        totalAccepted: Int,
        bestHashrate: Double
    ) {
        let dict: [String: Any] = [
            "isMining": isMining,
            "hashrate": hashrate,
            "accepted": accepted,
            "rejected": rejected,
            "pool": pool,
            "uptime": uptime,
            "lastUpdate": Date().timeIntervalSince1970,
            "totalHashes": totalHashes,
            "totalAccepted": totalAccepted,
            "bestHashrate": bestHashrate,
        ]

        // Write to shared file (primary mechanism on jailbreak)
        writeToFile(dict)

        // Also write to App Group defaults (may work on some setups)
        writeToDefaults(dict)
    }

    static func writeStopped() {
        let dict: [String: Any] = [
            "isMining": false,
            "hashrate": 0.0,
            "accepted": 0,
            "rejected": 0,
            "pool": "",
            "uptime": 0,
            "lastUpdate": Date().timeIntervalSince1970,
            "totalHashes": "0",
            "totalAccepted": 0,
            "bestHashrate": 0.0,
        ]
        writeToFile(dict)
        writeToDefaults(dict)
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Read (called by widget)

    static func read() -> [String: Any]? {
        // Try shared file first (primary on jailbreak)
        if let data = readFromFile() {
            return data
        }
        // Fallback to App Group defaults
        return readFromDefaults()
    }

    // MARK: - File I/O

    private static func writeToFile(_ dict: [String: Any]) {
        do {
            // Ensure directory exists
            let fm = FileManager.default
            if !fm.fileExists(atPath: sharedDir) {
                try fm.createDirectory(atPath: sharedDir, withIntermediateDirectories: true)
            }

            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            try data.write(to: URL(fileURLWithPath: sharedFile), options: .atomic)
        } catch {
            print("[SharedMiningData] File write error: \(error)")
        }
    }

    private static func readFromFile() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sharedFile)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }

    // MARK: - UserDefaults I/O (secondary)

    private static func writeToDefaults(_ dict: [String: Any]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        for (key, value) in dict {
            defaults.set(value, forKey: "w_\(key)")
        }
        defaults.synchronize()
    }

    private static func readFromDefaults() -> [String: Any]? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        // Check if any data was written
        guard defaults.object(forKey: "w_lastUpdate") != nil else { return nil }
        return [
            "isMining": defaults.bool(forKey: "w_isMining"),
            "hashrate": defaults.double(forKey: "w_hashrate"),
            "accepted": defaults.integer(forKey: "w_accepted"),
            "rejected": defaults.integer(forKey: "w_rejected"),
            "pool": defaults.string(forKey: "w_pool") ?? "",
            "uptime": defaults.integer(forKey: "w_uptime"),
            "lastUpdate": defaults.double(forKey: "w_lastUpdate"),
            "totalHashes": defaults.string(forKey: "w_totalHashes") ?? "0",
            "totalAccepted": defaults.integer(forKey: "w_totalAccepted"),
            "bestHashrate": defaults.double(forKey: "w_bestHashrate"),
        ]
    }
}

//
//  iOSMinerWidget.swift
//  iOSMiner Widget Extension
//
//  WidgetKit widget showing live mining stats on the home screen.
//  Reads data from shared UserDefaults (App Group).
//

import WidgetKit
import SwiftUI

// MARK: - Shared Constants

/// App Group suite name — must match the main app
private let suiteName = "group.com.cooperwang.iosminer"

/// Shared file path — primary data exchange on jailbreak.
/// App Group UserDefaults doesn't reliably cross app/extension boundary
/// without a real provisioning profile, so we use a shared JSON file.
private let sharedFilePath = "/var/jb/var/mobile/Library/iOSMiner/widget.json"

/// Shared UserDefaults keys (prefixed with w_ to avoid collisions)
private enum WKey {
    static let isMining      = "w_isMining"
    static let hashrate      = "w_hashrate"
    static let accepted      = "w_accepted"
    static let rejected      = "w_rejected"
    static let pool          = "w_pool"
    static let uptime        = "w_uptime"
    static let lastUpdate    = "w_lastUpdate"
    static let totalHashes   = "w_totalHashes"
    static let totalAccepted = "w_totalAccepted"
    static let bestHashrate  = "w_bestHashrate"
}

// MARK: - Timeline Entry

struct MinerEntry: TimelineEntry {
    let date: Date
    let isMining: Bool
    let hashrate: Double
    let accepted: Int
    let rejected: Int
    let pool: String
    let uptime: Int
    let lastUpdate: Date
    let totalHashes: String
    let totalAccepted: Int
    let bestHashrate: Double

    static var placeholder: MinerEntry {
        MinerEntry(
            date: Date(),
            isMining: true,
            hashrate: 48_500,
            accepted: 12,
            rejected: 0,
            pool: "hmpool.io:3337",
            uptime: 3661,
            lastUpdate: Date(),
            totalHashes: "142.3M",
            totalAccepted: 87,
            bestHashrate: 52_000
        )
    }

    static var empty: MinerEntry {
        MinerEntry(
            date: Date(),
            isMining: false,
            hashrate: 0,
            accepted: 0,
            rejected: 0,
            pool: "—",
            uptime: 0,
            lastUpdate: Date(),
            totalHashes: "0",
            totalAccepted: 0,
            bestHashrate: 0
        )
    }
}

// MARK: - Timeline Provider

struct MinerTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinerEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MinerEntry) -> Void) {
        completion(context.isPreview ? .placeholder : readEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinerEntry>) -> Void) {
        // Read current data from the shared file
        let dict = readFromFile() ?? readFromDefaults()

        // Generate a burst of entries spaced 5 seconds apart.
        // iOS will tick through them automatically at each scheduled date,
        // giving the appearance of a near-real-time updating widget.
        // When the last entry is reached (.atEnd), WidgetKit calls us again
        // and we re-read fresh data from the file.
        let now = Date()
        let entryCount = 60          // 60 entries
        let interval: TimeInterval = 5 // 5 seconds apart → 5 minutes total

        var entries: [MinerEntry] = []
        for i in 0..<entryCount {
            let entryDate = now.addingTimeInterval(Double(i) * interval)
            if let dict = dict {
                // Increment uptime for each future entry to keep it ticking
                let baseUptime = dict["uptime"] as? Int ?? 0
                var adjusted = dict
                adjusted["uptime"] = baseUptime + (i * Int(interval))
                entries.append(entryFromDict(adjusted, date: entryDate))
            } else {
                entries.append(MinerEntry.empty)
            }
        }

        // .atEnd: when the last entry expires, call getTimeline again
        // This creates a loop: read fresh data → generate entries → tick → repeat
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func readEntry(at date: Date) -> MinerEntry {
        // Try shared file first (primary on jailbreak)
        if let dict = readFromFile() {
            return entryFromDict(dict, date: date)
        }
        // Fallback to App Group UserDefaults
        if let dict = readFromDefaults() {
            return entryFromDict(dict, date: date)
        }
        return .empty
    }

    private func readFromFile() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sharedFilePath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }

    private func readFromDefaults() -> [String: Any]? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        guard defaults.object(forKey: WKey.lastUpdate) != nil else { return nil }
        return [
            "isMining": defaults.bool(forKey: WKey.isMining),
            "hashrate": defaults.double(forKey: WKey.hashrate),
            "accepted": defaults.integer(forKey: WKey.accepted),
            "rejected": defaults.integer(forKey: WKey.rejected),
            "pool": defaults.string(forKey: WKey.pool) ?? "—",
            "uptime": defaults.integer(forKey: WKey.uptime),
            "lastUpdate": defaults.double(forKey: WKey.lastUpdate),
            "totalHashes": defaults.string(forKey: WKey.totalHashes) ?? "0",
            "totalAccepted": defaults.integer(forKey: WKey.totalAccepted),
            "bestHashrate": defaults.double(forKey: WKey.bestHashrate),
        ]
    }

    private func entryFromDict(_ dict: [String: Any], date: Date = Date()) -> MinerEntry {
        let isMining      = dict["isMining"] as? Bool ?? false
        let hashrate       = dict["hashrate"] as? Double ?? 0
        let accepted       = dict["accepted"] as? Int ?? 0
        let rejected       = dict["rejected"] as? Int ?? 0
        let pool           = dict["pool"] as? String ?? "—"
        let uptime         = dict["uptime"] as? Int ?? 0
        let lastUpdateTS   = dict["lastUpdate"] as? Double ?? 0
        let totalHashesStr = dict["totalHashes"] as? String ?? "0"
        let totalAccepted  = dict["totalAccepted"] as? Int ?? 0
        let bestHashrate   = dict["bestHashrate"] as? Double ?? 0

        return MinerEntry(
            date: date,
            isMining: isMining,
            hashrate: hashrate,
            accepted: accepted,
            rejected: rejected,
            pool: pool,
            uptime: uptime,
            lastUpdate: lastUpdateTS > 0 ? Date(timeIntervalSince1970: lastUpdateTS) : Date(),
            totalHashes: totalHashesStr,
            totalAccepted: totalAccepted,
            bestHashrate: bestHashrate
        )
    }
}

// MARK: - Small Widget View

struct MinerWidgetSmallView: View {
    let entry: MinerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: entry.isMining ? "bolt.fill" : "bolt.slash.fill")
                    .font(.caption)
                    .foregroundStyle(entry.isMining ? .green : .gray)
                Text("iOSMiner")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }

            Text(entry.isMining ? "Mining" : "Stopped")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(entry.isMining ? .green : .secondary)

            Spacer()

            // Hashrate
            Text(formatHashrate(entry.hashrate))
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(entry.isMining ? .green : .secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            // Shares
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("\(entry.accepted)")
                    .font(.system(.caption2, design: .monospaced))
                if entry.rejected > 0 {
                    Text("/")
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                    Text("\(entry.rejected)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }
}

// MARK: - Medium Widget View

struct MinerWidgetMediumView: View {
    let entry: MinerEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left column — status & hashrate
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: entry.isMining ? "bolt.fill" : "bolt.slash.fill")
                        .font(.caption)
                        .foregroundStyle(entry.isMining ? .green : .gray)
                    Text("iOSMiner")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                }

                Text(entry.isMining ? "Mining" : "Stopped")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(entry.isMining ? .green : .secondary)

                Spacer()

                Text(formatHashrate(entry.hashrate))
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(entry.isMining ? .green : .secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(entry.pool)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Divider
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
                .padding(.vertical, 4)

            // Right column — stats
            VStack(alignment: .leading, spacing: 6) {
                statLine(icon: "checkmark.circle.fill", color: .green, label: "Accepted", value: "\(entry.accepted)")
                statLine(icon: "xmark.circle.fill", color: .red, label: "Rejected", value: "\(entry.rejected)")
                statLine(icon: "clock.fill", color: .purple, label: "Uptime", value: formatUptime(entry.uptime))
                statLine(icon: "flame.fill", color: .yellow, label: "Best", value: formatHashrate(entry.bestHashrate))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }

    private func statLine(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Helpers

private func formatHashrate(_ rate: Double) -> String {
    if rate >= 1_000_000_000 {
        return String(format: "%.2f GH/s", rate / 1_000_000_000)
    } else if rate >= 1_000_000 {
        return String(format: "%.1f MH/s", rate / 1_000_000)
    } else if rate >= 1_000 {
        return String(format: "%.1f KH/s", rate / 1_000)
    } else if rate > 0 {
        return String(format: "%.0f H/s", rate)
    }
    return "0 H/s"
}

private func formatUptime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 {
        return "\(h)h \(m)m"
    }
    return "\(m)m"
}

// MARK: - Widget Configuration

@main
struct iOSMinerWidget: Widget {
    let kind: String = "com.cooperwang.iosminer.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MinerTimelineProvider()) { entry in
            Group {
                if #available(iOSApplicationExtension 17.0, *) {
                    WidgetEntryView(entry: entry)
                        .containerBackground(.black, for: .widget)
                } else {
                    WidgetEntryView(entry: entry)
                        .background(.black)
                }
            }
        }
        .configurationDisplayName("iOSMiner")
        .description("Monitor your Bitcoin mining status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MinerEntry

    var body: some View {
        switch family {
        case .systemSmall:
            MinerWidgetSmallView(entry: entry)
        case .systemMedium:
            MinerWidgetMediumView(entry: entry)
        default:
            MinerWidgetSmallView(entry: entry)
        }
    }
}

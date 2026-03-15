//
//  NotificationManager.swift
//  iOSMiner
//
//  Local notification system for mining events.
//  - Share accepted / rejected
//  - Pool disconnection or error
//  - Configurable: on/off, share notification frequency
//

import Foundation
import UserNotifications

nonisolated enum MiningNotification {
    /// Frequency options for share notifications.
    enum ShareFrequency: String, CaseIterable, Identifiable, Sendable {
        case every   = "every"
        case every5  = "every5"
        case every10 = "every10"
        case every25 = "every25"
        case never   = "never"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .every:   return "Every Share"
            case .every5:  return "Every 5"
            case .every10: return "Every 10"
            case .every25: return "Every 25"
            case .never:   return "Never"
            }
        }

        var interval: Int {
            switch self {
            case .every:   return 1
            case .every5:  return 5
            case .every10: return 10
            case .every25: return 25
            case .never:   return 0
            }
        }
    }
}

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    private var authorized = false
    private var lastNotifiedAccepted = 0
    private var lastNotifiedRejected = 0

    private init() {}

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    // MARK: - Share Notifications

    /// Call after each accepted share. Sends notification based on frequency setting.
    func notifyShareAccepted(total: Int) {
        guard enabled, authorized else { return }
        let freq = shareFrequency
        guard freq != .never, freq.interval > 0 else { return }

        // Only notify at the right intervals
        let prevMilestone = lastNotifiedAccepted / freq.interval
        let curMilestone = total / freq.interval
        guard curMilestone > prevMilestone else { return }
        lastNotifiedAccepted = total

        send(
            title: "Share Accepted",
            body: "Total: \(total) accepted shares",
            id: "share-accepted-\(total)"
        )
    }

    func notifyShareRejected(total: Int, reason: String) {
        guard enabled, authorized else { return }
        guard shareFrequency != .never else { return }
        guard total > lastNotifiedRejected else { return }
        lastNotifiedRejected = total

        send(
            title: "Share Rejected",
            body: reason.isEmpty ? "Rejected shares: \(total)" : reason,
            id: "share-rejected-\(total)"
        )
    }

    // MARK: - Connection Notifications

    func notifyDisconnected(reason: String) {
        guard connectionAlertsEnabled, authorized else { return }
        send(
            title: "Pool Disconnected",
            body: reason,
            id: "disconnect-\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifyError(_ message: String) {
        guard connectionAlertsEnabled, authorized else { return }
        send(
            title: "Mining Error",
            body: message,
            id: "error-\(Int(Date().timeIntervalSince1970))"
        )
    }

    // MARK: - Reset

    func reset() {
        lastNotifiedAccepted = 0
        lastNotifiedRejected = 0
    }

    // MARK: - Settings Access

    var enabled: Bool {
        UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }

    var connectionAlertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "connectionNotifications")
    }

    var shareFrequency: MiningNotification.ShareFrequency {
        let raw = UserDefaults.standard.string(forKey: "shareNotificationFreq") ?? "every10"
        return MiningNotification.ShareFrequency(rawValue: raw) ?? .every10
    }

    // MARK: - Private

    private func send(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

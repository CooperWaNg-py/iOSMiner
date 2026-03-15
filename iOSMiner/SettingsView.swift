//
//  SettingsView.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Bindable var miningManager: MiningManager

    private var stratum: StratumClient { miningManager.stratum }
    private var engine: MiningEngine { miningManager.engine }

    @AppStorage("poolHost") private var poolHost = ""
    @AppStorage("poolPort") private var poolPort = "3333"
    @AppStorage("poolPresetId") private var poolPresetId = "custom"
    @AppStorage("walletAddress") private var walletAddress = ""
    @AppStorage("workerName") private var workerName = ""
    @AppStorage("workerPassword") private var workerPassword = "x"
    @AppStorage("miningMode") private var miningModeRaw = MiningMode.eco.rawValue
    @AppStorage("threadCount") private var savedThreadCount = 0
    @AppStorage("backgroundMining") private var backgroundMining = false
    @AppStorage("silentMode") private var silentMode = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("shareNotificationFreq") private var shareNotifFreq = MiningNotification.ShareFrequency.every10.rawValue
    @AppStorage("connectionNotifications") private var connectionNotifications = true

    @State private var showingResetAlert = false

    private var maxThreads: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    private var miningMode: MiningMode {
        get { MiningMode(rawValue: miningModeRaw) ?? .eco }
        set { miningModeRaw = newValue.rawValue }
    }

    private var selectedPreset: PoolPreset? {
        PoolPreset.builtIn.first { $0.id == poolPresetId }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Pool Selection
                poolSection

                // MARK: - Wallet
                Section {
                    TextField("Wallet address", text: $walletAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Wallet")
                } footer: {
                    Text("Your payout wallet address. Used as the primary identity for pool authorization.")
                }

                // MARK: - Worker
                Section {
                    HStack {
                        Text("Worker")
                            .frame(width: 70, alignment: .leading)
                        TextField("worker1 (optional)", text: $workerName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Password")
                            .frame(width: 70, alignment: .leading)
                        SecureField("x", text: $workerPassword)
                    }
                } header: {
                    Text("Worker")
                } footer: {
                    if !walletAddress.isEmpty {
                        Text("Pool identity: **\(workerIdentityPreview)**")
                    }
                }

                // MARK: - Performance
                Section {
                    Picker("Mode", selection: $miningModeRaw) {
                        ForEach(MiningMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: miningModeRaw) { _, newValue in
                        applyModeDefaults(MiningMode(rawValue: newValue) ?? .eco)
                    }

                    HStack {
                        Text("Threads")
                        Spacer()
                        Text("\(effectiveThreadCount) / \(maxThreads)")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                        Stepper("", value: $savedThreadCount, in: 1...maxThreads)
                            .labelsHidden()
                    }

                    Toggle(isOn: $backgroundMining) {
                        Label("Background Mining", systemImage: "moon.fill")
                    }
                    .onChange(of: backgroundMining) { _, newValue in
                        miningManager.backgroundMining = newValue
                    }

                    Toggle(isOn: $silentMode) {
                        Label("Silent Mode", systemImage: "eye.slash.fill")
                    }
                    .onChange(of: silentMode) { _, newValue in
                        miningManager.silentMode = newValue
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(miningMode.description)
                        if backgroundMining {
                            Text("Mining will continue when the app is in the background.")
                                .foregroundStyle(.purple)
                        }
                        if silentMode {
                            Text("Silent: logs, stats sampling, and widget updates are disabled.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // MARK: - Notifications
                notificationsSection

                // MARK: - Connection
                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(stratum.connectionState.displayText)
                            .foregroundStyle(statusColor)
                            .fontWeight(.medium)
                    }

                    if stratum.connectionState.isConnected || stratum.connectionState == .authorized {
                        HStack {
                            Text("Difficulty")
                            Spacer()
                            Text("\(stratum.difficulty, specifier: "%.2f")")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("ExtraNonce1")
                            Spacer()
                            Text(stratum.extranonce1.isEmpty ? "—" : stratum.extranonce1)
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                    }

                    if stratum.acceptedShares > 0 || stratum.rejectedShares > 0 {
                        HStack {
                            Text("Shares")
                            Spacer()
                            Text("\(stratum.acceptedShares) accepted / \(stratum.rejectedShares) rejected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Lifetime Stats
                lifetimeStatsSection

                // MARK: - Dev Fee
                Section {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("1% dev fee")
                        Spacer()
                        Text("\(miningManager.devFee.devSharesSubmitted) shares")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Dev Fee")
                } footer: {
                    Text("1 share every 100 accepted shares is donated to support development.")
                }

                // MARK: - Donation
                donationSection

                // MARK: - Actions
                if !stratum.lastLog.isEmpty {
                    Section("Last Log") {
                        Text(stratum.lastLog)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        saveAndConnect()
                    } label: {
                        Text("Test Connection")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(poolHost.isEmpty || walletAddress.isEmpty)

                    if stratum.connectionState.isConnected {
                        Button(role: .destructive) {
                            stratum.disconnect()
                        } label: {
                            Text("Disconnect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.3.1")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Device")
                        Spacer()
                        Text("\(ProcessInfo.processInfo.activeProcessorCount) cores")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                initializeDefaults()
                syncFromStorage()
            }
            .alert("Reset Lifetime Stats?", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive) {
                    miningManager.globalStats.resetAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently erase all lifetime mining statistics. This cannot be undone.")
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Enable Notifications", systemImage: "bell.fill")
            }
            .onChange(of: notificationsEnabled) { _, enabled in
                if enabled {
                    NotificationManager.shared.requestPermission()
                }
            }

            if notificationsEnabled {
                Picker("Share Alerts", selection: $shareNotifFreq) {
                    ForEach(MiningNotification.ShareFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq.rawValue)
                    }
                }

                Toggle(isOn: $connectionNotifications) {
                    Label("Connection Alerts", systemImage: "wifi.exclamationmark")
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            if notificationsEnabled {
                Text("Share alerts notify at the chosen interval. Connection alerts fire on disconnect or errors.")
            }
        }
    }

    // MARK: - Pool Section

    private var poolSection: some View {
        Section {
            // Pool preset picker
            Picker("Pool", selection: $poolPresetId) {
                ForEach(PoolPreset.builtIn) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .onChange(of: poolPresetId) { _, newId in
                if let preset = PoolPreset.builtIn.first(where: { $0.id == newId }),
                   preset.id != "custom" {
                    poolHost = preset.host
                    poolPort = String(preset.port)
                }
            }

            // Host/port are always editable (even for presets — allows custom ports etc.)
            HStack {
                Text("Host")
                    .frame(width: 50, alignment: .leading)
                TextField("stratum.pool.com", text: $poolHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            HStack {
                Text("Port")
                    .frame(width: 50, alignment: .leading)
                TextField("3333", text: $poolPort)
                    .keyboardType(.numberPad)
            }
        } header: {
            Text("Pool")
        } footer: {
            if let preset = selectedPreset, preset.id != "custom" {
                Text(preset.description + " — Host and port are editable.")
            }
        }
    }

    // MARK: - Lifetime Stats Section

    private var lifetimeStatsSection: some View {
        Section {
            let g = miningManager.globalStats
            statRow("Total Hashes", value: g.formattedTotalHashes, icon: "number", color: .orange)
            statRow("Accepted Shares", value: "\(g.totalAcceptedShares)", icon: "checkmark.circle.fill", color: .green)
            statRow("Rejected Shares", value: "\(g.totalRejectedShares)", icon: "xmark.circle.fill", color: .red)
            statRow("Accept Rate", value: g.shareAcceptRate, icon: "percent", color: .cyan)
            statRow("Best Hashrate", value: g.formattedBestHashrate, icon: "flame.fill", color: .yellow)
            statRow("Total Time", value: g.formattedTotalTime, icon: "clock.fill", color: .purple)
            statRow("Sessions", value: "\(g.totalSessions)", icon: "arrow.clockwise", color: .blue)

            Button(role: .destructive) {
                showingResetAlert = true
            } label: {
                Label("Reset Lifetime Stats", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Lifetime Stats")
        } footer: {
            Text("Persisted across app restarts and sessions.")
        }
    }

    private func statRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Donation Section

    private var donationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Support iOSMiner development:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("16JXoJL46hAZSjtWrKYyoMcur1VtwWAbeB")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = "16JXoJL46hAZSjtWrKYyoMcur1VtwWAbeB"
                    #endif
                } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text("Donate")
        } footer: {
            Text("Thank you for supporting open-source jailbreak development!")
        }
    }

    // MARK: - Helpers

    private var effectiveThreadCount: Int {
        let count = savedThreadCount
        return count > 0 ? min(count, maxThreads) : miningMode.defaultThreadCount(maxThreads: maxThreads)
    }

    private var workerIdentityPreview: String {
        if workerName.isEmpty {
            return walletAddress
        }
        return "\(walletAddress).\(workerName)"
    }

    private var statusColor: Color {
        switch stratum.connectionState {
        case .authorized: return .green
        case .subscribed, .connected: return .orange
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        }
    }

    private func initializeDefaults() {
        if savedThreadCount == 0 {
            savedThreadCount = miningMode.defaultThreadCount(maxThreads: maxThreads)
        }
    }

    private func applyModeDefaults(_ mode: MiningMode) {
        savedThreadCount = mode.defaultThreadCount(maxThreads: maxThreads)
        engine.threadCount = savedThreadCount
    }

    private func syncFromStorage() {
        stratum.poolHost = poolHost
        stratum.poolPort = UInt16(poolPort) ?? 3333
        stratum.walletAddress = walletAddress
        stratum.workerName = workerName
        stratum.workerPassword = workerPassword
        engine.threadCount = effectiveThreadCount
        miningManager.backgroundMining = backgroundMining
        miningManager.silentMode = silentMode
    }

    private func saveAndConnect() {
        syncFromStorage()
        stratum.disconnect()
        stratum.connect()
    }
}

#if DEBUG
#Preview {
    SettingsView(miningManager: MiningManager())
}
#endif

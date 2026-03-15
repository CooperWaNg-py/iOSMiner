//
//  ContentView.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var miningManager = MiningManager()

    var body: some View {
        TabView {
            MinerTab(miningManager: miningManager)
                .tabItem {
                    Label("Miner", systemImage: "bolt.fill")
                }

            StatsView(miningManager: miningManager)
                .tabItem {
                    Label("Stats", systemImage: "chart.xyaxis.line")
                }

            ScreensaverView(miningManager: miningManager)
                .tabItem {
                    Label("Vis", systemImage: "sparkles")
                }

            LogsView(stratum: miningManager.stratum)
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }

            SettingsView(miningManager: miningManager)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

// MARK: - Miner Tab

struct MinerTab: View {
    @Bindable var miningManager: MiningManager

    // Reactive observation of settings so the UI updates when user fills them in
    @AppStorage("poolHost") private var poolHost = ""
    @AppStorage("walletAddress") private var walletAddress = ""

    private var stratum: StratumClient { miningManager.stratum }
    private var engine: MiningEngine { miningManager.engine }

    private var hasPoolSettings: Bool {
        !poolHost.isEmpty && !walletAddress.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Status indicator
            Circle()
                .fill(statusCircleColor)
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: statusIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(statusIconColor)
                )
                .shadow(color: statusGlow, radius: 16)
                .animation(.easeInOut(duration: 0.4), value: miningManager.state)

            // Title and status
            VStack(spacing: 4) {
                Text("iOSMiner")
                    .font(.title)
                    .fontWeight(.bold)

                Text(miningManager.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Hash rate (prominent when mining)
            if miningManager.isRunning {
                Text(miningManager.formattedHashRate)
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
                    .animation(.default, value: engine.hashesPerSecond)
            }

            // Elapsed time
            Text(miningManager.formattedElapsedTime)
                .font(.system(size: miningManager.isRunning ? 20 : 40, weight: .light, design: .monospaced))
                .foregroundStyle(miningManager.isRunning ? .primary : .secondary)

            // Stats panel when mining or connecting
            if miningManager.state != .idle {
                statsPanel
                    .padding(.horizontal, 20)
            }

            Spacer()

            // Pool info hint when idle with no settings
            if miningManager.state == .idle && !hasPoolSettings {
                Text("Configure pool and wallet in Settings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Background indicator
            if miningManager.backgroundHelper.isBackgroundEnabled {
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill")
                        .font(.caption2)
                    Text("Background mining")
                        .font(.caption2)
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.purple.opacity(0.12), in: Capsule())
            }

            // Start / Stop buttons
            HStack(spacing: 16) {
                Button {
                    miningManager.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(miningManager.state != .idle || !hasPoolSettings)

                Button {
                    miningManager.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(miningManager.state == .idle)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Stats Panel

    private var statsPanel: some View {
        VStack(spacing: 0) {
            statRow("Status", value: stratum.connectionState.displayText, color: connectionColor)

            Divider()

            statRow("Difficulty", value: String(format: "%.4g", stratum.difficulty))

            Divider()

            statRow("Shares",
                     value: "\(stratum.acceptedShares) / \(stratum.rejectedShares) rej",
                     color: stratum.rejectedShares > 0 ? .orange : .green)

            Divider()

            statRow("Hashes", value: formatTotalHashes(engine.totalHashes))

            Divider()

            statRow("Threads", value: "\(engine.threadCount)")

            if let job = stratum.currentJob {
                Divider()
                statRow("Job", value: job.jobId)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.vertical, 6)
    }

    private func formatTotalHashes(_ total: UInt64) -> String {
        if total >= 1_000_000_000 {
            return String(format: "%.2f G", Double(total) / 1_000_000_000)
        } else if total >= 1_000_000 {
            return String(format: "%.2f M", Double(total) / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "%.2f K", Double(total) / 1_000)
        }
        return "\(total)"
    }

    // MARK: - Computed Styles

    private var statusCircleColor: Color {
        switch miningManager.state {
        case .idle:       return Color.gray.opacity(0.3)
        case .connecting: return Color.orange.opacity(0.5)
        case .mining:     return Color.green
        }
    }

    private var statusIcon: String {
        switch miningManager.state {
        case .idle:       return "bolt.slash.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .mining:     return "bolt.fill"
        }
    }

    private var statusIconColor: Color {
        switch miningManager.state {
        case .idle:       return .gray
        case .connecting: return .white
        case .mining:     return .white
        }
    }

    private var statusGlow: Color {
        switch miningManager.state {
        case .idle:       return .clear
        case .connecting: return .orange.opacity(0.4)
        case .mining:     return .green.opacity(0.5)
        }
    }

    private var connectionColor: Color {
        switch stratum.connectionState {
        case .authorized: return .green
        case .subscribed, .connected: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif

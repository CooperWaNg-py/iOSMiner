//
//  StatsView.swift
//  iOSMiner
//
//  Live mining statistics dashboard with graphs and real-time numbers.
//

import SwiftUI

// MARK: - Stats Data Model

@Observable
final class MiningStats {
    /// Rolling hashrate samples (last 60 seconds)
    private(set) var hashrateSamples: [Double] = []
    /// Shares accepted over time (cumulative, sampled every 10s)
    private(set) var sharesSamples: [Int] = []
    /// Peak hashrate observed
    private(set) var peakHashrate: Double = 0
    /// Average hashrate since start
    private(set) var avgHashrate: Double = 0
    /// Session start time
    private(set) var sessionStart: Date?
    /// Total accepted shares for this session
    private(set) var sessionShares: Int = 0

    private var hashSum: Double = 0
    private var hashSampleCount: Int = 0
    private var samplingTimer: Timer?

    let maxHashrateSamples = 60
    let maxSharesSamples = 60

    func startSampling(engine: MiningEngine, stratum: StratumClient) {
        sessionStart = Date()
        hashrateSamples = []
        sharesSamples = []
        peakHashrate = 0
        avgHashrate = 0
        hashSum = 0
        hashSampleCount = 0
        sessionShares = 0

        samplingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rate = engine.hashesPerSecond

            // Hashrate rolling window
            self.hashrateSamples.append(rate)
            if self.hashrateSamples.count > self.maxHashrateSamples {
                self.hashrateSamples.removeFirst()
            }

            // Peak & average
            if rate > self.peakHashrate { self.peakHashrate = rate }
            self.hashSum += rate
            self.hashSampleCount += 1
            self.avgHashrate = self.hashSum / Double(self.hashSampleCount)

            // Shares (sample every tick)
            let totalAccepted = stratum.acceptedShares
            self.sessionShares = totalAccepted
            // Add a shares sample every 10 ticks
            if self.hashSampleCount % 10 == 0 {
                self.sharesSamples.append(totalAccepted)
                if self.sharesSamples.count > self.maxSharesSamples {
                    self.sharesSamples.removeFirst()
                }
            }
        }
    }

    func stopSampling() {
        samplingTimer?.invalidate()
        samplingTimer = nil
    }
}

// MARK: - Stats View

struct StatsView: View {
    let miningManager: MiningManager

    private var stats: MiningStats { miningManager.stats }
    private var engine: MiningEngine { miningManager.engine }
    private var stratum: StratumClient { miningManager.stratum }
    private var global: GlobalStats { miningManager.globalStats }

    @State private var showLifetime = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Session / Lifetime toggle
                    Picker("View", selection: $showLifetime) {
                        Text("Session").tag(false)
                        Text("Lifetime").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if showLifetime {
                        lifetimeStatsContent
                    } else {
                        sessionStatsContent
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Stats")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Session Stats

    private var sessionStatsContent: some View {
        VStack(spacing: 16) {
            // Live hashrate card
            hashrateCard

            // Hashrate graph
            graphCard(
                title: "HASHRATE",
                samples: stats.hashrateSamples,
                color: .green,
                formatter: formatHashrate
            )

            // Shares graph
            graphCard(
                title: "SHARES",
                samples: stats.sharesSamples.map { Double($0) },
                color: .cyan,
                formatter: { String(Int($0)) }
            )

            // Detail grid
            detailGrid

            // Session info
            sessionCard
        }
    }

    // MARK: - Lifetime Stats

    private var lifetimeStatsContent: some View {
        VStack(spacing: 16) {
            // Big lifetime hashes card
            lifetimeHashesCard

            // Lifetime detail grid
            lifetimeGrid

            // Per-session averages
            lifetimeAveragesCard
        }
    }

    private var lifetimeHashesCard: some View {
        VStack(spacing: 8) {
            Text("LIFETIME HASHES")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.7))

            Text(global.formattedTotalHashes)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            HStack(spacing: 24) {
                miniStat("BEST RATE", value: global.formattedBestHashrate, color: .yellow)
                miniStat("TOTAL TIME", value: global.formattedTotalTime, color: .purple)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var lifetimeGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 12) {
            detailCard("ACCEPTED", value: "\(global.totalAcceptedShares)", color: .green, icon: "checkmark.circle.fill")
            detailCard("REJECTED", value: "\(global.totalRejectedShares)", color: .red, icon: "xmark.circle.fill")
            detailCard("ACCEPT RATE", value: global.shareAcceptRate, color: .cyan, icon: "percent")
            detailCard("SESSIONS", value: "\(global.totalSessions)", color: .blue, icon: "arrow.clockwise")
            detailCard("BEST HASH", value: global.formattedBestHashrate, color: .yellow, icon: "flame.fill")
            detailCard("TOTAL TIME", value: global.formattedTotalTime, color: .purple, icon: "clock.fill")
        }
    }

    private var lifetimeAveragesCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("AVERAGES")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            let sessCount = max(1, global.totalSessions)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shares / Session")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", Double(global.totalAcceptedShares) / Double(sessCount)))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Time / Session")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    let avgSeconds = global.totalMiningSeconds / sessCount
                    Text(formatDuration(avgSeconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Hashrate Card

    private var hashrateCard: some View {
        VStack(spacing: 8) {
            Text("LIVE HASHRATE")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.green.opacity(0.7))

            Text(formatHashrate(engine.hashesPerSecond))
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: engine.hashesPerSecond)

            HStack(spacing: 24) {
                miniStat("PEAK", value: formatHashrate(stats.peakHashrate), color: .yellow)
                miniStat("AVG", value: formatHashrate(stats.avgHashrate), color: .orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Graph Card

    private func graphCard(
        title: String,
        samples: [Double],
        color: Color,
        formatter: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color.opacity(0.7))
                Spacer()
                if let last = samples.last {
                    Text(formatter(last))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(color)
                }
            }

            // Graph
            GeometryReader { geo in
                let maxVal = samples.max() ?? 1
                let minVal: Double = 0
                let range = max(maxVal - minVal, 1)
                let w = geo.size.width
                let h = geo.size.height

                if samples.count > 1 {
                    // Fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, val) in samples.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(samples.count - 1)
                            let y = h - h * CGFloat((val - minVal) / range)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        for (i, val) in samples.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(samples.count - 1)
                            let y = h - h * CGFloat((val - minVal) / range)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, lineWidth: 2)
                } else {
                    // Not enough data
                    Text("Collecting data...")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 100)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Detail Grid

    private var detailGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 12) {
            detailCard("ACCEPTED", value: "\(stratum.acceptedShares)", color: .green, icon: "checkmark.circle.fill")
            detailCard("REJECTED", value: "\(stratum.rejectedShares)", color: .red, icon: "xmark.circle.fill")
            detailCard("DIFFICULTY", value: String(format: "%.4g", stratum.difficulty), color: .purple, icon: "dial.high.fill")
            detailCard("THREADS", value: "\(engine.threadCount)", color: .blue, icon: "cpu.fill")
            detailCard("TOTAL HASHES", value: formatTotalHashes(engine.totalHashes), color: .orange, icon: "number")
            detailCard("DEV FEE", value: "\(miningManager.devFee.devSharesSubmitted)", color: .pink, icon: "heart.fill")
        }
    }

    private func detailCard(_ title: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Session Card

    private var sessionCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("SESSION")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uptime")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(miningManager.formattedElapsedTime)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(stratum.connectionState.displayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(connectionColor)
                }
            }

            if let job = stratum.currentJob {
                HStack {
                    Text("Job")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(job.jobId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            if miningManager.devFee.isDevMining {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    Text("Dev fee share in progress...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.pink.opacity(0.8))
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func miniStat(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color.opacity(0.6))
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
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

    private func formatTotalHashes(_ total: UInt64) -> String {
        if total >= 1_000_000_000 {
            return String(format: "%.2fG", Double(total) / 1_000_000_000)
        } else if total >= 1_000_000 {
            return String(format: "%.1fM", Double(total) / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "%.1fK", Double(total) / 1_000)
        }
        return "\(total)"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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

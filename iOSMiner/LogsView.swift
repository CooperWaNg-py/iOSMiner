//
//  LogsView.swift
//  iOSMiner
//
//  Live log viewer for stratum communication and mining events.
//

import SwiftUI
import UIKit

struct LogsView: View {
    let stratum: StratumClient

    @State private var autoScroll = true
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Controls bar
                HStack(spacing: 10) {
                    Text("\(stratum.logEntries.count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Toggle("Scroll", isOn: $autoScroll)
                        .font(.caption2)
                        .toggleStyle(.switch)
                        .fixedSize()

                    Button {
                        let allLogs = stratum.logEntries.joined(separator: "\n")
                        UIPasteboard.general.string = allLogs
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(copied ? .green : .accentColor)

                    Button("Clear") {
                        stratum.clearLogs()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // Log entries
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(stratum.logEntries.enumerated()), id: \.offset) { index, entry in
                                Text(entry)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(logColor(for: entry))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.08))
                                    .id(index)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = entry
                                        } label: {
                                            Label("Copy Line", systemImage: "doc.on.doc")
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: stratum.logEntries.count) { _, _ in
                        if autoScroll, let last = stratum.logEntries.indices.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Logs")
        }
    }

    private func logColor(for entry: String) -> Color {
        if entry.contains("ACCEPTED") { return .green }
        if entry.contains("REJECTED") || entry.contains("error") || entry.contains("failed") { return .red }
        if entry.contains("SHARE FOUND") || entry.contains("Submitting") { return .cyan }
        if entry.contains("Job:") || entry.contains("New job") { return .yellow }
        if entry.contains("Difficulty") { return .purple }
        if entry.contains("authorized") || entry.contains("Authorized") { return .green }
        return .secondary
    }
}

import SwiftUI
import os

struct DiagnosticsTab: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "DiagnosticsTab")

    @State private var hardware: DiagnosticsCollector.HardwareInfo?
    @State private var storage: DiagnosticsCollector.StorageInfo?
    @State private var llmInfo: DiagnosticsCollector.LLMInfo?
    @State private var audioInfo: DiagnosticsCollector.AudioInfo?
    @State private var crashInfo: DiagnosticsCollector.CrashInfo?
    @State private var showCopiedFeedback = false
    @State private var showCrashLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // Hardware section
                if let hw = hardware {
                    DiagnosticSection(title: "Hardware", systemImage: "cpu") {
                        DiagnosticRow(label: "Memory", value: "\(hw.totalMemoryGB) GB")
                        DiagnosticRow(label: "Processor", value: hw.processorName)
                        DiagnosticRow(label: "macOS", value: hw.osVersion)
                        DiagnosticRow(label: "App Version", value: "\(hw.appVersion) (\(hw.buildNumber))")
                    }
                }

                // Audio section
                if let audio = audioInfo {
                    DiagnosticSection(title: "Audio Pipeline", systemImage: "waveform") {
                        DiagnosticRow(label: "Sample Rate", value: "\(Int(audio.sampleRate)) Hz")
                        DiagnosticRow(label: "Channels", value: "\(audio.channels)")
                        DiagnosticRow(label: "Buffer Duration", value: "\(Int(audio.bufferDuration))s")
                    }
                }

                // LLM section
                if let llm = llmInfo {
                    DiagnosticSection(title: "LLM Engine", systemImage: "brain") {
                        DiagnosticRow(label: "Provider", value: llm.provider)
                        DiagnosticRow(label: "Model", value: llm.model)
                        DiagnosticRow(label: "Base URL", value: llm.baseURL)
                        DiagnosticRow(label: "Temperature", value: String(format: "%.1f", llm.temperature))
                        DiagnosticRow(label: "Max Tokens", value: "\(llm.maxTokens)")
                    }
                }

                // Storage section
                if let storage = storage {
                    DiagnosticSection(title: "Storage", systemImage: "internaldrive") {
                        DiagnosticRow(label: "Database", value: storage.databaseSizeFormatted)
                        DiagnosticRow(label: "Audio Files", value: "\(storage.audioFilesSizeFormatted) (\(storage.audioFileCount) files)")
                        DiagnosticRow(label: "Total", value: storage.totalSizeFormatted)
                    }
                }

                // Crash Log section
                if let crash = crashInfo {
                    DiagnosticSection(title: "Crash Log", systemImage: "exclamationmark.triangle") {
                        DiagnosticRow(label: "Has Crash Log", value: crash.hasCrashLog ? "Yes" : "No")
                        if let date = crash.crashLogDate {
                            DiagnosticRow(label: "Last Crash", value: date.formatted())
                        }
                        if crash.hasCrashLog {
                            Button("View Crash Log") {
                                showCrashLog = true
                            }
                            .font(DS.Typography.caption)
                        }
                    }
                }

                // Actions
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        exportDiagnostics()
                    } label: {
                        Label(showCopiedFeedback ? "Copied!" : "Export Diagnostics", systemImage: showCopiedFeedback ? "checkmark" : "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        refreshAll()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, DS.Spacing.sm)
            }
            .padding()
        }
        .onAppear { refreshAll() }
        .sheet(isPresented: $showCrashLog) {
            if let content = crashInfo?.crashLogContent {
                NavigationStack {
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Crash Log")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showCrashLog = false }
                        }
                    }
                }
                .frame(minWidth: 500, minHeight: 400)
            }
        }
    }

    private func refreshAll() {
        hardware = DiagnosticsCollector.collectHardware()
        storage = DiagnosticsCollector.collectStorage()
        llmInfo = DiagnosticsCollector.collectLLMInfo()
        audioInfo = DiagnosticsCollector.collectAudioInfo()
        crashInfo = DiagnosticsCollector.collectCrashInfo()
        Self.logger.info("Diagnostics refreshed")
    }

    private func exportDiagnostics() {
        let report = DiagnosticsCollector.exportReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        Self.logger.info("Exported diagnostics report to clipboard")
        withAnimation { showCopiedFeedback = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedFeedback = false }
        }
    }
}

// MARK: - Helper Views

private struct DiagnosticSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(DS.Typography.body)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                content
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(DS.Typography.caption)
                .textSelection(.enabled)
        }
    }
}

import SwiftUI
import os

/// Sheet showing batch re-summarization progress.
struct BatchResummarizeSheet: View {
    let sessionCount: Int
    @Binding var isPresented: Bool
    let onStart: () -> Task<BatchResummarizeService.BatchResult, Never>

    @State private var progress: BatchResummarizeService.BatchProgress?
    @State private var result: BatchResummarizeService.BatchResult?
    @State private var task: Task<BatchResummarizeService.BatchResult, Never>?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "BatchResummarizeSheet")

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.md) {
                if let result {
                    completedView(result)
                } else if let progress {
                    progressView(progress)
                } else {
                    confirmationView
                }
            }
            .padding()
            .navigationTitle("Batch Re-summarize")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        task?.cancel()
                        isPresented = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
    }

    private var confirmationView: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "arrow.trianglehead.2.counterclockwise")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Re-summarize \(sessionCount) session\(sessionCount == 1 ? "" : "s")?")
                .font(DS.Typography.body)
                .fontWeight(.medium)

            Text("This will regenerate all summaries using the current model and settings. Existing summaries will be replaced.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start") {
                startBatch()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func progressView(_ progress: BatchResummarizeService.BatchProgress) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ProgressView(value: progress.fractionComplete)
                .progressViewStyle(.linear)

            HStack {
                Text("\(progress.completed + progress.failed)/\(progress.total)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if progress.failed > 0 {
                    Text("\(progress.failed) failed")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.red)
                }
            }

            if let title = progress.currentTitle {
                Text("Processing: \(title)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button("Cancel") {
                task?.cancel()
            }
            .buttonStyle(.bordered)
        }
    }

    private func completedView(_ result: BatchResummarizeService.BatchResult) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(result.failed == 0 ? .green : .orange)

            Text("Completed")
                .font(DS.Typography.body)
                .fontWeight(.medium)

            Text("\(result.succeeded) succeeded, \(result.failed) failed")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

            if !result.errors.isEmpty {
                Text("Failed: \(result.errors.joined(separator: ", "))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Button("Done") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func startBatch() {
        Self.logger.info("Starting batch re-summarization for \(sessionCount) sessions")
        let t = onStart()
        task = t
        Task { @MainActor in
            let r = await t.value
            result = r
            Self.logger.info("Batch complete: \(r.succeeded) succeeded, \(r.failed) failed")
        }
    }
}

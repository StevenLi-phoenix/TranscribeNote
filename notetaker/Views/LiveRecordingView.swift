import SwiftUI

struct LiveRecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RecordingControlView(
                state: viewModel.state,
                elapsedTime: viewModel.clock.formatted,
                onStart: {
                    Task {
                        await viewModel.startRecording()
                    }
                },
                onStop: onStop
            )

            Divider()

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            if viewModel.segments.isEmpty && viewModel.partialText.isEmpty {
                if !viewModel.isRecording {
                    ContentUnavailableView(
                        "No Transcript",
                        systemImage: "mic.badge.plus",
                        description: Text("Press \(Image(systemName: "record.circle")) or ⌘R to start recording")
                    )
                } else {
                    TranscriptView(
                        segments: viewModel.segments,
                        partialText: viewModel.partialText
                    )
                }
            } else {
                TranscriptView(
                    segments: viewModel.segments,
                    partialText: viewModel.partialText
                )
            }

            // Summary section (shown during recording)
            if viewModel.isRecording || viewModel.state == .stopping {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.isSummarizing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Summarizing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if let error = viewModel.summaryError {
                        Text(error)
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    if let summary = viewModel.latestSummary {
                        SummaryCardView(
                            coveringFrom: viewModel.summaries.last?.coveringFrom ?? 0,
                            coveringTo: viewModel.summaries.last?.coveringTo ?? 0,
                            content: summary,
                            model: "",
                            isCompact: true
                        )
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

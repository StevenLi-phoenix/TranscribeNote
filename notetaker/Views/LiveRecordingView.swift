import SwiftUI

struct LiveRecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    let onStop: () -> Void

    @State private var showSummaries = true
    @State private var scrollToTime: TimeInterval?

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

            // Summary section (shown during recording) — above transcript
            if viewModel.isRecording || viewModel.state == .stopping {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        showSummaries.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showSummaries ? "chevron.down" : "chevron.right")
                                .font(.caption)

                            Text("Summaries")
                                .font(.headline)

                            Text("\(viewModel.summaries.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())

                            if viewModel.isSummarizing {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showSummaries {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.summaries) { summary in
                                    SummaryCardView(
                                        coveringFrom: summary.coveringFrom,
                                        coveringTo: summary.coveringTo,
                                        content: summary.content,
                                        model: summary.model,
                                        isCompact: true,
                                        isOverall: summary.isOverall
                                    ) {
                                        scrollToTime = summary.coveringFrom
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }

                    if let error = viewModel.summaryError {
                        Text(error)
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .animation(.easeInOut, value: showSummaries)

                Divider()
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
                    partialText: viewModel.partialText,
                    scrollToTime: $scrollToTime
                )
            }
        }
    }
}

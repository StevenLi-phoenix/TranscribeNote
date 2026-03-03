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
                audioLevel: viewModel.audioMeter.level,
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
                    .padding(.vertical, DS.Spacing.xs)
            }

            // Summary section (shown during recording) — above transcript
            if viewModel.isRecording || viewModel.state == .stopping {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Button {
                        showSummaries.toggle()
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: showSummaries ? "chevron.down" : "chevron.right")
                                .font(DS.Typography.caption)

                            Text("Summaries")
                                .font(DS.Typography.sectionHeader)

                            Text("\(viewModel.summaries.count)")
                                .badgeStyle()

                            // Summaries appear silently — no spinner
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showSummaries {
                        ScrollView {
                            LazyVStack(spacing: DS.Spacing.sm) {
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
                                    .transition(.opacity)
                                }
                            }
                            .animation(.easeIn(duration: 0.3), value: viewModel.summaries.count)
                        }
                        .frame(maxHeight: 200)
                    }

                    if let error = viewModel.summaryError {
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(DS.Typography.caption)
                            .transition(.opacity)
                            .task(id: error) {
                                try? await Task.sleep(for: .seconds(5))
                                guard !Task.isCancelled else { return }
                                viewModel.clearSummaryError()
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, DS.Spacing.sm)
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

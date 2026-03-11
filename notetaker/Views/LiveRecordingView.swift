import SwiftUI

struct LiveRecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    let onStop: () -> Void
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?

    @State private var scrollToTime: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            RecordingControlView(
                state: viewModel.state,
                elapsedTime: viewModel.clock.formatted,
                audioLevel: viewModel.audioMeter.level,
                stoppingStatus: viewModel.stoppingStatus,
                onStart: {
                    Task {
                        await viewModel.startRecording()
                    }
                },
                onStop: onStop,
                onPause: onPause,
                onResume: onResume
            )

            Divider()

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, DS.Spacing.xs)
            }

            // Summary error — shown independently of summary section
            if let error = viewModel.summaryError {
                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        viewModel.clearSummaryError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(DS.Typography.caption)
                .padding(DS.Spacing.sm)
                .padding(.horizontal)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                .transition(.opacity)
            }

            if viewModel.segments.isEmpty && viewModel.partialText.isEmpty {
                if !viewModel.isActive {
                    ContentUnavailableView(
                        "No Transcript",
                        systemImage: "mic.badge.plus",
                        description: Text("Press \(Image(systemName: "record.circle")) or ⌘R to start recording")
                    )
                } else {
                    TranscriptView(
                        segments: viewModel.segments,
                        partialText: viewModel.partialText,
                        summaries: viewModel.summaries
                    )
                }
            } else {
                TranscriptView(
                    segments: viewModel.segments,
                    partialText: viewModel.partialText,
                    summaries: viewModel.summaries,
                    scrollToTime: $scrollToTime
                )
            }
        }
    }
}

import SwiftUI

struct LiveRecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RecordingControlView(
                isRecording: viewModel.isRecording,
                elapsedTime: viewModel.formattedElapsedTime,
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

            if viewModel.segments.isEmpty && viewModel.partialText.isEmpty && !viewModel.isRecording {
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
        }
    }
}

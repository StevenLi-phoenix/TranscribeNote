import SwiftUI

struct RecordingControlView: View {
    let state: RecordingState
    let elapsedTime: String
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var pulseAnimation = false

    private var isRecording: Bool { state == .recording }

    var body: some View {
        ZStack {
            // Recording indicator — always rendered to prevent layout shift
            HStack(spacing: 16) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseAnimation ? 0.3 : 1.0)

                Text(elapsedTime)
                    .font(ControlBarMetrics.timeFont)
                    .frame(minWidth: ControlBarMetrics.timeMinWidth)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    onStop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
            .opacity(isRecording ? 1 : 0)
            .allowsHitTesting(isRecording)
            .accessibilityHidden(!isRecording)

            // Stopping state — transient "saving..." indicator
            HStack(spacing: 16) {
                ProgressView()
                    .controlSize(.small)

                Text(elapsedTime)
                    .font(ControlBarMetrics.timeFont)
                    .frame(minWidth: ControlBarMetrics.timeMinWidth)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Saving...")
                    .foregroundStyle(.secondary)
            }
            .opacity(state == .stopping ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(state != .stopping)

            // Idle state
            Button {
                onStart()
            } label: {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start recording")
            .opacity(state == .idle ? 1 : 0)
            .allowsHitTesting(state == .idle)
            .accessibilityHidden(state != .idle)
        }
        .padding()
        .background {
            // Single keyboard shortcut that dispatches based on state
            Button {
                isRecording ? onStop() : onStart()
            } label: {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(state == .stopping)
            .accessibilityHidden(true)
        }
        .onAppear {
            if isRecording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .onChange(of: state) { _, newValue in
            if newValue == .recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
    }
}

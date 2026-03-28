import SwiftUI

struct RecordingControlView: View {
    let state: RecordingState
    let elapsedTime: String
    var audioLevel: Float = 0
    var stoppingStatus: String = "Saving..."
    var heroNamespace: Namespace.ID? = nil
    let onStart: () -> Void
    let onStop: () -> Void
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?

    @State private var pulseAnimation = false

    private var isRecording: Bool { state == .recording }
    private var isPaused: Bool { state == .paused }

    var body: some View {
        ZStack {
            // Recording indicator — always rendered to prevent layout shift
            HStack(spacing: DS.Spacing.lg) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseAnimation ? 0.3 : 1.0)

                Text(elapsedTime)
                    .font(ControlBarMetrics.timeFont)
                    .frame(minWidth: ControlBarMetrics.timeMinWidth)
                    .foregroundStyle(.primary)
                    .matchedGeometryEffectIfPresent(id: "sessionTimer", in: heroNamespace, properties: .position, isSource: true)

                Spacer()

                Button {
                    onPause?()
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.title)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause recording")

                Button {
                    onStop()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.title)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
            .opacity(isRecording ? 1 : 0)
            .allowsHitTesting(isRecording)
            .accessibilityHidden(!isRecording)

            // Audio level bar — only during recording, positioned below controls
            if isRecording {
                AudioLevelBar(level: audioLevel)
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .offset(y: DS.Spacing.xl)
            }

            // Paused state
            HStack(spacing: DS.Spacing.lg) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.body)

                Text(elapsedTime)
                    .font(ControlBarMetrics.timeFont)
                    .frame(minWidth: ControlBarMetrics.timeMinWidth)
                    .foregroundStyle(.secondary)

                Text("Paused")
                    .foregroundStyle(.orange)
                    .font(DS.Typography.caption)

                Spacer()

                Button {
                    onResume?()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume recording")

                Button {
                    onStop()
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.title)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
            .opacity(isPaused ? 1 : 0)
            .allowsHitTesting(isPaused)
            .accessibilityHidden(!isPaused)

            // Stopping state — transient "saving..." indicator
            HStack(spacing: DS.Spacing.lg) {
                ProgressView()
                    .controlSize(.small)

                Text(elapsedTime)
                    .font(ControlBarMetrics.timeFont)
                    .frame(minWidth: ControlBarMetrics.timeMinWidth)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(stoppingStatus)
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
                switch state {
                case .recording:
                    onPause?()
                case .paused:
                    onResume?()
                case .idle, .completed:
                    onStart()
                case .stopping:
                    break
                }
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

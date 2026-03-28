import SwiftUI

struct PlaybackControlView: View {
    @Bindable var service: AudioPlaybackService
    @State private var isSeeking = false
    @State private var seekValue: TimeInterval = 0

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button {
                service.seek(to: max(0, service.currentTime - 15))
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip back 15 seconds")

            Button {
                service.togglePlayPause()
            } label: {
                Image(systemName: service.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.isPlaying ? "Pause" : "Play")

            Button {
                service.seek(to: min(service.duration, service.currentTime + 15))
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip forward 15 seconds")

            Text((isSeeking ? seekValue : service.currentTime).mmss)
                .font(ControlBarMetrics.timeFont)
                .frame(minWidth: ControlBarMetrics.timeMinWidth, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { isSeeking ? seekValue : service.currentTime },
                    set: { seekValue = $0 }
                ),
                in: 0...max(service.duration, 0.01),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        service.seek(to: seekValue)
                    }
                }
            )

            Text(service.duration.mmss)
                .font(ControlBarMetrics.timeFont)
                .frame(minWidth: ControlBarMetrics.timeMinWidth, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, DS.Spacing.sm)
        .background {
            Button {
                service.togglePlayPause()
            } label: {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityHidden(true)
        }
    }
}

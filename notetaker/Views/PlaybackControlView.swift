import SwiftUI

struct PlaybackControlView: View {
    @Bindable var service: AudioPlaybackService
    @State private var isSeeking = false
    @State private var seekValue: TimeInterval = 0

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button {
                service.togglePlayPause()
            } label: {
                Image(systemName: service.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(DS.Typography.title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(service.isPlaying ? "Pause" : "Play")

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
    }
}

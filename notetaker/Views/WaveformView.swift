import SwiftUI

/// Audio waveform visualization with playhead, click/drag seek support.
struct WaveformView: View {
    let waveformData: WaveformExtractor.WaveformData
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    var onSeek: ((TimeInterval) -> Void)?

    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0

    private var displayTime: TimeInterval {
        isDragging ? dragTime : currentTime
    }

    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(displayTime / duration)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }

                if duration > 0 {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: progress * geometry.size.width - 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let ratio = max(0, min(1, value.location.x / geometry.size.width))
                        dragTime = Double(ratio) * duration
                    }
                    .onEnded { value in
                        let ratio = max(0, min(1, value.location.x / geometry.size.width))
                        let seekTime = Double(ratio) * duration
                        onSeek?(seekTime)
                        isDragging = false
                    }
            )
        }
        .frame(height: DS.Layout.waveformHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .accessibilityLabel("Audio waveform")
        .accessibilityValue("\(Int(displayTime)) of \(Int(duration)) seconds")
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let samples = waveformData.samples
        guard !samples.isEmpty else { return }

        let barWidth = max(1, size.width / CGFloat(samples.count))
        let halfHeight = size.height / 2
        let playedColor = Color.accentColor
        let unplayedColor = Color.secondary.opacity(0.3)

        for (index, amplitude) in samples.enumerated() {
            let x = CGFloat(index) * barWidth
            let barHeight = max(1, CGFloat(amplitude) * halfHeight)
            let rect = CGRect(
                x: x,
                y: halfHeight - barHeight,
                width: max(1, barWidth - 0.5),
                height: barHeight * 2
            )

            let barProgress = CGFloat(index) / CGFloat(samples.count)
            let color = barProgress <= progress ? playedColor : unplayedColor
            context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
        }
    }
}

import SwiftUI

/// A draggable horizontal handle for resizing a section height.
struct ResizeHandle: View {
    @Binding var height: Double
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : DS.Colors.separator)
            .frame(height: isDragging ? 3 : 1)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newHeight = height + value.translation.height
                        height = max(Double(minHeight), min(newHeight, Double(maxHeight)))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

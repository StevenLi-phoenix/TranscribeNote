import SwiftUI

/// A vertical draggable divider for resizing horizontal sections (e.g., side panels).
/// Mirrors the pattern of `ResizeHandle` but operates on width instead of height.
struct VerticalResizeHandle: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : DS.Colors.separator)
            .frame(width: isDragging ? 3 : 1)
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        // Dragging left increases panel width (panel is on the right)
                        let newWidth = width - value.translation.width
                        width = max(Double(minWidth), min(newWidth, Double(maxWidth)))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityLabel("Resize handle")
            .help("Drag to resize panel width")
    }
}

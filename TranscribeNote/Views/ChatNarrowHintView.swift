import SwiftUI

/// Floating hint shown when inline chat is squeezed in a narrow window.
struct ChatNarrowHintView: View {
    let onOpenInWindow: () -> Void
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "arrow.up.right.square")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                Text("Window too narrow for chat panel")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                Button("Open in Window") {
                    onOpenInWindow()
                }
                .buttonStyle(.borderless)
                .font(DS.Typography.caption)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .shadow(radius: 4)
            .task {
                try? await Task.sleep(for: .seconds(8))
                withAnimation { isVisible = false }
            }
        }
    }
}

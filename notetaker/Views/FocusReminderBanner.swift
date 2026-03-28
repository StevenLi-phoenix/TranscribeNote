import SwiftUI
import os

/// Banner suggesting the user enable Focus/DND mode during recording.
struct FocusReminderBanner: View {
    @Binding var isVisible: Bool
    @AppStorage("focusReminderEnabled") private var reminderEnabled = true

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "FocusReminderBanner")

    var body: some View {
        if isVisible && reminderEnabled {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "moon.fill")
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Focus Mode is off")
                        .font(DS.Typography.callout)
                        .fontWeight(.medium)
                    Text("Enable Do Not Disturb to avoid notification sounds in your recording.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Open System Settings Focus
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Focus") {
                        NSWorkspace.shared.open(url)
                    }
                    Self.logger.info("User opened Focus settings")
                } label: {
                    Text("Open Settings")
                        .font(DS.Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Dismiss
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")

                // Don't show again
                Button {
                    reminderEnabled = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                    Self.logger.info("User disabled focus reminders")
                } label: {
                    Image(systemName: "bell.slash")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Don't remind again")
            }
            .padding(DS.Spacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

import SwiftUI

/// Centralized design tokens for consistent spacing, typography, colors, and layout.
enum DS {

    // MARK: - Spacing (4pt grid)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Typography

    enum Typography {
        static let title: Font = .title2.weight(.semibold)
        static let sectionHeader: Font = .headline
        static let body: Font = .body
        static let callout: Font = .callout
        static let caption: Font = .caption
        static let caption2: Font = .caption2
        static let timestamp: Font = .system(.caption, design: .monospaced)
        static let timer: Font = .system(.body, design: .monospaced)
    }

    // MARK: - Colors

    enum Colors {
        static let recording: Color = .red
        static let cardBackground: Color = .init(nsColor: .controlBackgroundColor)
        static let subtleError: Color = .orange
        static let separator: Color = .init(nsColor: .separatorColor)
        static let audioLevel: Color = .green
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    // MARK: - Layout

    enum Layout {
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarIdealWidth: CGFloat = 250
        static let timestampWidth: CGFloat = 72
        static let summaryMaxHeight: CGFloat = 300
        static let controlBarMinHeight: CGFloat = 48
        static let timeMinWidth: CGFloat = 64
        static let waveformHeight: CGFloat = 60
    }
}

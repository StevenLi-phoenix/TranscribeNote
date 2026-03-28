import SwiftUI
import os

struct SummaryCardView: View {
    let coveringFrom: TimeInterval
    let coveringTo: TimeInterval
    let content: String
    let model: String
    let isCompact: Bool
    let isOverall: Bool
    let isUserEdited: Bool
    let sessionTitle: String
    let sessionDate: Date
    let sessionDuration: TimeInterval
    var onTimeTap: (() -> Void)?
    var onSave: ((String) -> Void)?
    var onRegenerate: ((String) -> Void)?

    @State private var isEditing = false
    @State private var editText = ""
    @State private var showRegenerateField = false
    @State private var regenerateInstructions = ""
    @State private var isHovered = false
    @State private var showCopiedFeedback = false
    @State private var showCardCopiedFeedback = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "SummaryCardView")

    init(
        coveringFrom: TimeInterval,
        coveringTo: TimeInterval,
        content: String,
        model: String,
        isCompact: Bool = false,
        isOverall: Bool = false,
        isUserEdited: Bool = false,
        sessionTitle: String = "Untitled",
        sessionDate: Date = Date(),
        sessionDuration: TimeInterval = 0,
        onTimeTap: (() -> Void)? = nil,
        onSave: ((String) -> Void)? = nil,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.coveringFrom = coveringFrom
        self.coveringTo = coveringTo
        self.content = content
        self.model = model
        self.isCompact = isCompact
        self.isOverall = isOverall
        self.isUserEdited = isUserEdited
        self.sessionTitle = sessionTitle
        self.sessionDate = sessionDate
        self.sessionDuration = sessionDuration
        self.onTimeTap = onTimeTap
        self.onSave = onSave
        self.onRegenerate = onRegenerate
    }

    init(
        block: SummaryBlock,
        isCompact: Bool = false,
        sessionTitle: String = "Untitled",
        sessionDate: Date = Date(),
        sessionDuration: TimeInterval = 0,
        onTimeTap: (() -> Void)? = nil,
        onSave: ((String) -> Void)? = nil,
        onRegenerate: ((String) -> Void)? = nil
    ) {
        self.coveringFrom = block.coveringFrom
        self.coveringTo = block.coveringTo
        self.content = block.displayContent
        self.model = block.model
        self.isCompact = isCompact
        self.isOverall = block.isOverall
        self.isUserEdited = block.userEdited
        self.sessionTitle = sessionTitle
        self.sessionDate = sessionDate
        self.sessionDuration = sessionDuration
        self.onTimeTap = onTimeTap
        self.onSave = onSave
        self.onRegenerate = onRegenerate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Content area
            if isEditing {
                editingView
            } else if showRegenerateField {
                regenerateView
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
                    // Time label on the left — matches TranscriptSegmentRow / InlineSummaryRow width
                    if isOverall {
                        timeLabel("Overall", systemImage: nil)
                            .frame(width: DS.Layout.timestampWidth, alignment: .leading)
                    } else {
                        timeLabel("\(coveringFrom.mmss)–\(coveringTo.mmss)", systemImage: nil)
                            .frame(width: DS.Layout.timestampWidth, alignment: .leading)
                    }

                    if isUserEdited {
                        Image(systemName: "pencil")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Edited by user")
                    }

                    // Summary content
                    contentView
                }
            }

        }
        .padding(.vertical, DS.Spacing.xs)
        .overlay(alignment: .topTrailing) {
            if !isEditing && !showRegenerateField && (isHovered || showCopiedFeedback || showCardCopiedFeedback) {
                HStack(spacing: DS.Spacing.xs) {
                    copyButton

                    shareCardMenu

                    if onSave != nil {
                        Button {
                            editText = content
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(DS.Typography.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Edit summary")
                    }
                    if onRegenerate != nil {
                        Button {
                            regenerateInstructions = ""
                            showRegenerateField = true
                        } label: {
                            Image(systemName: "arrow.trianglehead.2.counterclockwise")
                                .font(DS.Typography.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .help("Regenerate with instructions")
                    }
                }
            }
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - Copy

    @ViewBuilder
    private var copyButton: some View {
        Button(action: copySummaryAsMarkdown) {
            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                .font(DS.Typography.caption2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(showCopiedFeedback ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
        .help("Copy summary (Markdown)")
        .accessibilityLabel("Copy summary to clipboard")
    }

    private func copySummaryAsMarkdown() {
        let markdown = SummaryMarkdownFormatter.format(
            content: content,
            coveringFrom: coveringFrom,
            coveringTo: coveringTo,
            isOverall: isOverall
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        Self.logger.debug("Copied summary to clipboard (\(markdown.count) chars)")

        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedFeedback = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }

    // MARK: - Share as Card

    @ViewBuilder
    private var shareCardMenu: some View {
        Menu {
            ForEach(SummaryCardStyle.allCases, id: \.self) { style in
                Button("Copy as \(style.rawValue.capitalized)") {
                    shareAsCard(style: style)
                }
            }
            Divider()
            Menu("Save Image\u{2026}") {
                ForEach(SummaryCardStyle.allCases, id: \.self) { style in
                    Button(style.rawValue.capitalized) {
                        saveCardAsFile(style: style)
                    }
                }
            }
        } label: {
            Image(systemName: showCardCopiedFeedback ? "checkmark" : "square.and.arrow.up")
                .font(DS.Typography.caption2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(showCardCopiedFeedback ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
        .help("Share as card image")
        .accessibilityLabel("Share summary as card image")
    }

    private func buildCardData(style: SummaryCardStyle) -> SummaryCardData {
        let bullets = SummaryCardExporter.extractBulletPoints(from: content)
        let plainText = SummaryCardExporter.extractPlainSummary(from: content)
        return SummaryCardData(
            title: sessionTitle,
            date: sessionDate,
            duration: sessionDuration,
            summaryText: plainText,
            bulletPoints: bullets,
            style: style
        )
    }

    private func shareAsCard(style: SummaryCardStyle) {
        let data = buildCardData(style: style)
        let success = SummaryCardExporter.copyToClipboard(data: data)
        if success {
            Self.logger.debug("Shared summary as \(style.rawValue) card image to clipboard")
            withAnimation(.easeInOut(duration: 0.2)) {
                showCardCopiedFeedback = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCardCopiedFeedback = false
                }
            }
        }
    }

    private func saveCardAsFile(style: SummaryCardStyle) {
        let data = buildCardData(style: style)
        Task { @MainActor in
            let success = await SummaryCardExporter.saveToFile(data: data)
            if success {
                Self.logger.debug("Saved summary as \(style.rawValue) card image to file")
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var contentView: some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(DS.Typography.callout)
                .textSelection(.enabled)
        } else {
            Text(content)
                .font(DS.Typography.callout)
                .textSelection(.enabled)
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            TextEditor(text: $editText)
                .font(DS.Typography.callout)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(DS.Spacing.xs)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            HStack {
                Spacer()
                Button("Cancel") {
                    isEditing = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Save") {
                    onSave?(editText)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var regenerateView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            TextField("Instructions for regeneration...", text: $regenerateInstructions, axis: .vertical)
                .font(DS.Typography.callout)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(DS.Spacing.xs)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            HStack {
                Spacer()
                Button("Cancel") {
                    showRegenerateField = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Regenerate") {
                    onRegenerate?(regenerateInstructions)
                    showRegenerateField = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(regenerateInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func timeLabel(_ title: String, systemImage: String?) -> some View {
        if let onTimeTap {
            Button {
                onTimeTap()
            } label: {
                timeLabelContent(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to transcript")
        } else {
            timeLabelContent(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func timeLabelContent(_ title: String, systemImage: String?) -> some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .font(DS.Typography.caption)
        } else {
            Text(title)
                .font(DS.Typography.caption)
        }
    }
}

import SwiftUI

struct SummaryCardView: View {
    let coveringFrom: TimeInterval
    let coveringTo: TimeInterval
    let content: String
    let model: String
    let isCompact: Bool
    let isOverall: Bool
    let isUserEdited: Bool
    var onTimeTap: (() -> Void)?
    var onSave: ((String) -> Void)?
    var onRegenerate: ((String) -> Void)?

    @State private var isEditing = false
    @State private var editText = ""
    @State private var showRegenerateField = false
    @State private var regenerateInstructions = ""
    @State private var isHovered = false

    init(
        coveringFrom: TimeInterval,
        coveringTo: TimeInterval,
        content: String,
        model: String,
        isCompact: Bool = false,
        isOverall: Bool = false,
        isUserEdited: Bool = false,
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
        self.onTimeTap = onTimeTap
        self.onSave = onSave
        self.onRegenerate = onRegenerate
    }

    init(
        block: SummaryBlock,
        isCompact: Bool = false,
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
            if !isEditing && !showRegenerateField && isHovered && (onSave != nil || onRegenerate != nil) {
                HStack(spacing: DS.Spacing.xs) {
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

    // MARK: - Subviews

    @ViewBuilder
    private var contentView: some View {
        Text(content)
            .font(DS.Typography.callout)
            .textSelection(.enabled)
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

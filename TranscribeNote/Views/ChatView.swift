import SwiftUI
import os

/// Chat panel content — renders messages and input, driven by ChatViewModel.
struct ChatViewContent: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()

            if viewModel.segments.isEmpty {
                emptyTranscriptView
            } else {
                messagesArea
                if viewModel.messages.isEmpty {
                    presetQuestionsView
                }
                Divider()
                inputBar
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Text("Chat")
                .font(DS.Typography.sectionHeader)
            Spacer()
            if !viewModel.messages.isEmpty {
                Button {
                    viewModel.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Typography.caption)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Clear conversation"))
                .accessibilityLabel(String(localized: "Clear conversation"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(viewModel.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }
                    if viewModel.isGenerating {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(DS.Spacing.md)
            }
            .onChange(of: viewModel.scrollTarget) {
                if let target = viewModel.scrollTarget {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isGenerating) {
                if viewModel.isGenerating {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Preset Questions

    private var presetQuestionsView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Suggested questions")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Spacing.md)

            FlowLayout(spacing: DS.Spacing.xs) {
                ForEach(viewModel.presetQuestions, id: \.self) { question in
                    Button {
                        viewModel.inputText = question
                        viewModel.sendMessage()
                    } label: {
                        Text(question)
                            .font(DS.Typography.caption)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.lg)
                                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
        }
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: DS.Spacing.sm) {
            TextField("Ask about this transcript…", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .onSubmit { viewModel.sendMessage() }

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(String(localized: "Send message"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    // MARK: - Empty State

    private var emptyTranscriptView: some View {
        ContentUnavailableView(
            "No Transcript",
            systemImage: "text.bubble",
            description: Text("This session has no transcript content to chat about.")
        )
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Chat Bubble

private struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            bubbleContent
            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var bubbleContent: some View {
        Text(message.content)
            .font(DS.Typography.body)
            .textSelection(.enabled)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(backgroundColor)
            .foregroundStyle(message.isError ? DS.Colors.subtleError : .primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var backgroundColor: Color {
        if message.isError {
            return DS.Colors.subtleError.opacity(0.1)
        }
        return message.role == .user
            ? Color.accentColor.opacity(0.15)
            : DS.Colors.cardBackground
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .onAppear { animating = true }
    }
}

// MARK: - Flow Layout

/// Simple flow layout for preset question buttons.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return ArrangeResult(
            size: CGSize(width: maxWidth, height: y + rowHeight),
            positions: positions,
            sizes: sizes
        )
    }
}

import SwiftUI
import os

/// Chat panel for conversational Q&A against a session's transcript.
struct ChatView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ChatView")

    let segments: [TranscriptSegment]
    let sessionID: UUID

    @State private var chatService: ChatService?
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isGenerating = false
    @State private var scrollTarget: UUID?
    @State private var chatTask: Task<Void, Never>?

    private let presetQuestions = [
        "What were the main topics discussed?",
        "What action items were mentioned?",
        "Summarize the key decisions",
        "What are the next steps?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()

            if segments.isEmpty {
                emptyTranscriptView
            } else {
                messagesArea
                if messages.isEmpty {
                    presetQuestionsView
                }
                Divider()
                inputBar
            }
        }
        .onAppear { initServiceIfNeeded() }
        .onDisappear {
            chatTask?.cancel()
            chatTask = nil
        }
        .onChange(of: sessionID) {
            chatTask?.cancel()
            chatTask = nil
            isGenerating = false
            messages.removeAll()
            chatService?.clearHistory()
            chatService = nil
            initServiceIfNeeded()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Text("Chat")
                .font(DS.Typography.sectionHeader)
            if !messages.isEmpty {
                Text("(\(messages.count))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !messages.isEmpty {
                Button {
                    messages.removeAll()
                    chatService?.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Typography.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear conversation")
                .help("Clear conversation")
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
                    ForEach(messages) { message in
                        ChatBubbleView(
                            message: message,
                            onDismiss: message.isError ? { messages.removeAll { $0.id == message.id } } : nil
                        )
                        .id(message.id)
                    }
                    if isGenerating {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(DS.Spacing.md)
            }
            .onChange(of: scrollTarget) {
                if let target = scrollTarget {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isGenerating) {
                if isGenerating {
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
                ForEach(presetQuestions, id: \.self) { question in
                    Button {
                        inputText = question
                        sendMessage()
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
            TextField("Ask about this transcript…", text: $inputText)
                .textFieldStyle(.plain)
                .onSubmit { sendMessage() }
                .onKeyPress(.escape) {
                    inputText = ""
                    return .handled
                }

            if isGenerating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send message")
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

    // MARK: - Actions

    private func initServiceIfNeeded() {
        guard chatService == nil else { return }
        let config = LLMProfileStore.resolveConfig(for: .chat)
        let engine = LLMEngineFactory.create(from: config)
        chatService = ChatService(engine: engine)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        isGenerating = true

        // Add user message to local state immediately for UI
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        scrollTarget = userMsg.id

        chatTask = Task {
            defer { isGenerating = false }
            do {
                let config = LLMProfileStore.resolveConfig(for: .chat)
                let response = try await chatService?.sendMessage(text, segments: segments, llmConfig: config)
                guard !Task.isCancelled else { return }
                if let response {
                    messages.append(response)
                    scrollTarget = response.id
                }
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Chat error: \(error.localizedDescription)")
                let errorMsg = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)", isError: true)
                messages.append(errorMsg)
                scrollTarget = errorMsg.id
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubbleView: View {
    let message: ChatMessage
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            bubbleContent
            if message.role != .user { Spacer(minLength: 60) }
        }
        .task(id: message.id) {
            guard message.isError, onDismiss != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            onDismiss?()
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
            .accessibilityLabel("\(message.role == .user ? "You" : "Assistant"): \(message.content)")
            .overlay(alignment: .topTrailing) {
                if message.isError, onDismiss != nil {
                    Button { onDismiss?() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
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

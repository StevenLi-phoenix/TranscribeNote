import SwiftUI
import os

/// Observable view model owning chat state, shared between inline and windowed modes.
@Observable
@MainActor
final class ChatViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ChatViewModel")

    var messages: [ChatMessage] = []
    var inputText = ""
    var isGenerating = false
    var scrollTarget: UUID?

    private(set) var sessionID: UUID?
    private(set) var segments: [TranscriptSegment] = []
    private var chatService: ChatService?

    let presetQuestions = [
        "What were the main topics discussed?",
        "What action items were mentioned?",
        "Summarize the key decisions",
        "What are the next steps?",
    ]

    /// Update session context. Clears messages and service if session changes.
    func configure(sessionID: UUID, segments: [TranscriptSegment]) {
        if self.sessionID != sessionID {
            Self.logger.info("Chat session changed: \(sessionID)")
            messages.removeAll()
            chatService?.clearHistory()
            chatService = nil
        }
        self.sessionID = sessionID
        self.segments = segments
        initServiceIfNeeded()
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isGenerating else { return }

        inputText = ""
        isGenerating = true

        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        scrollTarget = userMsg.id

        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let config = LLMProfileStore.resolveConfig(for: .chat)
                let response = try await chatService?.sendMessage(text, segments: segments, llmConfig: config)
                if let response {
                    messages.append(response)
                    scrollTarget = response.id
                }
            } catch {
                Self.logger.error("Chat error: \(error.localizedDescription)")
                let errorMsg = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)", isError: true)
                messages.append(errorMsg)
                scrollTarget = errorMsg.id
            }
        }
    }

    func clearHistory() {
        messages.removeAll()
        chatService?.clearHistory()
        Self.logger.info("Chat history cleared")
    }

    private func initServiceIfNeeded() {
        guard chatService == nil else { return }
        let config = LLMProfileStore.resolveConfig(for: .chat)
        let engine = LLMEngineFactory.create(from: config)
        chatService = ChatService(engine: engine)
        Self.logger.info("ChatService initialized")
    }
}

/// Chat panel display mode.
enum ChatPanelMode: String {
    case inline
    case window
}

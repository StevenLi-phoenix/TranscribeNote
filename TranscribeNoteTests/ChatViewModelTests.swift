import Testing
import Foundation
@testable import TranscribeNote

@Suite(.serialized) struct ChatViewModelTests {
    @MainActor @Test func configureSetsSesssionAndSegments() {
        let vm = ChatViewModel()
        let id = UUID()
        let segments = [TranscriptSegment(startTime: 0, endTime: 5, text: "Hello")]

        vm.configure(sessionID: id, segments: segments)

        #expect(vm.sessionID == id)
        #expect(vm.segments.count == 1)
    }

    @MainActor @Test func configureWithNewSessionClearsMessages() {
        let vm = ChatViewModel()
        let id1 = UUID()
        let id2 = UUID()
        let segments = [TranscriptSegment(startTime: 0, endTime: 5, text: "Hello")]

        vm.configure(sessionID: id1, segments: segments)
        // Simulate a message
        vm.messages.append(ChatMessage(role: .user, content: "test"))
        #expect(vm.messages.count == 1)

        vm.configure(sessionID: id2, segments: segments)
        #expect(vm.messages.isEmpty)
    }

    @MainActor @Test func configureSameSessionKeepsMessages() {
        let vm = ChatViewModel()
        let id = UUID()
        let segments = [TranscriptSegment(startTime: 0, endTime: 5, text: "Hello")]

        vm.configure(sessionID: id, segments: segments)
        vm.messages.append(ChatMessage(role: .user, content: "test"))

        // Re-configure with same session
        vm.configure(sessionID: id, segments: segments)
        #expect(vm.messages.count == 1)
    }

    @MainActor @Test func clearHistoryRemovesAllMessages() {
        let vm = ChatViewModel()
        vm.messages.append(ChatMessage(role: .user, content: "test"))
        vm.messages.append(ChatMessage(role: .assistant, content: "response"))

        vm.clearHistory()

        #expect(vm.messages.isEmpty)
    }

    @MainActor @Test func sendMessageGuardsEmptyInput() {
        let vm = ChatViewModel()
        vm.inputText = "   "
        vm.configure(sessionID: UUID(), segments: [])

        vm.sendMessage()

        // No message added for empty input
        #expect(vm.messages.isEmpty)
    }

    @MainActor @Test func sendMessageGuardsWhileGenerating() {
        let vm = ChatViewModel()
        vm.isGenerating = true
        vm.inputText = "Hello"
        vm.configure(sessionID: UUID(), segments: [])

        vm.sendMessage()

        // Should not add message while generating
        #expect(vm.messages.isEmpty)
    }
}

@Suite struct ChatPanelModeTests {
    @Test func rawValueRoundTrip() {
        #expect(ChatPanelMode(rawValue: "inline") == .inline)
        #expect(ChatPanelMode(rawValue: "window") == .window)
        #expect(ChatPanelMode(rawValue: "invalid") == nil)
        #expect(ChatPanelMode.inline.rawValue == "inline")
        #expect(ChatPanelMode.window.rawValue == "window")
    }
}

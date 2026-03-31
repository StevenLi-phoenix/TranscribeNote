import SwiftUI
import SwiftData
import os

/// NSWindowController hosting ChatView in a standalone window.
@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "notetaker", category: "ChatWindowController")

    var onClose: (() -> Void)?
    private var hostingView: NSHostingView<AnyView>?

    init(viewModel: ChatViewModel, sessionTitle: String, modelContainer: ModelContainer) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: DS.Layout.chatDefaultWidth, height: DS.Layout.chatDefaultHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: DS.Layout.chatMinWindowWidth, height: DS.Layout.chatMinWindowHeight)
        window.title = "Chat – \(sessionTitle)"
        window.setFrameAutosaveName("ChatWindow")
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .managed

        let chatView = ChatViewContent(viewModel: viewModel)
            .modelContainer(modelContainer)
        let hosting = NSHostingView(rootView: AnyView(chatView))
        window.contentView = hosting

        super.init(window: window)
        window.delegate = self
        self.hostingView = hosting

        Self.logger.info("Chat window created for session: \(sessionTitle)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTitle(_ title: String) {
        window?.title = "Chat – \(title)"
    }

    func windowWillClose(_ notification: Notification) {
        Self.logger.info("Chat window closed")
        onClose?()
    }

    /// Position the window to the right of the given main window frame.
    func positionRelativeTo(_ mainFrame: NSRect) {
        guard let window, !window.isVisible else { return }
        let x = mainFrame.maxX + 20
        let y = mainFrame.midY - window.frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

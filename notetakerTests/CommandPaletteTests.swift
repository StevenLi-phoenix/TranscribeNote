import Foundation
import Testing
@testable import notetaker

@Suite("CommandPaletteSearch")
struct CommandPaletteTests {

    // MARK: - Test Helpers

    private static func makeCommand(
        id: String = UUID().uuidString,
        title: String,
        category: CommandCategory = .recording
    ) -> PaletteCommand {
        PaletteCommand(
            id: id,
            title: title,
            subtitle: nil,
            icon: "circle",
            shortcut: nil,
            category: category,
            action: {}
        )
    }

    private static let sampleCommands: [PaletteCommand] = [
        makeCommand(id: "start", title: "Start Recording", category: .recording),
        makeCommand(id: "stop", title: "Stop Recording", category: .recording),
        makeCommand(id: "play", title: "Play / Pause", category: .playback),
        makeCommand(id: "skip", title: "Skip Forward 5s", category: .playback),
        makeCommand(id: "settings", title: "Open Settings", category: .navigation),
        makeCommand(id: "export", title: "Export Markdown", category: .export),
        makeCommand(id: "search", title: "Search Sessions", category: .session),
    ]

    // MARK: - Filter Tests

    @Test("Empty query returns all commands")
    func emptyQueryReturnsAll() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "")
        #expect(result.count == Self.sampleCommands.count)
    }

    @Test("Whitespace-only query returns all commands")
    func whitespaceQueryReturnsAll() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "   ")
        #expect(result.count == Self.sampleCommands.count)
    }

    @Test("Exact match filters correctly")
    func exactMatch() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "Start Recording")
        #expect(result.count == 1)
        #expect(result[0].id == "start")
    }

    @Test("Case-insensitive match")
    func caseInsensitive() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "start recording")
        #expect(result.count == 1)
        #expect(result[0].id == "start")
    }

    @Test("Multi-word fuzzy match — words need not be contiguous")
    func multiWordFuzzy() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "open settings")
        #expect(result.count == 1)
        #expect(result[0].id == "settings")
    }

    @Test("Partial word match")
    func partialWordMatch() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "rec")
        #expect(result.count == 2) // Start Recording, Stop Recording
        let ids = Set(result.map(\.id))
        #expect(ids.contains("start"))
        #expect(ids.contains("stop"))
    }

    @Test("No match returns empty")
    func noMatch() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "zzz nonexistent")
        #expect(result.isEmpty)
    }

    @Test("All query words must appear")
    func allWordsMustAppear() {
        // "start markdown" — no single command has both words
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "start markdown")
        #expect(result.isEmpty)
    }

    // MARK: - Grouping Tests

    @Test("Grouped preserves category order and filters empty categories")
    func groupedCategories() {
        let subset = [
            Self.makeCommand(id: "a", title: "A", category: .playback),
            Self.makeCommand(id: "b", title: "B", category: .recording),
            Self.makeCommand(id: "c", title: "C", category: .playback),
        ]
        let groups = CommandPaletteSearch.grouped(commands: subset)
        #expect(groups.count == 2)
        // Recording comes before Playback in CaseIterable order
        #expect(groups[0].category == .recording)
        #expect(groups[0].commands.count == 1)
        #expect(groups[1].category == .playback)
        #expect(groups[1].commands.count == 2)
    }

    @Test("Grouped with empty input returns no groups")
    func groupedEmpty() {
        let groups = CommandPaletteSearch.grouped(commands: [])
        #expect(groups.isEmpty)
    }

    @Test("Filter + group integration")
    func filterAndGroup() {
        let result = CommandPaletteSearch.filter(commands: Self.sampleCommands, query: "recording")
        let groups = CommandPaletteSearch.grouped(commands: result)
        #expect(groups.count == 1)
        #expect(groups[0].category == .recording)
        #expect(groups[0].commands.count == 2)
    }
}

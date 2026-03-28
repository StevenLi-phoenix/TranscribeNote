import Testing
import Foundation
@testable import notetaker

@Suite("ActionItemParser")
struct ActionItemParserTests {

    // MARK: - JSON Parsing

    @Test("Parse valid JSON array")
    func parseValidJSON() {
        let input = """
        [
          {"content": "Review PR", "category": "task", "assignee": "Alice", "dueDate": "2026-04-01"},
          {"content": "Approved new design", "category": "decision", "assignee": null, "dueDate": null},
          {"content": "Check deployment", "category": "followUp", "assignee": "Bob", "dueDate": null}
        ]
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 3)
        #expect(items[0].content == "Review PR")
        #expect(items[0].category == "task")
        #expect(items[0].assignee == "Alice")
        #expect(items[0].dueDate == "2026-04-01")
        #expect(items[1].category == "decision")
        #expect(items[1].assignee == nil)
        #expect(items[2].category == "followUp")
        #expect(items[2].assignee == "Bob")
    }

    @Test("Parse JSON wrapped in markdown code fences")
    func parseJSONInCodeFences() {
        let input = """
        Here are the action items:
        ```json
        [
          {"content": "Update docs", "category": "task", "assignee": null, "dueDate": null}
        ]
        ```
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 1)
        #expect(items[0].content == "Update docs")
    }

    @Test("Parse JSON with preamble text")
    func parseJSONWithPreamble() {
        let input = """
        Based on the transcript, I've identified the following action items:
        [{"content": "Schedule follow-up", "category": "followUp", "assignee": null, "dueDate": null}]
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 1)
        #expect(items[0].content == "Schedule follow-up")
    }

    @Test("Parse JSON with think blocks")
    func parseJSONWithThinkBlocks() {
        let input = """
        <think>
        Let me analyze the transcript for action items...
        </think>
        [{"content": "Fix bug", "category": "task", "assignee": null, "dueDate": null}]
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 1)
        #expect(items[0].content == "Fix bug")
    }

    @Test("Empty JSON array returns empty")
    func emptyJSONArray() {
        let items = ActionItemParser.parse("[]")
        #expect(items.isEmpty)
    }

    @Test("Filter out items with empty content")
    func filterEmptyContent() {
        let input = """
        [
          {"content": "", "category": "task", "assignee": null, "dueDate": null},
          {"content": "Valid item", "category": "task", "assignee": null, "dueDate": null}
        ]
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 1)
        #expect(items[0].content == "Valid item")
    }

    // MARK: - Markdown Fallback

    @Test("Fallback to markdown checklist")
    func markdownFallback() {
        let input = """
        Here are the action items:
        - [ ] Review the proposal
        - [ ] Send follow-up email
        - [x] Approve budget
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 3)
        #expect(items[0].content == "Review the proposal")
        #expect(items[0].category == "task")
        #expect(items[1].content == "Send follow-up email")
        #expect(items[2].content == "Approve budget")
    }

    @Test("Markdown with asterisks")
    func markdownAsterisks() {
        let input = "* [ ] Task with asterisk"
        let items = ActionItemParser.parse(input)
        #expect(items.count == 1)
        #expect(items[0].content == "Task with asterisk")
    }

    // MARK: - Empty/Invalid Input

    @Test("Empty string returns empty")
    func emptyInput() {
        let items = ActionItemParser.parse("")
        #expect(items.isEmpty)
    }

    @Test("Gibberish returns empty")
    func gibberishInput() {
        let items = ActionItemParser.parse("This is just random text with no structure.")
        #expect(items.isEmpty)
    }

    @Test("Malformed JSON falls back to markdown")
    func malformedJSON() {
        let input = """
        [{"content": "Valid"
        - [ ] Fallback item
        """
        let items = ActionItemParser.parse(input)
        #expect(items.count == 1)
        #expect(items[0].content == "Fallback item")
    }

    // MARK: - Date Parsing

    @Test("Parse valid date string")
    func parseValidDate() {
        let date = ActionItemParser.parseDate("2026-04-01")
        #expect(date != nil)
        let calendar = Calendar.current
        #expect(calendar.component(.year, from: date!) == 2026)
        #expect(calendar.component(.month, from: date!) == 4)
        #expect(calendar.component(.day, from: date!) == 1)
    }

    @Test("Parse nil date string")
    func parseNilDate() {
        #expect(ActionItemParser.parseDate(nil) == nil)
    }

    @Test("Parse empty date string")
    func parseEmptyDate() {
        #expect(ActionItemParser.parseDate("") == nil)
    }

    @Test("Parse invalid date string")
    func parseInvalidDate() {
        #expect(ActionItemParser.parseDate("not-a-date") == nil)
    }
}

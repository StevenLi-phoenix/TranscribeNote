import Testing
import Foundation
@testable import notetaker

struct SummaryBlockTests {
    @Test func displayContentReturnsEditedWhenSet() {
        let block = SummaryBlock(
            coveringFrom: 0,
            coveringTo: 60,
            content: "Original content",
            editedContent: "Edited content"
        )
        #expect(block.displayContent == "Edited content")
    }

    @Test func displayContentFallsBackToContent() {
        let block = SummaryBlock(
            coveringFrom: 0,
            coveringTo: 60,
            content: "Original content"
        )
        #expect(block.displayContent == "Original content")
        #expect(block.editedContent == nil)
    }

    @Test func displayContentFallsBackWhenEditedIsNil() {
        let block = SummaryBlock(
            coveringFrom: 0,
            coveringTo: 60,
            content: "Original content",
            editedContent: nil
        )
        #expect(block.displayContent == "Original content")
    }
}

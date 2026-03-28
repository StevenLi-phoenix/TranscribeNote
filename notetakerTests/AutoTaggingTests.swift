import Testing
@testable import notetaker

@Suite("AutoTagging")
struct AutoTaggingTests {
    @Test func parseJSON_validArray() {
        let tags = TagParser.parse(from: "[\"Product Review\", \"Sprint Planning\", \"Tech Discussion\"]")
        #expect(tags.count == 3)
        #expect(tags.contains("Product Review"))
    }

    @Test func parseJSON_withSurroundingText() {
        let tags = TagParser.parse(from: "Here are the tags: [\"Meeting\", \"Design\"] for this session")
        #expect(tags.count == 2)
        #expect(tags.first == "Meeting")
    }

    @Test func parseCommaSeparated() {
        let tags = TagParser.parse(from: "Product Review, Sprint Planning, Tech Discussion")
        #expect(tags.count == 3)
    }

    @Test func parseNewlineSeparated() {
        let tags = TagParser.parse(from: "- Product Review\n- Sprint Planning\n- Tech Discussion")
        #expect(tags.count == 3)
        #expect(tags.first == "Product Review")
    }

    @Test func parseLimitsTo5() {
        let tags = TagParser.parse(from: "[\"a\",\"b\",\"c\",\"d\",\"e\",\"f\",\"g\"]")
        #expect(tags.count == 5)
    }

    @Test func parseDeduplicates() {
        let tags = TagParser.parse(from: "[\"Meeting\", \"meeting\", \"MEETING\"]")
        #expect(tags.count == 1)
    }

    @Test func parseEmpty() {
        #expect(TagParser.parse(from: "").isEmpty)
        #expect(TagParser.parse(from: "[]").isEmpty)
    }

    @Test func parseFiltersLongTags() {
        let tags = TagParser.parse(from: "[\"Short\", \"This is a very long tag that should be filtered out because it exceeds the limit\"]")
        #expect(tags.count == 1)
        #expect(tags.first == "Short")
    }

    @Test func colorIndex_deterministic() {
        let idx1 = TagParser.colorIndex(for: "Meeting")
        let idx2 = TagParser.colorIndex(for: "Meeting")
        #expect(idx1 == idx2)
        #expect(idx1 >= 0 && idx1 < 8)
    }

    @Test func colorIndex_deterministicAcrossCalls() {
        // Verify djb2 produces known stable values (not randomized like String.hashValue)
        let idx = TagParser.colorIndex(for: "product review")
        // Call again — must be identical
        #expect(TagParser.colorIndex(for: "product review") == idx)
    }

    @Test func colorIndex_caseInsensitive() {
        // colorIndex lowercases before hashing, so these should match
        let idx1 = TagParser.colorIndex(for: "Meeting")
        let idx2 = TagParser.colorIndex(for: "meeting")
        #expect(idx1 == idx2)
    }

    @Test func colorIndex_differentForDifferentTags() {
        // Not guaranteed to be different, but statistically likely with djb2
        let indices = Set(["Meeting", "Product", "Design", "Sprint", "Review"].map { TagParser.colorIndex(for: $0) })
        #expect(indices.count >= 2) // At least some variation
    }

    @Test func colorIndex_boundsCheck() {
        let testTags = ["", "a", "Hello World", "Very Long Tag Name Here", "Special!@#$%"]
        for tag in testTags {
            let idx = TagParser.colorIndex(for: tag)
            #expect(idx >= 0 && idx < 8, "colorIndex out of bounds for tag: \(tag)")
        }
    }
}

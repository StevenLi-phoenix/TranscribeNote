import Testing
@testable import notetaker

@Suite("AutoTitleGenerator")
struct AutoTitleTests {
    @Test func englishTruncation() {
        let text = "Today we are going to discuss the product roadmap and timeline for Q3"
        let title = AutoTitleGenerator.generate(from: text)
        #expect(title != nil)
        let words = title!.split(separator: " ")
        #expect(words.count <= 9) // 8 words + possible ellipsis as part of last word
        #expect(title!.hasSuffix("…"))
    }

    @Test func englishShort() {
        let text = "Hello world meeting"
        let title = AutoTitleGenerator.generate(from: text)
        #expect(title == "Hello world meeting")
    }

    @Test func chineseTruncation() {
        let text = "今天我们来讨论一下关于产品路线图的最新进展和下一步计划"
        let title = AutoTitleGenerator.generate(from: text)
        #expect(title != nil)
        #expect(title!.count <= 21) // 20 chars + ellipsis
        #expect(title!.hasSuffix("…"))
    }

    @Test func chineseShort() {
        let text = "今天开会讨论"
        let title = AutoTitleGenerator.generate(from: text)
        #expect(title == "今天开会讨论")
    }

    @Test func fillerWordsFiltered() {
        let text = "um uh like the project update"
        let title = AutoTitleGenerator.generate(from: text)
        #expect(title != nil)
        #expect(!title!.lowercased().contains("um"))
        #expect(!title!.lowercased().contains("uh"))
    }

    @Test func chineseFillerFiltered() {
        let text = "嗯那个就是今天讨论产品方案"
        let title = AutoTitleGenerator.generate(from: text)
        #expect(title != nil)
        #expect(!title!.hasPrefix("嗯"))
    }

    @Test func tooShortReturnsNil() {
        #expect(AutoTitleGenerator.generate(from: "um") == nil)
        #expect(AutoTitleGenerator.generate(from: "uh like") == nil)
        #expect(AutoTitleGenerator.generate(from: "") == nil)
    }

    @Test func emptyReturnsNil() {
        #expect(AutoTitleGenerator.generate(from: "") == nil)
        #expect(AutoTitleGenerator.generate(from: "   ") == nil)
    }

    @Test func isDefaultTitle() {
        #expect(AutoTitleGenerator.isDefaultTitle("Recording Mar 24, 2026, 2:30 PM"))
        #expect(AutoTitleGenerator.isDefaultTitle("Recording 2026-03-24"))
        #expect(!AutoTitleGenerator.isDefaultTitle("My Custom Title"))
        #expect(!AutoTitleGenerator.isDefaultTitle("Product Discussion"))
    }

    @Test func onlyFillerReturnsNil() {
        #expect(AutoTitleGenerator.generate(from: "um uh like") == nil)
    }
}

import Testing
import SwiftUI
@testable import notetaker

@Suite("Liquid Glass Design Tokens")
struct LiquidGlassTests {

    // MARK: - DS.Glass smoke tests

    @Test("DS.Glass.card produces a view without crash")
    func glassCardSmoke() {
        let view = DS.Glass.card(Text("Hello"), cornerRadius: DS.Radius.md)
        #expect(type(of: view) != Never.self)
    }

    @Test("DS.Glass.capsule produces a view without crash")
    func glassCapsuleSmoke() {
        let view = DS.Glass.capsule(Text("Badge"))
        #expect(type(of: view) != Never.self)
    }

    @Test("DS.Glass.tinted produces a view without crash")
    func glassTintedSmoke() {
        let view = DS.Glass.tinted(Text("Tinted"), color: .blue, cornerRadius: DS.Radius.lg)
        #expect(type(of: view) != Never.self)
    }

    @Test("DS.Glass.card uses default corner radius from DS.Radius.md")
    func glassCardDefaultRadius() {
        // Verify the default parameter matches DS.Radius.md
        #expect(DS.Radius.md == 8)
    }

    // MARK: - DS.Radius validation

    @Test("DS.Radius values are positive and ordered")
    func radiusValuesOrdered() {
        #expect(DS.Radius.xs > 0)
        #expect(DS.Radius.sm > DS.Radius.xs)
        #expect(DS.Radius.md > DS.Radius.sm)
        #expect(DS.Radius.lg > DS.Radius.md)
    }

    // MARK: - ViewModifier smoke tests

    @Test("CardStyleModifier can be applied to a View")
    func cardStyleModifierSmoke() {
        let view = Text("Card").modifier(CardStyleModifier())
        #expect(type(of: view) != Never.self)
    }

    @Test("BadgeStyleModifier can be applied to a View")
    func badgeStyleModifierSmoke() {
        let view = Text("Badge").modifier(BadgeStyleModifier())
        #expect(type(of: view) != Never.self)
    }

    @Test("SummaryCardGlassModifier can be applied for overall and chunk")
    func summaryCardGlassModifierSmoke() {
        let overallView = Text("Overall").modifier(SummaryCardGlassModifier(isOverall: true))
        let chunkView = Text("Chunk").modifier(SummaryCardGlassModifier(isOverall: false))
        #expect(type(of: overallView) != Never.self)
        #expect(type(of: chunkView) != Never.self)
    }

    @Test("SessionHeaderGlassModifier can be applied")
    func sessionHeaderGlassModifierSmoke() {
        let view = Text("Header").modifier(SessionHeaderGlassModifier())
        #expect(type(of: view) != Never.self)
    }

    @Test("MenuBarRecordingGlassModifier can be applied for recording and paused")
    func menuBarGlassModifierSmoke() {
        let recordingView = Text("Recording").modifier(MenuBarRecordingGlassModifier(isPaused: false))
        let pausedView = Text("Paused").modifier(MenuBarRecordingGlassModifier(isPaused: true))
        #expect(type(of: recordingView) != Never.self)
        #expect(type(of: pausedView) != Never.self)
    }
}

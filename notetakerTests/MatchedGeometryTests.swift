import Testing
import SwiftUI
@testable import notetaker

@Suite("MatchedGeometryTests")
struct MatchedGeometryTests {
    @Test("matchedGeometryEffectIfPresent with nil namespace returns view unchanged")
    func nilNamespaceNoOp() {
        let view = Text("Test")
        _ = view.matchedGeometryEffectIfPresent(id: "test", in: nil)
    }

    @Test("matchedGeometryEffectIfPresent with custom properties")
    func customProperties() {
        let view = Text("Test")
        _ = view.matchedGeometryEffectIfPresent(id: "test", in: nil, properties: .position)
    }

    @Test("matchedGeometryEffectIfPresent with custom anchor and isSource")
    func customAnchorAndSource() {
        let view = Text("Test")
        _ = view.matchedGeometryEffectIfPresent(
            id: "hero",
            in: nil,
            properties: .frame,
            anchor: .topLeading,
            isSource: false
        )
    }

    @Test("Spring animation parameters compile correctly")
    func springParameters() {
        let animation = Animation.spring(response: 0.4, dampingFraction: 0.85)
        _ = animation
    }
}

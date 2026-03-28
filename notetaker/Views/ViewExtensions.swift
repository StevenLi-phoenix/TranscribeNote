import SwiftUI

extension View {
    /// Applies matchedGeometryEffect only when a namespace is provided.
    /// This allows views to optionally participate in hero transitions.
    @ViewBuilder
    func matchedGeometryEffectIfPresent(
        id: String,
        in namespace: Namespace.ID?,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace, properties: properties, anchor: anchor, isSource: isSource)
        } else {
            self
        }
    }
}

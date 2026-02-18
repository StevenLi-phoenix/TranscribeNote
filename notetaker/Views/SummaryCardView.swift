import SwiftUI

struct SummaryCardView: View {
    let coveringFrom: TimeInterval
    let coveringTo: TimeInterval
    let content: String
    let model: String
    let isCompact: Bool

    @State private var isExpanded = false

    init(coveringFrom: TimeInterval, coveringTo: TimeInterval, content: String, model: String, isCompact: Bool = false) {
        self.coveringFrom = coveringFrom
        self.coveringTo = coveringTo
        self.content = content
        self.model = model
        self.isCompact = isCompact
    }

    init(block: SummaryBlock, isCompact: Bool = false) {
        self.coveringFrom = block.coveringFrom
        self.coveringTo = block.coveringTo
        self.content = block.content
        self.model = block.model
        self.isCompact = isCompact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(coveringFrom.mmss) – \(coveringTo.mmss)", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !model.isEmpty {
                    Text(model)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }

            if isCompact && !isExpanded {
                Text(content)
                    .lineLimit(3)
                    .font(.callout)

                if content.count > 150 {
                    Button("Show more") { isExpanded = true }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Text(content)
                    .font(.callout)
                    .textSelection(.enabled)

                if isCompact && isExpanded {
                    Button("Show less") { isExpanded = false }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

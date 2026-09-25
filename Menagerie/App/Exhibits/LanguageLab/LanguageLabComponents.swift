import SwiftUI

extension LanguageLab {
    /// A titled panel on the stage. The optional `source` names the API or
    /// algorithm behind the panel, such as "NLTagger" or "RAKE".
    struct StageCard<Content: View, Accessory: View>: View {
        let title: String
        let symbol: String
        let source: String?
        private let accessory: Accessory
        private let content: Content

        init(
            _ title: String,
            symbol: String,
            source: String? = nil,
            @ViewBuilder accessory: () -> Accessory,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.symbol = symbol
            self.source = source
            self.accessory = accessory()
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                    if let source {
                        Text(source)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.mutedInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    accessory
                }
                .frame(minHeight: 20)

                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
        }
    }

    /// A small round color key.
    struct Swatch: View {
        let color: Color
        var size: CGFloat = 8

        var body: some View {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }

    /// A muted one-line explanation under a chart.
    struct ChartCaption: View {
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A horizontal bar that grows from the left: square at its baseline,
    /// rounded at the end that carries the value.
    struct ValueBar: View {
        /// 0…1 of the available width.
        let fraction: Double
        let color: Color
        var height: CGFloat = 6

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(Palette.track)
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: min(4, height / 2),
                        topTrailingRadius: min(4, height / 2),
                        style: .continuous
                    )
                    .fill(color)
                    .frame(width: max(2, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
            .frame(height: height)
        }
    }

    /// Lays out views left to right and wraps them onto new lines, like
    /// words in a paragraph.
    struct FlowLayout: Layout {
        var spacing: CGFloat = 6
        var lineSpacing: CGFloat = 6

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let frames = arrange(subviews, width: proposal.width ?? .infinity)
            let usedWidth = frames.map(\.maxX).max() ?? 0
            let height = frames.map(\.maxY).max() ?? 0
            return CGSize(width: proposal.width.map { min($0, usedWidth) } ?? usedWidth, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let frames = arrange(subviews, width: bounds.width)
            for (subview, frame) in zip(subviews, frames) {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(frame.size)
                )
            }
        }

        private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
            var frames: [CGRect] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            for subview in subviews {
                var size = subview.sizeThatFits(.unspecified)
                size.width = min(size.width, width)
                if x > 0 && x + size.width > width {
                    x = 0
                    y += lineHeight + lineSpacing
                    lineHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            return frames
        }
    }

    /// Columns of cards, each card dropped into the shortest column, as
    /// many columns as fit.
    struct MasonryLayout: Layout {
        var minimumColumnWidth: CGFloat = 340
        /// On very wide stages, wider cards read better than one long row.
        var maximumColumns: Int = .max
        var spacing: CGFloat = 14

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let width = usableWidth(proposal.width)
            let frames = arrange(subviews, width: width)
            return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let frames = arrange(subviews, width: bounds.width)
            for (subview, frame) in zip(subviews, frames) {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: frame.width, height: frame.height)
                )
            }
        }

        private func usableWidth(_ proposed: CGFloat?) -> CGFloat {
            guard let proposed, proposed.isFinite else { return minimumColumnWidth }
            return proposed
        }

        private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
            let columns = min(maximumColumns, max(1, Int((width + spacing) / (minimumColumnWidth + spacing))))
            let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            var bottoms = [CGFloat](repeating: 0, count: columns)
            var isEmpty = [Bool](repeating: true, count: columns)
            var frames: [CGRect] = []
            for subview in subviews {
                let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
                let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
                let top = isEmpty[column] ? 0 : bottoms[column] + spacing
                frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: top, width: columnWidth, height: height))
                bottoms[column] = top + height
                isEmpty[column] = false
            }
            return frames
        }
    }
}

extension LanguageLab.StageCard where Accessory == EmptyView {
    init(
        _ title: String,
        symbol: String,
        source: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, symbol: symbol, source: source, accessory: { EmptyView() }, content: content)
    }
}

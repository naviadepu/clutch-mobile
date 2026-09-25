import SwiftUI

/// A deck card styled like a crossword poster: a paper frame with small
/// header/footer captions, one of the grainy aura gradients as the "photo",
/// a fine grid mapped over it, and the card's word spelled out in pink
/// letter tiles that sit in the grid's cells. Tap cards put their choices
/// under the poster.
struct CrosswordCard<Content: View>: View {
    let word: String
    let question: String
    /// Which of the six aura photos sits behind the grid.
    let aura: Int
    var footer: String?
    @ViewBuilder let content: Content

    static var paper: Color { Color(hex: 0xEEEAE6) }
    static var tilePink: Color { Color(hex: 0xF4B8CE) }
    static var ink: Color { Color.black.opacity(0.85) }
    private static var columns: Int { 10 }

    private var backgroundName: String { "card-aura-\(aura % 6 + 1)" }

    private var words: [String] {
        word.uppercased().split(separator: " ").map(String.init)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        VStack(spacing: 8) {
            HStack {
                Text("\u{2018}today\u{2019}")
                Spacer()
                Text("Clutch")
            }
            .font(.custom("HelveticaNeue", size: 10))

            Text(question)
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .tracking(-0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                grid(size: geo.size)
            }
            .clipped()

            content

            if let footer {
                Text(footer)
                    .font(.custom("HelveticaNeue", size: 9))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(Self.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Self.paper, in: shape)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }

    private func grid(size: CGSize) -> some View {
        let cell = size.width / CGFloat(Self.columns)
        let rows = max(words.count, Int(size.height / cell))
        let gridHeight = CGFloat(rows) * cell
        let placements = place(words, rows: rows)

        return ZStack(alignment: .topLeading) {
            Image(backgroundName)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: gridHeight)
                .clipped()

            ForEach(placements.indices, id: \.self) { i in
                let p = placements[i]
                ForEach(Array(p.word.enumerated()), id: \.offset) { j, letter in
                    Text(String(letter))
                        .font(.custom("HelveticaNeue", size: cell * 0.52))
                        .foregroundStyle(Self.ink)
                        .frame(width: cell, height: cell)
                        .background(Self.tilePink.opacity(0.95))
                        .offset(x: CGFloat(p.column + j) * cell, y: CGFloat(p.row) * cell)
                }
            }

            Path { path in
                for c in 0...Self.columns {
                    let x = CGFloat(c) * cell
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: gridHeight))
                }
                for r in 0...rows {
                    let y = CGFloat(r) * cell
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(.black.opacity(0.35), lineWidth: 0.6)
        }
        .frame(width: size.width, height: gridHeight)
        .frame(maxHeight: .infinity)
    }

    private struct Placement {
        let word: String
        let row: Int
        let column: Int
    }

    /// Words go on consecutive rows around the middle, staggered like the
    /// poster: a single word sits centred, the first of two hugs the left,
    /// the second the right.
    private func place(_ words: [String], rows: Int) -> [Placement] {
        let startRow = max(0, (rows - words.count) / 2)
        return words.enumerated().map { i, word in
            let len = min(word.count, Self.columns)
            let column: Int
            if words.count == 1 {
                column = (Self.columns - len) / 2
            } else if i.isMultiple(of: 2) {
                column = min(1, Self.columns - len)
            } else {
                column = max(0, Self.columns - len - 1)
            }
            return Placement(word: String(word.prefix(Self.columns)), row: startRow + i, column: column)
        }
    }
}

/// Uses the shared paper, tile and ink colours without naming a content type.
typealias CrosswordStyle = CrosswordCard<EmptyView>

extension CrosswordCard where Content == EmptyView {
    /// A symptom swipe: the poster alone.
    init(symptom: Symptom) {
        self.init(
            word: symptom.label,
            question: symptom.question,
            aura: Symptom.catalog.firstIndex { $0.id == symptom.id } ?? 0,
            footer: "swipe right for yes  \u{2022}  left for no"
        ) { EmptyView() }
    }
}

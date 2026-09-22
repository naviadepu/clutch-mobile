import SwiftUI

/// A symptom card styled like a crossword poster: a paper frame with small
/// header/footer captions, one of the grainy aura gradients as the "photo",
/// a fine grid mapped over it, and the symptom spelled out in pink letter
/// tiles that sit in the grid's cells.
struct CrosswordCard: View {
    let symptom: Symptom

    static let paper = Color(hex: 0xEEEAE6)
    static let tilePink = Color(hex: 0xF4B8CE)
    static let ink = Color.black.opacity(0.85)
    private static let columns = 10

    private var backgroundName: String {
        let index = Symptom.catalog.firstIndex(where: { $0.id == symptom.id }) ?? 0
        return "card-aura-\(index % 6 + 1)"
    }

    private var words: [String] {
        symptom.label.uppercased().split(separator: " ").map(String.init)
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
            .foregroundStyle(Self.ink)

            Text(symptom.question)
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .tracking(-0.4)
                .foregroundStyle(Self.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                grid(size: geo.size)
            }

            Text("swipe right to log  \u{2022}  left to skip")
                .font(.custom("HelveticaNeue", size: 9))
                .foregroundStyle(Self.ink.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Self.paper, in: shape)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }

    private func grid(size: CGSize) -> some View {
        let cell = size.width / CGFloat(Self.columns)
        let rows = max(words.count + 2, Int(size.height / cell))
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

/// Shown in place of the period card after swiping right: pick flow from
/// three pink crossword tiles.
struct FlowPicker: View {
    let onPick: (Flow) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\u{2018}today\u{2019}")
                Spacer()
                Text("Clutch")
            }
            .font(.custom("HelveticaNeue", size: 10))

            Spacer(minLength: 0)

            Text("How heavy is it?")
                .font(.custom("HelveticaNeue-Medium", size: 22))
                .tracking(-0.5)

            HStack(spacing: 0) {
                ForEach(Array(Flow.allCases.enumerated()), id: \.element) { index, flow in
                    Button { onPick(flow) } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 2) {
                                ForEach(0...index, id: \.self) { _ in
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 11))
                                }
                            }
                            Text(flow.title.uppercased())
                                .font(.custom("HelveticaNeue", size: 13))
                                .tracking(1.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(CrosswordCard.tilePink)
                        .overlay(Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 0.6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(flow.title) flow")
                }
            }

            Spacer(minLength: 0)

            Button("back", action: onBack)
                .font(.custom("HelveticaNeue", size: 11))
                .foregroundStyle(CrosswordCard.ink.opacity(0.7))
        }
        .foregroundStyle(CrosswordCard.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(CrosswordCard.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }
}

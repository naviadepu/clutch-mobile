import SwiftUI
import UIKit

// The daily log's cards: a crossword poster with the choices in pink
// letter tiles underneath. Swiping moves between cards; inputs are taps.

/// One crossword tile. Chosen tiles fill pink; the rest stay paper.
struct LetterTile: View {
    let title: String
    var detail: AnyView? = nil
    var isSelected = true
    var height: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            if let detail { detail }
            Text(title.uppercased())
                .font(.custom("HelveticaNeue", size: 11))
                .tracking(1.2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .padding(.horizontal, 4)
        .background(isSelected ? CrosswordStyle.tilePink : CrosswordStyle.paper)
        .overlay(Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 0.6))
        .contentShape(Rectangle())
    }
}

/// Tiles in rows of `columns`, joined edge to edge like a crossword.
struct TileGrid<Option: Hashable>: View {
    let options: [Option]
    var columns = 2
    var tileHeight: CGFloat = 38
    let title: (Option) -> String
    let isSelected: (Option) -> Bool
    let onTap: (Option) -> Void

    var body: some View {
        let rows = stride(from: 0, to: options.count, by: columns).map { Array(options[$0..<min($0 + columns, options.count)]) }
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r], id: \.self) { option in
                        Button { onTap(option) } label: {
                            LetterTile(title: title(option), isSelected: isSelected(option), height: tileHeight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
                    }
                    // Keep a short last row's tiles the same width.
                    ForEach(0..<(columns - rows[r].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// A small text button under a card's tiles: Skip, Done, back.
struct CardLink: View {
    let title: String
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(emphasized ? "HelveticaNeue-Medium" : "HelveticaNeue", size: emphasized ? 13 : 11))
                .foregroundStyle(CrosswordStyle.ink.opacity(emphasized ? 1 : 0.7))
                .padding(.horizontal, emphasized ? 18 : 6)
                .padding(.vertical, emphasized ? 8 : 4)
                .background {
                    if emphasized { Capsule().fill(CrosswordStyle.tilePink) }
                }
                .overlay {
                    if emphasized { Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.6) }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow

/// Card 4 while she's on her period. "Ended" saves today as the last day.
struct FlowCard: View {
    let onPick: (Flow) -> Void
    let onEnded: () -> Void

    var body: some View {
        CrosswordCard(word: "period", question: "How's your flow today?", aura: 2) {
            HStack(spacing: 0) {
                ForEach(Array([Flow.light, .medium, .heavy].enumerated()), id: \.element) { index, flow in
                    Button { onPick(flow) } label: {
                        LetterTile(title: flow.title, detail: AnyView(drops(index + 1)), height: 58)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(flow.title) flow")
                }
                Button(action: onEnded) {
                    LetterTile(title: "Ended", detail: AnyView(Image(systemName: "checkmark").font(.system(size: 11))), isSelected: false, height: 58)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Period ended")
            }
        }
    }

    private func drops(_ count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in Image(systemName: "drop.fill") }
        }
        .font(.system(size: 11))
    }
}

// MARK: - Mood and energy

/// Five tiles, 1 to 5, one tap.
struct LevelCard: View {
    let word: String
    let aura: Int
    let question: String
    let titles: [String]
    let onPick: (Int) -> Void

    var body: some View {
        CrosswordCard(word: word, question: question, aura: aura) {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(titles.indices, id: \.self) { index in
                        Button { onPick(index + 1) } label: {
                            LetterTile(title: "\(index + 1)", height: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(titles[index])
                    }
                }
                HStack {
                    Text(titles.first ?? "")
                    Spacer()
                    Text(titles.last ?? "")
                }
                .font(.custom("HelveticaNeue", size: 10))
                .opacity(0.8)
            }
        }
    }
}

// MARK: - Anything else?

/// Every symptom as a chip, pick any, then Done. None ends it straight away.
struct ChipsCard: View {
    let symptoms: [Symptom]
    let onDone: ([String]) -> Void

    @State private var chosen: Set<String> = []

    var body: some View {
        CrosswordCard(word: "anything else", question: "Anything else today?", aura: 3) {
            VStack(spacing: 8) {
                TileGrid(
                    options: symptoms.map(\.id) + ["none"],
                    columns: 3,
                    tileHeight: 32,
                    title: { id in Symptom.named(id)?.label ?? "None" },
                    isSelected: { chosen.contains($0) },
                    onTap: tap
                )
                CardLink(title: "Done", emphasized: true) { onDone(symptoms.map(\.id).filter(chosen.contains)) }
                    .disabled(chosen.isEmpty)
                    .opacity(chosen.isEmpty ? 0.5 : 1)
            }
        }
    }

    private func tap(_ id: String) {
        guard id != "none" else { return onDone([]) }
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }
}

// MARK: - What helped

/// Pick any that helped, then Done. "Nothing really" clears the rest.
struct HelpedCard: View {
    let question: String
    let options: [Helper]
    let onDone: ([Helper]) -> Void

    @State private var chosen: Set<Helper> = []

    var body: some View {
        CrosswordCard(word: "helped", question: question, aura: 4) {
            VStack(spacing: 8) {
                TileGrid(
                    options: options,
                    columns: 3,
                    tileHeight: 34,
                    title: \.title,
                    isSelected: { chosen.contains($0) },
                    onTap: toggle
                )
                CardLink(title: "Done", emphasized: true) {
                    onDone(options.filter(chosen.contains))
                }
                .disabled(chosen.isEmpty)
                .opacity(chosen.isEmpty ? 0.5 : 1)
            }
        }
    }

    private func toggle(_ helper: Helper) {
        if helper == .nothingReally {
            chosen = chosen.contains(helper) ? [] : [helper]
        } else {
            chosen.remove(.nothingReally)
            if chosen.contains(helper) { chosen.remove(helper) } else { chosen.insert(helper) }
        }
    }
}

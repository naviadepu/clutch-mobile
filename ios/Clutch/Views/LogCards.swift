import SwiftUI
import UIKit

// The tap cards in the daily deck: the same crossword poster as the
// symptom swipes, with their choices in pink letter tiles underneath.

/// A plain paper frame without the poster — for the back of a flipped
/// card, where the words need the room.
struct LogCardFrame<Content: View>: View {
    let question: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
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

            content
                .frame(maxHeight: .infinity)

            if let footer {
                Text(footer)
                    .font(.custom("HelveticaNeue", size: 9))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(CrosswordStyle.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CrosswordStyle.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }
}

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

struct FlowCard: View {
    let onPick: (Flow) -> Void

    var body: some View {
        CrosswordCard(word: "period", question: "Is your period happening today?", aura: 2) {
            HStack(spacing: 0) {
                ForEach(Array(Flow.allCases.enumerated()), id: \.element) { index, flow in
                    Button { onPick(flow) } label: {
                        LetterTile(title: flow.title, detail: AnyView(drops(index)), height: 58)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(flow == .noFlow ? "No period" : "\(flow.title) flow")
                }
            }
        }
    }

    private func drops(_ count: Int) -> some View {
        HStack(spacing: 2) {
            if count == 0 {
                Image(systemName: "drop")
            } else {
                ForEach(0..<count, id: \.self) { _ in Image(systemName: "drop.fill") }
            }
        }
        .font(.system(size: 11))
    }
}

// MARK: - Mood and energy

/// Five tiles, 1 to 5: tap one, or drag along them and let go.
struct LevelCard: View {
    let word: String
    let aura: Int
    let question: String
    let titles: [String]
    let onPick: (Int) -> Void

    @State private var highlighted: Int?

    var body: some View {
        CrosswordCard(word: word, question: question, aura: aura) {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(titles.indices, id: \.self) { index in
                            LetterTile(
                                title: "\(index + 1)",
                                isSelected: highlighted.map { index <= $0 } ?? true,
                                height: 48
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(titles[index])
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { onPick(index + 1) }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let index = level(at: drag.location.x, width: geo.size.width)
                                if index != highlighted {
                                    withAnimation(.easeOut(duration: 0.12)) { highlighted = index }
                                }
                            }
                            .onEnded { drag in
                                onPick(level(at: drag.location.x, width: geo.size.width) + 1)
                            }
                    )
                }
                .frame(height: 48)
                HStack {
                    Text(titles.first ?? "")
                    Spacer()
                    Text(highlighted.map { titles[$0].uppercased() } ?? "tap or drag")
                        .font(.custom("HelveticaNeue-Medium", size: 10))
                        .tracking(1.2)
                    Spacer()
                    Text(titles.last ?? "")
                }
                .font(.custom("HelveticaNeue", size: 10))
                .opacity(0.8)
            }
        }
    }

    private func level(at x: CGFloat, width: CGFloat) -> Int {
        let fraction = min(max(x / max(width, 1), 0), 0.999)
        return Int(fraction * CGFloat(titles.count))
    }
}

// MARK: - What helped

/// Pick any that helped, then Done. "Nothing really" (follow-up only)
/// clears the rest.
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

// MARK: - One-time questions

/// A question about her, asked once. Every one can be skipped.
struct OneTimeCard: View {
    let question: OneTimeQuestion
    let onAnswer: (@escaping (inout CycleProfile) -> Void) -> Void
    let onSkip: () -> Void

    @State private var periodDays = CycleProfile.typicalPeriodLength
    @State private var goals: Set<HelpGoal> = []

    var body: some View {
        CrosswordCard(word: question.word, question: question.question, aura: 5) {
            VStack(spacing: 8) {
                content
                CardLink(title: "Skip", action: onSkip)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch question {
        case .birthControl:
            TileGrid(options: BirthControl.allCases, tileHeight: 28, title: \.title, isSelected: { _ in false }) { choice in
                onAnswer { $0.birthControl = choice }
            }

        case .periodLength:
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    stepButton("minus") { periodDays = max(1, periodDays - 1) }
                    LetterTile(title: "\(periodDays) day\(periodDays == 1 ? "" : "s")", height: 44)
                    stepButton("plus") { periodDays = min(10, periodDays + 1) }
                }
                HStack(spacing: 10) {
                    CardLink(title: "Not sure") { onAnswer { $0.periodLength = nil } }
                    CardLink(title: "Save", emphasized: true) {
                        let days = periodDays
                        onAnswer { $0.periodLength = days }
                    }
                }
            }

        case .products:
            TileGrid(options: PeriodProduct.allCases, title: \.title, isSelected: { _ in false }) { choice in
                onAnswer { $0.products = [choice] }
            }

        case .student:
            TileGrid(options: [true, false], tileHeight: 48, title: { $0 ? "Yes" : "No" }, isSelected: { _ in false }) { choice in
                onAnswer { $0.isStudent = choice }
            }

        case .goals:
            VStack(spacing: 10) {
                TileGrid(
                    options: HelpGoal.allCases,
                    columns: 3,
                    tileHeight: 34,
                    title: \.title,
                    isSelected: { goals.contains($0) },
                    onTap: { goal in
                        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                    }
                )
                CardLink(title: "Done", emphasized: true) {
                    let picked = HelpGoal.allCases.filter(goals.contains)
                    onAnswer { $0.goals = picked }
                }
                .disabled(goals.isEmpty)
                .opacity(goals.isEmpty ? 0.5 : 1)
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 44, height: 44)
                .background(CrosswordStyle.paper)
                .overlay(Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "More days" : "Fewer days")
    }
}

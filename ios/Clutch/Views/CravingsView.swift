import SwiftUI

/// One idea on the cravings page, from `cravings.json`.
struct CravingCard: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let short: String
    let icon: String
    let why: String
    let minutes: Int
    let `where`: String
    let cravings: [String]
    let tags: [String]

    var placeLabel: String {
        switch `where` {
        case "dorm": "No kitchen needed"
        case "campus": "Grab it on campus"
        default: "Needs a kitchen"
        }
    }

    static let all: [CravingCard] = {
        struct File: Decodable { let cards: [CravingCard] }
        guard let url = Bundle.main.url(forResource: "cravings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.cards
    }()
}

enum Craving: String, CaseIterable, Identifiable {
    case sweet, salty, crunchy, chocolate, carbs, warm, cold
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .sweet: "birthday.cake"
        case .salty: "popcorn"
        case .crunchy: "carrot"
        case .chocolate: "square.grid.3x2"
        case .carbs: "fork.knife"
        case .warm: "mug"
        case .cold: "snowflake"
        }
    }
}

/// "Craving something": pick the craving, browse ideas that still hit the
/// spot. Never calls food good or bad, never mentions calories, and always
/// leaves room to just have the thing.
struct CravingsView: View {
    @State private var craving: Craving?
    @State private var saved: Set<String> = Set(InsightStore.snackList())
    @State private var flipped: String?
    private let beforePeriod: Bool

    init() {
        let engine = CycleEngine(logs: DayLogStore.allLogs(), profile: CycleProfile.load() ?? CycleProfile())
        beforePeriod = (engine.backwardOffset(for: .now) ?? 99) <= 7 || engine.periodDay(for: .now) != nil
    }

    var body: some View {
        ClutchPage(title: "craving something?", subtitle: "Pick one. Tap an idea to see why it helps.") {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Craving.allCases) { option in
                        Button { withAnimation(.easeInOut(duration: 0.2)) { craving = craving == option ? nil : option } } label: {
                            IconBubble(symbol: option.symbol, title: option.title, filled: craving == option, size: 54)
                                .frame(width: 68)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(craving == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .contentMargins(.horizontal, 20, for: .scrollContent)

            if beforePeriod {
                Label("Period's close: iron + magnesium first", systemImage: "leaf.fill")
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundStyle(Color.cardInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.matcha.opacity(0.25), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(cards) { card in ideaTile(card) }
                justHaveIt
            }
        }
    }

    /// Her saved ideas first, then iron and magnesium before her period.
    private var cards: [CravingCard] {
        let pool = CravingCard.all.filter { craving == nil || $0.cravings.contains(craving!.rawValue) }
        return pool.sorted { a, b in
            let sa = score(a), sb = score(b)
            return sa != sb ? sa > sb : a.title < b.title
        }
        .prefix(craving == nil ? 7 : 11)
        .map { $0 }
    }

    private func score(_ card: CravingCard) -> Int {
        (saved.contains(card.title) ? 2 : 0) + (beforePeriod && !card.tags.isEmpty ? 1 : 0)
    }

    private func ideaTile(_ card: CravingCard) -> some View {
        let open = flipped == card.id
        return Button { withAnimation(.easeInOut(duration: 0.25)) { flipped = open ? nil : card.id } } label: {
            VStack(spacing: 6) {
                if open {
                    Text(card.why)
                        .font(.custom("DMSans-Light", size: 12.5))
                        .foregroundStyle(Color.cardInk)
                        .multilineTextAlignment(.center)
                        .frame(maxHeight: .infinity)
                } else {
                    Image(systemName: card.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(Color.cardInk)
                        .frame(width: 64, height: 64)
                        .background(Color.strawberry, in: Circle())
                        .frame(maxHeight: .infinity)
                    Text(card.short)
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundStyle(Color.cardInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                HStack(spacing: 10) {
                    Label("\(card.minutes)m", systemImage: "clock")
                    Image(systemName: card.where == "kitchen" ? "frying.pan" : card.where == "campus" ? "building.columns" : "house")
                        .accessibilityLabel(card.placeLabel)
                }
                .font(.custom("DMSans-Light", size: 11))
                .foregroundStyle(Color.cardSoft)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Color.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: 0x4A3328).opacity(0.08), radius: 14, y: 7)
            .overlay(alignment: .topTrailing) { heart(card) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.title), \(card.minutes) minutes, \(card.placeLabel)")
        .accessibilityHint(open ? card.why : "Shows why it helps")
    }

    private func heart(_ card: CravingCard) -> some View {
        Button {
            if !saved.contains(card.title) {
                InsightStore.addSnack(card.title)
                saved.insert(card.title)
            }
        } label: {
            Image(systemName: saved.contains(card.title) ? "heart.fill" : "heart")
                .foregroundStyle(Color(hex: 0xE58DAA))
                .font(.system(size: 15))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(saved.contains(card.title) ? "Saved to your snack list" : "Save to your snack list")
    }

    /// Always last: no swap needed.
    private var justHaveIt: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color(hex: 0xE58DAA))
                .frame(width: 64, height: 64)
                .background(Color.cream, in: Circle())
                .frame(maxHeight: .infinity)
            Text("Or just have it")
                .font(.custom("DMSans-Regular", size: 14))
                .foregroundStyle(Color.cardInk)
            Text("totally allowed").font(.custom("DMSans-Light", size: 11)).foregroundStyle(Color.cardSoft)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.strawberry.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import UIKit

/// "See full details": what her logs add up to, in plain sentences with
/// one thing to do each. When her next period is likely, what today
/// means, what Clutch has learned about her, whether her cycles sit in the
/// ranges doctors use, and a summary she can take to a doctor. Every fact
/// with a source behind it gets a "Why?" link to that source.
struct DetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var data = DetailsData.load()
    @State private var why: WhyItem?

    var body: some View {
        ZStack {
            AuraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("your details")
                        .font(.custom("InterTight-SemiBold", size: 30))
                        .tracking(-1.2)
                        .foregroundStyle(Color.cardInk)

                    if data.plan.showsSupport {
                        SupportCard()
                    }

                    NextPeriodCard(data: data, why: showWhy)
                    TodayLineCard(data: data, why: showWhy)
                    KnowsYouCard(data: data, why: showWhy)
                    CycleCheckCard(data: data, why: showWhy)
                    DoctorSummaryCard(data: data)

                    if let question = data.question {
                        KnowYouCard(question: question) { data = DetailsData.load() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.cardInk)
                    .frame(width: 36, height: 36)
                    .background(Color.cream, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 12)
            .accessibilityLabel("Back")
        }
        .sheet(item: $why) { item in
            WhySheet(item: item)
                .presentationDetents([.medium, .large])
        }
    }

    private func showWhy(_ item: WhyItem) { why = item }
}

// MARK: - Data

/// Everything the page reads, loaded once when it opens.
struct DetailsData {
    let profile: CycleProfile
    let today: DayLog
    let engine: CycleEngine
    let plan: CycleEngine.DetailsPlan
    let question: OneTimeQuestion?

    static func load(now: Date = .now) -> DetailsData {
        let profile = CycleProfile.load() ?? CycleProfile()
        let logs = DayLogStore.allLogs()
        let today = DayLogStore.load(for: now) ?? DayLog(date: Calendar.current.startOfDay(for: now), seed: 0)
        let engine = CycleEngine(logs: logs, profile: profile)
        return DetailsData(
            profile: profile,
            today: today,
            engine: engine,
            plan: engine.detailsPlan(for: today),
            question: DeckPlanner(engine: engine).dueQuestion(on: now)
        )
    }

    var date: Date { today.date }
    var phase: CycleEngine.Phase? { engine.phase(for: date) }
    var dayPhrase: String { InsightCopy.dayPhrase(engine: engine, on: date) }

    /// "Day 2 · Period" under the header.
    var dayLabel: String {
        if let periodDay = engine.periodDay(for: date) { return "Period, day \(periodDay)" }
        guard let cycleDay = engine.cycleDay(for: date) else { return "Cycle day not known yet" }
        return "Day \(cycleDay)" + (phase.map { " \u{00B7} \($0.title)" } ?? "")
    }

    /// "Oct 3 to 6" / "any day now".
    var windowText: String? {
        guard let window = engine.nextPeriodWindow(after: date) else { return nil }
        if window.isLate { return "any day now" }
        return Self.range(window.earliest, window.latest)
    }

    static func range(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.current
        let first = start.formatted(.dateTime.month(.abbreviated).day())
        if calendar.isDate(start, inSameDayAs: end) { return first }
        let last = calendar.isDate(start, equalTo: end, toGranularity: .month)
            ? end.formatted(.dateTime.day())
            : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(first) to \(last)"
    }

    func whyItem(_ context: LearnLibrary.Context) -> WhyItem? {
        LearnLibrary.shared.topic(for: context).map { WhyItem(topic: $0, forYou: $0.forYou(dayPhrase: dayPhrase)) }
    }

    /// Her logged symptoms, phase and facts, for a "Why?" link.
    func context(symptoms: Set<String>? = nil, extra: Set<String> = []) -> LearnLibrary.Context {
        LearnLibrary.Context(
            symptoms: symptoms ?? Set(today.symptoms),
            phase: phase,
            insights: engine.learnInsights(for: today).union(extra)
        )
    }
}

// MARK: - Shared pieces

/// The page's card: cream stock with a whisper of grain, a light serif
/// title, and an optional "Why?" link.
struct DetailsCard<Content: View>: View {
    let title: String
    var why: WhyItem?
    var onWhy: ((WhyItem) -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.custom("CormorantGaramond-Light", size: 24))
                    .foregroundStyle(Color.cardInk)
                Spacer(minLength: 8)
                if let why, let onWhy {
                    WhyButton { onWhy(why) }
                }
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cream)
                .overlay {
                    GrainOverlay()
                        .blendMode(.multiply)
                        .opacity(0.07)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
        .shadow(color: Color(hex: 0x4A3328).opacity(0.10), radius: 30, y: 16)
    }
}

struct WhyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Why?")
                .font(.custom("DMSans-Regular", size: 12))
                .foregroundStyle(Color.cardSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Color.cardRule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Body text, small print, and the capped labels used across the page.
extension Text {
    func detailsBody() -> some View {
        font(.custom("DMSans-Light", size: 15))
            .foregroundStyle(Color.cardInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    func detailsSmall() -> some View {
        font(.custom("DMSans-Light", size: 12))
            .foregroundStyle(Color.cardSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    func detailsLabel() -> some View {
        font(.custom("DMSans-Light", size: 9.5))
            .tracking(0.95)
            .foregroundStyle(Color.cardSoft)
    }
}

/// A soft pill: what she logged, or an answer to pick.
struct DetailsChip: View {
    let title: String
    var isSelected = true

    var body: some View {
        Text(title)
            .font(.custom("DMSans-Regular", size: 13))
            .foregroundStyle(Color.cardInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.strawberry : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? .clear : Color.cardRule, lineWidth: 1))
    }
}

/// Chips that wrap onto new lines.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// "Does this match you?" — saved on the device only.
struct MatchRow: View {
    let insight: String
    let text: String

    @State private var answer: Bool?

    var body: some View {
        if let answer {
            Text(answer ? "Glad it fits." : "Thanks, Clutch will keep learning.").detailsSmall()
        } else {
            HStack(spacing: 8) {
                Text("Does this match you?").detailsSmall()
                Spacer(minLength: 0)
                ForEach([true, false], id: \.self) { matches in
                    Button {
                        InsightStore.record(.init(date: .now, insight: insight, text: text, matches: matches))
                        withAnimation(.easeInOut(duration: 0.2)) { answer = matches }
                    } label: {
                        DetailsChip(title: matches ? "Yes" : "No", isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension CycleEngine.Phase {
    /// Soft band colours from the existing palette.
    var color: Color {
        switch self {
        case .period: CrosswordStyle.tilePink
        case .rising: Color.strawberry
        case .strongest: Color.matcha.opacity(0.45)
        case .windingDown: OnboardingStyle.lavender.opacity(0.6)
        }
    }
}

// MARK: - Support

private struct SupportCard: View {
    var body: some View {
        let support = SymptomTips.shared.supportLink
        DetailsCard(title: "You're not alone") {
            Text(support.text).detailsBody()
            Link(destination: support.url) {
                DetailsChip(title: support.linkTitle)
            }
        }
    }
}

// MARK: - Today in one line

private struct TodayLineCard: View {
    let data: DetailsData
    let why: (WhyItem) -> Void

    private var line: String {
        data.plan.isEarlyDays
            ? InsightCopy.earlyHeader(engine: data.engine, today: data.today)
            : InsightCopy.text(for: data.plan.header)
    }

    private var logged: [String] {
        var items: [String] = []
        if data.today.periodStarted { items.append("Period started") }
        if let flow = data.today.flow, flow.isBleeding { items.append("\(flow.title) flow") }
        if data.today.periodEnded { items.append("Period ended") }
        if let mood = data.today.mood { items.append("Mood: \(LevelScale.moodTitles[mood - 1].lowercased())") }
        if let energy = data.today.energy { items.append("Energy: \(LevelScale.energyTitles[energy - 1].lowercased())") }
        items += Symptom.catalog.filter { data.today.said($0.id) }.map(\.label)
        if data.today.nothingToday { items.append("Nothing today") }
        return items
    }

    var body: some View {
        DetailsCard(title: "Today in one line", why: data.whyItem(data.context(extra: ["cyclePhases"])), onWhy: why) {
            Text(data.dayLabel.uppercased()).detailsLabel()
            Text(line)
                .font(.custom("DMSans-Light", size: 19))
                .foregroundStyle(Color.cardInk)
                .fixedSize(horizontal: false, vertical: true)
            if !logged.isEmpty {
                ChipFlow {
                    ForEach(logged, id: \.self) { DetailsChip(title: $0) }
                }
            }
            if !data.plan.isEarlyDays && data.plan.header.asksForMatch {
                MatchRow(insight: "today.header", text: line)
            }
            if let first = data.plan.symptoms.first, let entry = SymptomTips.shared[first.id] {
                Rectangle().fill(Color.cardRule).frame(height: 0.5)
                Text(InsightCopy.text(for: first.insight, symptomID: first.id)).detailsBody()
                SymptomActionButton(action: entry.action, today: data.today)
            }
        }
    }
}

// MARK: - Help Clutch know you

private struct KnowYouCard: View {
    let question: OneTimeQuestion
    let onChange: () -> Void

    @State private var periodDays = CycleProfile.typicalPeriodLength
    @State private var goals: Set<HelpGoal> = []
    @State private var saved = false

    var body: some View {
        DetailsCard(title: "Help Clutch know you") {
            if saved {
                Text("Saved. Thanks, that helps.").detailsBody()
            } else {
                Text(question.question)
                    .font(.custom("DMSans-Regular", size: 16))
                    .foregroundStyle(Color.cardInk)
                Text(question.why).detailsSmall()
                options
                Button("Skip for now") { skip() }
                    .font(.custom("DMSans-Light", size: 12))
                    .foregroundStyle(Color.cardSoft)
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch question {
        case .birthControl:
            ChipFlow {
                ForEach(BirthControl.allCases) { choice in
                    chip(choice.title, selected: false) { answer { $0.birthControl = choice } }
                }
            }
        case .periodLength:
            HStack(spacing: 10) {
                chip("\u{2212}", selected: false) { periodDays = max(1, periodDays - 1) }
                Text("\(periodDays) day\(periodDays == 1 ? "" : "s")").detailsBody()
                chip("+", selected: false) { periodDays = min(10, periodDays + 1) }
                Spacer(minLength: 0)
                chip("Not sure", selected: false) { answer { $0.periodLength = nil } }
                chip("Save", selected: true) {
                    let days = periodDays
                    answer { $0.periodLength = days }
                }
            }
        case .products:
            ChipFlow {
                ForEach(PeriodProduct.allCases) { choice in
                    chip(choice.title, selected: false) { answer { $0.products = [choice] } }
                }
            }
        case .student:
            HStack(spacing: 8) {
                chip("Yes", selected: false) { answer { $0.isStudent = true } }
                chip("No", selected: false) { answer { $0.isStudent = false } }
            }
        case .goals:
            ChipFlow {
                ForEach(HelpGoal.allCases) { goal in
                    chip(goal.title, selected: goals.contains(goal)) {
                        if goals.contains(goal) { goals.remove(goal) } else { goals.insert(goal) }
                    }
                }
                if !goals.isEmpty {
                    chip("Done", selected: true) {
                        let picked = HelpGoal.allCases.filter(goals.contains)
                        answer { $0.goals = picked }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { DetailsChip(title: title, isSelected: selected) }
            .buttonStyle(.plain)
    }

    private func answer(_ update: (inout CycleProfile) -> Void) {
        var profile = CycleProfile.load() ?? CycleProfile()
        update(&profile)
        profile.oneTimeCards[question.id, default: OneTimeCardState()].answered = true
        profile.oneTimeCards[question.id, default: OneTimeCardState()].answeredOn = .now
        profile.save()
        withAnimation(.easeInOut(duration: 0.2)) { saved = true }
    }

    private func skip() {
        var profile = CycleProfile.load() ?? CycleProfile()
        profile.oneTimeCards[question.id, default: OneTimeCardState()].skips.append(.now)
        profile.save()
        onChange()
    }
}

// MARK: - Why?

struct WhyItem: Identifiable {
    let id = UUID()
    let topic: LearnLibrary.Topic
    let forYou: String
}

/// Three layers: how it connects to her, a short explainer, and the
/// research (only when the founder has added vetted sources).
struct WhySheet: View {
    let item: WhyItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("For you") { Text(item.forYou).detailsBody() }
                if !item.topic.explainer.isEmpty {
                    section("Go deeper") { Text(item.topic.explainer).detailsBody() }
                }
                if !item.topic.sources.isEmpty {
                    section("The research") {
                        ForEach(item.topic.sources, id: \.self) { source in
                            Link(destination: source.url) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.custom("DMSans-Regular", size: 14))
                                        .foregroundStyle(Color.cardInk)
                                        .underline()
                                        .multilineTextAlignment(.leading)
                                    Text(source.year.map { "\(source.publisher), \(String($0))" } ?? source.publisher).detailsSmall()
                                    Text(source.takeaway).detailsSmall()
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.cream.ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).detailsLabel()
            content()
        }
    }
}

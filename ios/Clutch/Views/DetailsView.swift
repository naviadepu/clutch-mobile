import SwiftUI
import UIKit

/// "See full details": two pictures and a few doors. Her cycle as a strip
/// of phases with today on it and her own numbers; how she's been feeling
/// as a fortnight of faces and her most common symptoms; then resources:
/// the science behind today, a doctor summary, and free pads nearby.
struct DetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var data = DetailsData.load()
    @State private var why: WhyItem?
    @State private var showRequest = false

    var body: some View {
        ZStack {
            AuraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("your cycle so far")
                            .font(.custom("InterTight-SemiBold", size: 30))
                            .tracking(-1.2)
                            .foregroundStyle(Color.cardInk)
                        Text(data.dayLabel)
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundStyle(Color.cardInk.opacity(0.7))
                    }

                    CycleStripCard(data: data)
                    FeelingsCard(data: data)
                    resources
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
        .sheet(isPresented: $showRequest) { RequestView() }
    }

    /// Three doors, in the dock's tile style.
    private var resources: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESOURCES").detailsLabel().padding(.leading, 4)
            HStack(spacing: 10) {
                if let item = data.whyItem(data.context(extra: ["cyclePhases"])) {
                    resource("Why you feel this way", symbol: "sparkles", palette: AuraTile.hints[2]) { why = item }
                }
                resource("Doctor summary", symbol: "doc.text", palette: AuraTile.hints[0]) {
                    if let url = DoctorSummary.makePDF(engine: data.engine, profile: data.profile, today: data.date) {
                        BouquetSharing.presentShareSheet(items: [url])
                    }
                }
                resource("Free pads near you", symbol: "map", palette: AuraTile.hints[3]) { showRequest = true }
            }
            if data.plan.showsSupport {
                Link(destination: URL(string: "tel:988")!) {
                    Label("Feeling low a lot? Talk to someone: call or text 988", systemImage: "heart")
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundStyle(Color.cardInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.cream, in: Capsule())
                }
            }
        }
    }

    private func resource(_ title: String, symbol: String, palette: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                AuraTile(palette: palette, symbol: symbol).frame(width: 42, height: 42)
                Text(title)
                    .font(.custom("DMSans-Regular", size: 13))
                    .foregroundStyle(Color.cardInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(Color.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: 0x4A3328).opacity(0.08), radius: 14, y: 7)
        }
        .buttonStyle(.plain)
    }
}

/// Her cycle as one strip: a colored segment per phase with its icon, a
/// marker on today, what today means in a line, and her own numbers.
private struct CycleStripCard: View {
    let data: DetailsData

    var body: some View {
        let engine = data.engine
        let length = max(engine.typicalCycleLength, 1)
        let spans = engine.phaseSpans
        let cycleDay = engine.cycleDay(for: data.date)

        Panel(padding: 20) {
            Text("YOUR CYCLE").detailsLabel()

            GeometryReader { geo in
                let unit = geo.size.width / CGFloat(length)
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        ForEach(spans, id: \.phase) { span in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(span.phase.tint.opacity(data.phase == span.phase ? 1 : 0.55))
                                .frame(width: max(unit * CGFloat(span.lastDay - span.firstDay + 1) - 3, 10))
                                .overlay(
                                    Image(systemName: span.phase.symbol)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                    if let cycleDay {
                        VStack(spacing: 3) {
                            Text("today").font(.custom("DMSans-Regular", size: 9)).foregroundStyle(Color.cardInk)
                            Capsule().fill(Color.cardInk).frame(width: 3, height: 40)
                        }
                        .offset(x: min(CGFloat(cycleDay) - 0.5, CGFloat(length)) * unit - 1.5, y: -8)
                    }
                }
            }
            .frame(height: 30)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(data.dayLabel)

            if let phase = data.phase {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: phase.symbol).foregroundStyle(phase.tint).font(.system(size: 16))
                    Text(InsightCopy.phaseNote(engine: engine, on: data.date)).detailsBody()
                }
            }

            HStack(spacing: 8) {
                stat("\(engine.typicalCycleLength)", "day cycle")
                stat("\(engine.usualPeriodLength)", "day period")
                if let window = data.windowText { stat(window, "next period") }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("InterTight-SemiBold", size: value.count > 4 ? 15 : 22))
                .foregroundStyle(Color.cardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.custom("DMSans-Light", size: 11)).foregroundStyle(Color.cardSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The last two weeks as mood faces, her most common symptoms, and what
/// has helped her.
private struct FeelingsCard: View {
    let data: DetailsData

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: data.date)
        return (0..<14).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var topSymptoms: [(id: String, count: Int)] {
        let recent = data.engine.logs.filter { $0.date >= (days.first ?? .distantPast) }
        let counts = Dictionary(grouping: recent.flatMap(\.symptoms), by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    var body: some View {
        Panel(padding: 20) {
            Text("HOW YOU'VE BEEN FEELING").detailsLabel()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 10) {
                ForEach(days, id: \.self) { day in
                    let mood = data.engine.log(on: day)?.mood
                    VStack(spacing: 4) {
                        Group {
                            if let mood {
                                MoodFace(level: mood, size: 26)
                            } else {
                                Circle().strokeBorder(Color.cardRule, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                    .frame(width: 26, height: 26)
                            }
                        }
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.custom("DMSans-Light", size: 10)).foregroundStyle(Color.cardSoft)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()) + (mood.map { ": mood \($0) of 5" } ?? ": not logged"))
                }
            }

            if !topSymptoms.isEmpty {
                HStack(spacing: 8) {
                    ForEach(topSymptoms, id: \.id) { item in
                        HStack(spacing: 6) {
                            Image(systemName: LogIcon.symptom(item.id)).font(.system(size: 12))
                            Text(Symptom.named(item.id)?.label ?? item.id)
                            Text("\(item.count)").foregroundStyle(Color.cardSoft)
                        }
                        .font(.custom("DMSans-Regular", size: 12))
                        .foregroundStyle(Color.cardInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.strawberry.opacity(0.6), in: Capsule())
                    }
                }
            }

            if let helper = data.engine.helperRanking.first {
                HStack(spacing: 10) {
                    Image(systemName: LogIcon.helper(helper.helper)).foregroundStyle(Color.matcha)
                    Text("\(helper.helper.phrase.prefix(1).uppercased() + helper.helper.phrase.dropFirst()) helps you most.").detailsBody()
                }
            } else if topSymptoms.isEmpty {
                Text("Check in for a few days and your patterns show up here.").detailsSmall()
            }
        }
    }
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

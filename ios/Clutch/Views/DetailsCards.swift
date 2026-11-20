import SwiftUI
import UIKit

// The details page's cards: a sentence or two each, one thing to do, and a
// "Why?" link wherever a source backs the fact.

// MARK: - Next period

/// When it's likely, how sure Clutch is, and a nudge to be ready.
struct NextPeriodCard: View {
    let data: DetailsData
    let why: (WhyItem) -> Void

    @State private var reminder: String?

    private var window: CycleEngine.PeriodWindow? { data.engine.nextPeriodWindow(after: data.date) }

    var body: some View {
        DetailsCard(title: "Next period", why: data.whyItem(.init(insights: ["prediction"])), onWhy: why) {
            if let periodDay = data.engine.periodDay(for: data.date), let start = data.engine.cycleStart(for: data.date) {
                Text("Period, day \(periodDay)")
                    .font(.custom("DMSans-Regular", size: 22))
                    .foregroundStyle(Color.cardInk)
                let end = data.engine.day(data.engine.usualPeriodLength - 1, from: start)
                Text("For you it usually lasts \(data.engine.usualPeriodLength) days, so it's likely over around \(end.formatted(.dateTime.weekday(.wide))). Tap Ended on the Flow card when it is.")
                    .detailsBody()
            } else if let window {
                Text(window.isLate ? "Any day now" : "Likely \(DetailsData.range(window.earliest, window.latest))")
                    .font(.custom("DMSans-Regular", size: 22))
                    .foregroundStyle(Color.cardInk)
                Text(countdown(window)).detailsBody()
                reminderButton(window)
                Text(basis.uppercased()).detailsLabel()
            } else {
                Text("Tap \u{201C}My period started\u{201D} on the Today screen when it comes, and Clutch will predict the next one.")
                    .detailsBody()
            }
        }
    }

    private func countdown(_ window: CycleEngine.PeriodWindow) -> String {
        if window.isLate { return "It's a little later than your usual. Cycles shift for lots of reasons, stress included." }
        let days = data.engine.days(from: data.date, to: window.earliest)
        if days <= 0 { return "You're in your window now. Keep a pad or tampon with you." }
        return "Starts in about \(days) day\(days == 1 ? "" : "s")."
    }

    /// "Based on 4 of your cycles" — the window narrows as she logs more.
    private var basis: String {
        let count = data.engine.plausibleCycles.count
        if count >= 2 { return "Based on \(count) of your cycles" }
        if data.profile.cycleLength != nil { return "Based on the cycle length you gave. Gets sharper as you log." }
        return "Based on a typical 28-day cycle. Gets sharper as you log."
    }

    @ViewBuilder
    private func reminderButton(_ window: CycleEngine.PeriodWindow) -> some View {
        if let reminder {
            Text(reminder).detailsSmall()
        } else if !window.isLate {
            Button {
                // 8 pm the evening before the window opens.
                let evening = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: data.engine.day(-1, from: window.earliest))
                Task {
                    let ok = await LocalReminders.schedule(body: "Your period could start tomorrow. Pack a pad or tampon.", at: evening ?? window.earliest)
                    reminder = ok ? "Reminder set for the evening before." : "Turn on notifications for Clutch in Settings to get reminders."
                }
            } label: {
                DetailsChip(title: "Remind me to pack a pad")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - What Clutch knows about you

struct KnowsYouCard: View {
    let data: DetailsData
    let why: (WhyItem) -> Void

    var body: some View {
        let facts = data.engine.personalFacts()
        DetailsCard(title: "What Clutch knows about you") {
            if facts.isEmpty {
                Text("After your next period, Clutch starts telling you your own patterns: when things start, how long they last, and what helps you.")
                    .detailsBody()
                Text(progressLine.uppercased()).detailsLabel()
            } else {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 { Rectangle().fill(Color.cardRule).frame(height: 0.5) }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(fact.text).detailsBody()
                        Spacer(minLength: 0)
                        if let topic = fact.topic,
                           let item = LearnLibrary.shared.topics.first(where: { $0.id == topic })
                            .map({ WhyItem(topic: $0, forYou: $0.forYou(dayPhrase: data.dayPhrase)) }) {
                            WhyButton { why(item) }
                        }
                    }
                    MatchRow(insight: "fact.\(fact.topic ?? "symptom")", text: fact.text)
                }
            }
        }
    }

    private var progressLine: String {
        let cycles = data.engine.plausibleCycles.count
        guard cycles == 0, let day = data.engine.cycleDay(for: data.date) else {
            return "\(cycles) full cycle\(cycles == 1 ? "" : "s") logged"
        }
        return "Day \(day) of your first full cycle"
    }
}

// MARK: - Your cycle check

/// Her cycles against the ranges doctors use (FIGO; ACOG for teens).
struct CycleCheckCard: View {
    let data: DetailsData
    let why: (WhyItem) -> Void

    var body: some View {
        DetailsCard(title: "Your cycle check", why: data.whyItem(.init(insights: ["cycleCheck"])), onWhy: why) {
            switch data.engine.cycleCheck() {
            case let .notEnoughData(have):
                Text("After 3 cycles, Clutch checks yours against the ranges doctors use: how often periods come, how much that varies, and how long they last.")
                    .detailsBody()
                Text("\(min(have, 3)) of 3 cycles so far".uppercased()).detailsLabel()
            case let .inRange(shortest, longest):
                Text(shortest == longest
                     ? "Your cycles are in the usual range, \(shortest) days each."
                     : "Your cycles are in the usual range, \(shortest) to \(longest) days.")
                    .detailsBody()
            case let .outsideRange(reasons):
                ForEach(reasons, id: \.self) { Text($0).detailsBody() }
                Text("This can happen for lots of reasons. It might be worth mentioning to a doctor, and your doctor summary below has the details.")
                    .detailsSmall()
            }
        }
    }
}

// MARK: - Doctor summary

struct DoctorSummaryCard: View {
    let data: DetailsData

    var body: some View {
        DetailsCard(title: "Doctor summary") {
            Text("A one-page summary of your cycles, symptoms and what helps, ready to show a doctor. It stays on your phone until you choose where to send it.")
                .detailsBody()
            Button {
                if let url = DoctorSummary.makePDF(engine: data.engine, profile: data.profile, today: data.date) {
                    BouquetSharing.presentShareSheet(items: [url])
                }
            } label: {
                DetailsChip(title: "Create doctor summary")
            }
            .buttonStyle(.plain)
        }
    }
}

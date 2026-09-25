import SwiftUI
import UIKit

/// Everything the app knows about her, on one page: her name, where she is
/// in her cycle, what she told onboarding, today's check-in and her streak.
/// Reached from "See your details" under the finished bouquet. Every
/// answer she's given — onboarding and the one-time cards — can be
/// changed here. A first pass — the fuller profile is still to be designed.
struct YouView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var profile = CycleProfile.load() ?? CycleProfile()
    private let signature = SignatureStore.load()
    private let today = DayLogStore.load(for: .now)
    private let collection = BouquetCollection.load()

    private static let cream = Color(hex: 0xF5F1EA)
    private static let ink = Color(hex: 0x3B2F2A)
    private static let soft = Color(hex: 0x857469)
    private static let rule = Color(hex: 0x3B2F2A).opacity(0.12)

    var body: some View {
        ZStack {
            AuraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    card("Your cycle") {
                        if let cycle = cycleNow {
                            row("Today", "Day \(cycle.day)")
                            row("Next period", cycle.nextStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), note: "estimate")
                            row("Last started", cycle.lastStart.formatted(.dateTime.month(.abbreviated).day()))
                        } else {
                            row("Last started", "Not logged yet", muted: true)
                        }
                        row("Cycle length", "\(profile.effectiveCycleLength) days", note: profile.cycleLength == nil ? "typical" : nil)
                        row("Period length", "\(profile.effectivePeriodLength) days", note: profile.periodLength == nil ? "typical" : nil, last: true)
                    }

                    card("Today") {
                        row("Period", periodToday, muted: today?.flow == nil)
                        row("Mood", today?.mood.map { LevelScale.moodTitles[$0 - 1] } ?? "Not logged", muted: today?.mood == nil)
                        row("Energy", today?.energy.map { LevelScale.energyTitles[$0 - 1] } ?? "Not logged", muted: today?.energy == nil)
                        row("Feelings", feelingsToday.isEmpty ? "None logged" : feelingsToday.joined(separator: ", "), muted: feelingsToday.isEmpty)
                        row("Checked in", checkedInText, last: snacks.isEmpty)
                        if !snacks.isEmpty {
                            row("Snack list", snacks.joined(separator: ", "), last: true)
                        }
                    }

                    card("Your garden") {
                        row("Streak", streak == 1 ? "1 day" : "\(streak) days")
                        row("Bouquets", "\(collection.count) collected", last: true)
                    }

                    card("Your answers") {
                        editRow("Age", profile.ageRange?.title ?? "Not set", options: AgeRange.allCases.map { ($0.title, $0) }) {
                            profile.ageRange = $0
                        }
                        editRow("Cycle length", profile.cycleLength.map { "\($0) days" } ?? "Not sure",
                                options: [("Not sure", nil)] + (20...45).map { ("\($0) days", Optional($0)) }) {
                            profile.cycleLength = $0
                        }
                        editRow("Period length", profile.periodLength.map { "\($0) days" } ?? "Not sure",
                                options: [("Not sure", nil)] + (1...10).map { ("\($0) day\($0 == 1 ? "" : "s")", Optional($0)) }) {
                            answered(.periodLength)
                            profile.periodLength = $0
                        }
                        editRow("Birth control", profile.birthControl?.title ?? "Not answered", options: BirthControl.allCases.map { ($0.title, $0) }) {
                            answered(.birthControl)
                            profile.birthControl = $0
                        }
                        editRow("You use", profile.products?.map(\.title).joined(separator: ", ") ?? "Not answered",
                                options: PeriodProduct.allCases.map { ($0.title, $0) }) {
                            answered(.products)
                            profile.products = [$0]
                        }
                        editRow("Student", profile.isStudent.map { $0 ? "Yes" : "No" } ?? "Not answered", options: [("Yes", true), ("No", false)]) {
                            answered(.student)
                            profile.isStudent = $0
                        }
                        goalsRow
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.ink)
                    .frame(width: 36, height: 36)
                    .background(Self.cream, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 12)
            .accessibilityLabel("Back")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let signature {
                Image(uiImage: signature)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 72, alignment: .leading)
                    .accessibilityLabel("Your name")
            }
            Text("about you")
                .font(.custom("InterTight-SemiBold", size: 30))
                .tracking(-1.2)
                .foregroundStyle(Self.ink)
        }
    }

    // MARK: - Cards

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.custom("CormorantGaramond-Light", size: 24))
                .foregroundStyle(Self.ink)
                .padding(.bottom, 14)
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Self.cream)
                .overlay {
                    GrainOverlay()
                        .blendMode(.multiply)
                        .opacity(0.07)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
        .shadow(color: Color(hex: 0x4A3328).opacity(0.10), radius: 30, y: 16)
    }

    private func row(_ label: String, _ value: String, note: String? = nil, muted: Bool = false, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Self.rule).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label.uppercased())
                    .font(.custom("DMSans-Light", size: 9.5))
                    .tracking(0.95)
                    .foregroundStyle(Self.soft)
                    .frame(width: 104, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.custom("DMSans-Light", size: 15))
                        .foregroundStyle(muted ? Self.soft : Self.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note.uppercased())
                            .font(.custom("DMSans-Light", size: 8.5))
                            .tracking(0.85)
                            .foregroundStyle(Self.soft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            if last { Rectangle().fill(Self.rule).frame(height: 0.5) }
        }
    }

    // MARK: - Editing

    /// The row's value opens a menu of choices; picking one saves straight away.
    private func editRow<Value>(
        _ label: String,
        _ value: String,
        options: [(String, Value)],
        last: Bool = false,
        onPick: @escaping (Value) -> Void
    ) -> some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].0) {
                    onPick(options[i].1)
                    profile.save()
                }
            }
        } label: {
            row(label, value, note: "tap to change", muted: value.hasPrefix("Not"), last: last)
        }
        .buttonStyle(.plain)
    }

    private var goalsRow: some View {
        let goals = profile.goals ?? []
        return Menu {
            ForEach(HelpGoal.allCases) { goal in
                Button {
                    answered(.goals)
                    var picked = Set(goals)
                    if picked.contains(goal) { picked.remove(goal) } else { picked.insert(goal) }
                    profile.goals = HelpGoal.allCases.filter(picked.contains)
                    profile.save()
                } label: {
                    if goals.contains(goal) { Label(goal.title, systemImage: "checkmark") } else { Text(goal.title) }
                }
            }
        } label: {
            row("Help with", goals.isEmpty ? "Not answered" : goals.map(\.title).joined(separator: ", "),
                note: "tap to change", muted: goals.isEmpty, last: true)
        }
        .buttonStyle(.plain)
    }

    /// Answering here counts: the one-time card won't ask again.
    private func answered(_ question: OneTimeQuestion) {
        profile.oneTimeCards[question.id, default: OneTimeCardState()].answered = true
    }

    // MARK: - Derived

    private let snacks = InsightStore.snackList()

    private var periodToday: String {
        guard let flow = today?.flow else { return "Not logged" }
        return flow == .noFlow ? "No period" : "\(flow.title) flow"
    }

    private var streak: Int { BouquetCollection.streak(collectedDays: collection.map(\.day)) }

    private var feelingsToday: [String] {
        Symptom.catalog.filter { today?.said($0.id) == true }.map(\.label)
    }

    private var checkedInText: String {
        guard let today else { return "Not yet" }
        if today.nothingToday { return "Nothing today" }
        if today.completed { return "Done" }
        return today.answeredCards.isEmpty ? "Not yet" : "\(today.answeredCards.count) cards so far"
    }

    /// Where today falls and when the next period should begin, from the
    /// same engine the insights use.
    private var cycleNow: (day: Int, lastStart: Date, nextStart: Date)? {
        let engine = CycleEngine(logs: DayLogStore.allLogs(), profile: profile)
        guard let start = engine.cycleStart(for: .now),
              let day = engine.cycleDay(for: .now)
        else { return nil }
        let next = engine.nextStart(after: .now) ?? engine.day(engine.typicalCycleLength, from: start)
        return (day, start, next)
    }
}

#Preview {
    YouView()
}

import SwiftUI
import UIKit

/// Everything the app knows about her, on one page: her name, where she is
/// in her cycle, what she told onboarding, today's check-in and her streak.
/// Reached from "See your details" under the finished bouquet. A first
/// pass — the fuller profile is still to be designed.
struct YouView: View {
    @Environment(\.dismiss) private var dismiss

    private let profile = CycleProfile.load() ?? CycleProfile()
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
                            row("Today", "Day \(cycle.day) of \(profile.effectiveCycleLength)")
                            row("Next period", cycle.nextStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), note: "estimate")
                            row("Last started", cycle.lastStart.formatted(.dateTime.month(.abbreviated).day()))
                        } else {
                            row("Last started", "Not logged yet", muted: true)
                        }
                        row("Cycle length", "\(profile.effectiveCycleLength) days", note: profile.cycleLength == nil ? "typical" : nil)
                        row("Period length", "\(profile.effectivePeriodLength) days", note: profile.periodLength == nil ? "typical" : nil, last: true)
                    }

                    card("Today") {
                        row("Period", today?.flow.map { "\($0.title) flow" } ?? "Not logged", muted: today?.flow == nil)
                        row("Feelings", feelingsToday.isEmpty ? "None logged" : feelingsToday.joined(separator: ", "), muted: feelingsToday.isEmpty)
                        row("Checked in", checkedInText, last: true)
                    }

                    card("Your garden") {
                        row("Streak", streak == 1 ? "1 day" : "\(streak) days")
                        row("Bouquets", "\(collection.count) collected", last: true)
                    }

                    card("About you") {
                        row("Age", "\(profile.age)")
                        row("Birth control", profile.birthControl.title, last: true)
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

    // MARK: - Derived

    private var streak: Int { BouquetCollection.streak(collectedDays: collection.map(\.day)) }

    private var feelingsToday: [String] {
        (today?.symptoms ?? [])
            .filter { $0 != Symptom.periodID }
            .compactMap { id in Symptom.catalog.first { $0.id == id }?.label }
    }

    private var checkedInText: String {
        let answered = today?.answeredCount ?? 0
        let total = Symptom.catalog.count
        return answered >= total ? "All \(total) cards" : "\(answered) of \(total) cards"
    }

    /// Where today falls, counting whole cycles on from the last start she
    /// gave, and when the next one should begin.
    private var cycleNow: (day: Int, lastStart: Date, nextStart: Date)? {
        guard let start = profile.lastPeriodStart else { return nil }
        let calendar = Calendar.current
        let length = profile.effectiveCycleLength
        let first = calendar.startOfDay(for: start)
        let todayStart = calendar.startOfDay(for: .now)
        let elapsed = max(calendar.dateComponents([.day], from: first, to: todayStart).day ?? 0, 0)
        let cyclesDone = elapsed / length
        guard let lastStart = calendar.date(byAdding: .day, value: cyclesDone * length, to: first),
              let nextStart = calendar.date(byAdding: .day, value: length, to: lastStart)
        else { return nil }
        return (elapsed % length + 1, lastStart, nextStart)
    }
}

#Preview {
    YouView()
}

import SwiftUI
import UIKit

/// What goes on the doctor summary, worked out from her logs. Plain facts
/// in the words a doctor would use, plus the ranges they're read against.
struct DoctorSummaryContent: Equatable {
    struct CycleRow: Equatable {
        let start: Date
        let length: Int
        let periodDays: Int?
    }

    var about: [String] = []
    var cycles: [CycleRow] = []
    var currentCycle: String?
    var skippedGaps = 0
    var check: [String] = []
    var symptoms: [String] = []
    var patterns: [String] = []
    var helped: [String] = []
    var logging: String = ""

    static let windowDays = 90

    static func make(engine: CycleEngine, profile: CycleProfile, today: Date) -> DoctorSummaryContent {
        var content = DoctorSummaryContent()
        if let range = profile.ageRange { content.about.append("Age \(range.title)") }
        if let birthControl = profile.birthControl { content.about.append("Birth control: \(birthControl.title)") }

        let plausible = engine.plausibleCycles
        content.skippedGaps = engine.completedCycles.filter { $0.length >= 15 }.count - plausible.count
        content.cycles = plausible.suffix(6).map {
            CycleRow(start: $0.start, length: $0.length, periodDays: engine.loggedPeriodDays(from: $0.start))
        }
        if let start = engine.cycleStart(for: today), let day = engine.cycleDay(for: today) {
            content.currentCycle = "Current cycle: day \(day), started \(start.formatted(.dateTime.month(.abbreviated).day().year()))."
        }

        switch engine.cycleCheck() {
        case let .notEnoughData(have):
            content.check = ["Fewer than 3 complete cycles logged (\(have) so far)."]
        case let .inRange(shortest, longest):
            content.check = ["Cycle lengths \(shortest)–\(longest) days: within the usual range (\(engine.normalCycleRange.lowerBound)–\(engine.normalCycleRange.upperBound) days, varying by no more than \(engine.allowedVariation))."]
        case let .outsideRange(reasons):
            content.check = reasons
        }

        // The last 90 days, today included.
        let since = engine.day(-(windowDays - 1), from: today)
        let recent = engine.logs.filter { $0.date >= since }
        for symptom in Symptom.catalog {
            let days = recent.filter { $0.said(symptom.id) }.count
            guard days > 0 else { continue }
            let stats = engine.stats(for: symptom.id)
            var line = "\(symptom.label.prefix(1).uppercased() + symptom.label.dropFirst()): \(days) day\(days == 1 ? "" : "s")"
            if stats.cyclesWithSymptom >= 2, let offset = stats.typicalStartOffset, let length = stats.typicalLength {
                line += offset <= 7
                    ? ", usually from \(offset) day\(offset == 1 ? "" : "s") before the period, lasting about \(length)"
                    : ", usually from cycle day \(stats.typicalStartDay ?? 1), lasting about \(length)"
            }
            content.symptoms.append(line + ".")
        }

        if engine.usableCycles.count >= 2 {
            content.patterns.append(engine.hasMoodPattern
                ? "Mood and mood symptoms were at least 30% worse in the 7 days before the period than on cycle days 4–10, in each of the last 2 cycles."
                : "No consistent premenstrual mood change across the last 2 cycles.")
        }
        if let link = engine.stressLink() {
            content.patterns.append("Cycles with 3+ days logged as stressed averaged \(abs(link.difference)) days \(link.difference > 0 ? "longer" : "shorter") (\(link.stressedCycles) stressed vs \(link.calmCycles) other cycles).")
        }

        content.helped = engine.helperRanking.prefix(3).map { "\($0.helper.title): helped \($0.count) of \($0.outOf) times" }

        let logged = recent.filter(\.isLogged).count
        content.logging = "Logged \(logged) of the last \(windowDays) days in Clutch."
        return content
    }
}

/// Renders the summary as a one-page, US Letter PDF in the temporary folder,
/// ready for the share sheet. Nothing is uploaded.
@MainActor
enum DoctorSummary {
    static func makePDF(engine: CycleEngine, profile: CycleProfile, today: Date) -> URL? {
        let content = DoctorSummaryContent.make(engine: engine, profile: profile, today: today)
        let page = DoctorSummaryPage(content: content, made: today)
            .frame(width: 612, height: 792)
        let renderer = ImageRenderer(content: page)
        let url = FileManager.default.temporaryDirectory.appending(path: "Clutch cycle summary.pdf")
        var rendered = false
        renderer.render { _, draw in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            rendered = true
        }
        return rendered ? url : nil
    }
}

/// The printed page: simple headed sections on white, in the app's type.
private struct DoctorSummaryPage: View {
    let content: DoctorSummaryContent
    let made: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cycle summary")
                    .font(.custom("InterTight-SemiBold", size: 24))
                Text("Made with Clutch on \(made.formatted(date: .long, time: .omitted)). Self-tracked by the patient; not a diagnosis.")
                    .font(.custom("DMSans-Light", size: 10))
                if !content.about.isEmpty {
                    Text(content.about.joined(separator: "  \u{00B7}  ")).font(.custom("DMSans-Regular", size: 11))
                }
            }

            section("Cycles") {
                if content.cycles.isEmpty {
                    line("No complete cycles logged yet.")
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 3) {
                        GridRow {
                            Text("Started").bold()
                            Text("Cycle length").bold()
                            Text("Period length").bold()
                        }
                        ForEach(content.cycles, id: \.start) { row in
                            GridRow {
                                Text(row.start.formatted(.dateTime.month(.abbreviated).day().year()))
                                Text("\(row.length) days")
                                Text(row.periodDays.map { "\($0) days" } ?? "not logged")
                            }
                        }
                    }
                    .font(.custom("DMSans-Light", size: 11))
                }
                if let current = content.currentCycle { line(current) }
                if content.skippedGaps > 0 {
                    line("\(content.skippedGaps) long gap\(content.skippedGaps == 1 ? "" : "s") with little logging left out as likely unlogged periods.")
                }
            }

            section("Compared with usual ranges (FIGO 2018; ACOG for under 18)") {
                ForEach(content.check, id: \.self, content: line)
            }

            if !content.symptoms.isEmpty {
                section("Symptoms, last \(DoctorSummaryContent.windowDays) days") {
                    ForEach(content.symptoms, id: \.self, content: line)
                }
            }

            if !content.patterns.isEmpty {
                section("Patterns") {
                    ForEach(content.patterns, id: \.self, content: line)
                }
            }

            if !content.helped.isEmpty {
                section("What helped (her own next-day answers)") {
                    ForEach(content.helped, id: \.self, content: line)
                }
            }

            Spacer(minLength: 0)

            Text(content.logging).font(.custom("DMSans-Light", size: 10))
            Text("Ranges: Munro et al., FIGO systems for normal and abnormal uterine bleeding, Int J Gynecol Obstet 2018. ACOG Committee Opinion, Menstruation in Girls and Adolescents: Using the Menstrual Cycle as a Vital Sign, 2015. Premenstrual comparison modelled on DRSP scoring (Endicott et al. 2006).")
                .font(.custom("DMSans-Light", size: 8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.cardInk)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.custom("DMSans-Regular", size: 9.5))
                .tracking(0.9)
                .foregroundStyle(Color.cardSoft)
            content()
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.custom("DMSans-Light", size: 11))
            .fixedSize(horizontal: false, vertical: true)
    }
}

import Foundation

// Checks that turn her logs into things worth knowing, each built on a
// published standard or study (see learnLibrary.json for the sources):
// - cycle check: FIGO's normal limits for cycle frequency, regularity and
//   period length (Munro et al. 2018), with ACOG's wider range for teens;
// - stress link: her stressed cycles' length against her calm ones;
// - mood check: modelled on how the DRSP is scored for PMS/PMDD — the
//   week before a period against days 4–10, a 30% rise, two cycles running.
// None of these diagnose anything. The strongest they say is "might be
// worth mentioning to a doctor."
extension CycleEngine {
    // MARK: - Cycle check

    enum CycleCheck: Equatable {
        /// Needs three real cycles; `have` so far.
        case notEnoughData(have: Int)
        case inRange(shortest: Int, longest: Int)
        case outsideRange(reasons: [String])
    }

    /// Cycles a doctor would read as normal, for her age: FIGO's 24–38 days
    /// for adults, ACOG's 21–45 for 15–17.
    var normalCycleRange: ClosedRange<Int> {
        profile.ageRange == .fifteenToSeventeen ? 21...45 : 24...38
    }

    /// Shortest to longest cycle: FIGO allows 9 days' difference up to 25
    /// (and for teens), 7 days from 26.
    var allowedVariation: Int {
        switch profile.ageRange {
        case .fifteenToSeventeen, .eighteenToTwentyFour, nil: 9
        default: 7
        }
    }

    /// FIGO: a period lasting more than 8 days is prolonged.
    static let longestNormalPeriod = 8

    func cycleCheck() -> CycleCheck {
        let lengths = plausibleCycles.suffix(6).map(\.length)
        guard lengths.count >= 3, let shortest = lengths.min(), let longest = lengths.max() else {
            return .notEnoughData(have: plausibleCycles.count)
        }
        var reasons: [String] = []
        let range = normalCycleRange
        if shortest < range.lowerBound {
            reasons.append("One of your cycles was \(shortest) days. Cycles shorter than \(range.lowerBound) days are outside the usual range.")
        }
        if longest > range.upperBound {
            reasons.append("One of your cycles was \(longest) days. Cycles longer than \(range.upperBound) days are outside the usual range.")
        }
        if longest - shortest > allowedVariation {
            reasons.append("Your cycles have varied by \(longest - shortest) days. More than \(allowedVariation) days is more than usual.")
        }
        if let longPeriod = periodStarts.compactMap(loggedPeriodDays).max(), longPeriod > Self.longestNormalPeriod {
            reasons.append("One of your periods lasted \(longPeriod) days. Longer than \(Self.longestNormalPeriod) days is more than usual.")
        }
        return reasons.isEmpty ? .inRange(shortest: shortest, longest: longest) : .outsideRange(reasons: reasons)
    }

    /// A logged period's length: to the day she tapped Ended, or the last
    /// day of flow she logged in a row.
    func loggedPeriodDays(from start: Date) -> Int? {
        if let ended = (0..<15).first(where: { log(on: day($0, from: start))?.periodEnded == true }) {
            return ended + 1
        }
        var last: Int?
        for offset in 0..<15 {
            guard let log = log(on: day(offset, from: start)) else { break }
            if log.flow?.isBleeding == true || log.periodStarted { last = offset } else if last != nil { break }
        }
        // Only the first day logged is just "it started" (common in
        // imported Clue history), not a one-day period: unknown.
        guard let last, last > 0 else { return nil }
        return last + 1
    }

    // MARK: - Stress and cycle length

    struct StressLink: Equatable {
        /// Stressed cycles minus calm ones, in days (positive = longer).
        let difference: Int
        let stressedCycles: Int
        let calmCycles: Int
    }

    /// A cycle counts as stressed with 3 or more "stressed" days in it.
    /// Needs at least one of each and three cycles in all, and only speaks
    /// up for a difference of 2 days or more.
    func stressLink() -> StressLink? {
        let cycles = plausibleCycles
        guard cycles.count >= 3 else { return nil }
        var stressed: [Double] = [], calm: [Double] = []
        for cycle in cycles {
            let days = (0..<cycle.length).filter { said("stressed", on: day($0, from: cycle.start)) }.count
            if days >= 3 { stressed.append(Double(cycle.length)) } else { calm.append(Double(cycle.length)) }
        }
        guard let s = Self.mean(stressed), let c = Self.mean(calm) else { return nil }
        let difference = Int((s - c).rounded())
        guard abs(difference) >= 2 else { return nil }
        return StressLink(difference: difference, stressedCycles: stressed.count, calmCycles: calm.count)
    }

    // MARK: - Before-your-period mood check

    /// How rough a day was: mood turned into 0 (great) … 4 (awful), plus
    /// one for each of low, anxious or irritable.
    private func roughness(_ log: DayLog) -> Double? {
        guard let mood = log.mood else { return nil }
        let feelings = ["low", "anxious", "irritable"].filter(log.said).count
        return Double(5 - mood + feelings)
    }

    /// Whether a cycle's last 7 days ran at least 30% rougher (and a
    /// point or more) than its days 4–10, with 4+ logged days in each.
    func hasPremenstrualDip(_ cycle: Cycle) -> Bool? {
        let before = (1...7).compactMap { log(on: day(-$0, from: cycle.nextStart)).flatMap(roughness) }
        let after = (3...9).compactMap { log(on: day($0, from: cycle.start)).flatMap(roughness) }
        guard before.count >= 4, after.count >= 4, let pre = Self.mean(before), let post = Self.mean(after) else { return nil }
        return pre >= post * 1.3 && pre - post >= 1
    }

    /// The dip in both of her last two usable cycles.
    var hasMoodPattern: Bool {
        let checked = usableCycles.suffix(2).map(hasPremenstrualDip)
        return checked.count == 2 && checked.allSatisfy { $0 == true }
    }

    // MARK: - What Clutch knows about you

    struct Fact: Equatable {
        let text: String
        /// The learnLibrary topic behind it, for its "Why?" link.
        let topic: String?
    }

    /// Up to three real things about her, most useful first. Empty until
    /// the data backs something up.
    func personalFacts() -> [Fact] {
        var facts: [Fact] = []
        if hasMoodPattern {
            facts.append(Fact(
                text: "Your mood dips in the week before your period, two cycles in a row. Doctors look for this kind of pattern, so it might be worth mentioning at your next visit.",
                topic: "pmdd-hormone-sensitivity"
            ))
        }
        if let link = stressLink() {
            let longer = link.difference > 0
            facts.append(Fact(
                text: "Cycles with stressed weeks ran about \(abs(link.difference)) days \(longer ? "longer" : "shorter") for you.",
                topic: "stress-cycle-length"
            ))
        }
        let symptomFacts = Symptom.catalog.compactMap { symptom -> (Int, Fact)? in
            let stats = stats(for: symptom.id)
            guard stats.cyclesWithSymptom >= 2, let offset = stats.typicalStartOffset, let length = stats.typicalLength else { return nil }
            let entry = SymptomTips.shared[symptom.id]
            let subject = entry?.subject ?? "Your \(symptom.label)"
            let when = offset <= 7
                ? "about \(offset) day\(offset == 1 ? "" : "s") before your period"
                : "around day \(stats.typicalStartDay ?? 1) of your cycle"
            var text = "\(subject) usually start\(entry?.plural == false ? "s" : "") \(when) and last\(entry?.plural == false ? "s" : "") about \(length) day\(length == 1 ? "" : "s")."
            if let helper = stats.topHelper, stats.helperAnswers >= 2 {
                text += " \(helper.phrase.prefix(1).uppercased() + helper.phrase.dropFirst()) helped \(stats.topHelperCount) of \(stats.helperAnswers) times."
            }
            return (stats.cyclesWithSymptom, Fact(text: text, topic: symptom.id == "cramps" ? "cramps-relief" : nil))
        }
        facts += symptomFacts.sorted { $0.0 > $1.0 }.map(\.1)
        return Array(facts.prefix(3))
    }
}

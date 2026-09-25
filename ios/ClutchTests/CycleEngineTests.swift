import XCTest
@testable import Clutch

/// The engine and insight picker against three sample users:
/// A — regular cycles, low and anxious in the days before each period;
/// B — irregular cycles with the same pre-period lows;
/// C — low days that don't follow the cycle at all.
final class CycleEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let origin = Date(timeIntervalSince1970: 1_780_000_000)

    private func day(_ n: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: n, to: origin)!)
    }

    /// Where a generated day falls.
    private struct Place {
        let index: Int
        let cycleDay: Int
        /// Days before the next period (predicted for the current cycle).
        let offset: Int
        let isCurrentCycle: Bool
    }

    /// A user who logs every day: five days of medium flow at the start of
    /// each cycle, mood 4 and energy 3 unless `shape` says otherwise. The
    /// last day generated is "today".
    private func sampleUser(
        cycles: [Int],
        currentDay: Int,
        predictedLength: Int? = nil,
        shape: (Place, inout DayLog) -> Void = { _, _ in }
    ) -> (engine: CycleEngine, today: DayLog) {
        var logs: [DayLog] = []
        var index = 0
        let lengths = cycles + [currentDay]
        let predicted = predictedLength ?? cycles.last ?? 28
        for (cycleIndex, length) in lengths.enumerated() {
            let isCurrent = cycleIndex == cycles.count
            for d in 0..<length {
                var log = DayLog(date: day(index), seed: index)
                log.flow = d < 5 ? .medium : .noFlow
                log.mood = 4
                log.energy = 3
                log.answeredCards = ["flow", "mood", "energy"]
                log.completed = true
                let offset = (isCurrent ? predicted : length) - d
                shape(Place(index: index, cycleDay: d + 1, offset: offset, isCurrentCycle: isCurrent), &log)
                logs.append(log)
                index += 1
            }
        }
        let engine = CycleEngine(logs: logs, profile: CycleProfile(), calendar: calendar)
        return (engine, logs.last!)
    }

    // MARK: - A: regular, pre-period lows

    private func userA(currentDay: Int = 26) -> (engine: CycleEngine, today: DayLog) {
        sampleUser(cycles: [28, 28, 28, 28], currentDay: currentDay) { place, log in
            if (1...4).contains(place.offset) || place.cycleDay == 1 {
                log.symptoms = ["anxious", "low"]
                log.mood = 2
            }
            if place.cycleDay <= 2 {
                log.symptoms.append("cramps")
                log.helped = [Helper.heatingPad.rawValue]
            }
            if (8...14).contains(place.cycleDay) { log.energy = 5 }
        }
    }

    func testRegularUserCycleMaths() {
        let (engine, today) = userA()
        XCTAssertEqual(engine.periodStarts.count, 5)
        XCTAssertEqual(engine.cycleDay(for: today.date), 26)
        XCTAssertEqual(engine.backwardOffset(for: today.date), 3)
        XCTAssertEqual(engine.usableCycles.count, 4)
        XCTAssertEqual(engine.baselineMood(before: today.date), 4)
        XCTAssertTrue(engine.isHardDay(today))
    }

    func testRegularUserGetsAPersonalInsightForLowDays() {
        let (engine, today) = userA()
        let stats = engine.stats(for: "low")
        XCTAssertEqual(stats.typicalStartOffset, 4)
        XCTAssertEqual(stats.typicalLength, 5, "four days before, plus day 1")
        XCTAssertEqual(stats.cyclesWithSymptom, 4)
        // Today is the second low day of the usual five. The heating pad
        // logged on day 1 (a low day too) counts as low's top helper.
        XCTAssertEqual(
            engine.symptomInsight(for: "low", on: today.date, generalLastShown: nil),
            .personal(daysLeft: 3, helper: .heatingPad, helperCount: 5, helperAnswers: 5)
        )
    }

    func testRegularUsersCrampsKnowWhatHelped() {
        let stats = userA().engine.stats(for: "cramps")
        XCTAssertEqual(stats.topHelper, .heatingPad)
        XCTAssertEqual(stats.topHelperCount, stats.helperAnswers)
    }

    func testRegularUserIsInHerKnownStretch() {
        let (engine, today) = userA()
        XCTAssertEqual(engine.usualHardPositions, [-4, -3, -2, -1, 1])
        let line = engine.todayLine(for: today)
        XCTAssertEqual(line, .knownStretch(feelings: ["anxious", "feeling low"], cycleDay: 26, beforePeriod: true, easesBy: 2, inDays: 4))
        XCTAssertEqual(
            InsightCopy.text(for: line),
            "Anxious, feeling low, and day 26 is your usual pre-period stretch. For you, it usually eases by day 2 of your period."
        )
        XCTAssertTrue(line.asksForMatch)
    }

    func testRegularUserMidCycleIsAGoodWindow() {
        let (engine, today) = userA(currentDay: 11)
        XCTAssertEqual(engine.todayLine(for: today), .goodWindow)
    }

    // MARK: - B: irregular, pre-period lows

    private func userB() -> (engine: CycleEngine, today: DayLog) {
        sampleUser(cycles: [24, 35, 29, 40], currentDay: 30, predictedLength: 32) { place, log in
            if (1...3).contains(place.offset) {
                log.symptoms = ["low"]
                log.mood = 2
            }
        }
    }

    func testIrregularUserLinesUpByBackwardOffset() {
        let (engine, today) = userB()
        XCTAssertEqual(engine.typicalCycleLength, 32, "median of 24, 29, 35, 40")
        XCTAssertEqual(engine.backwardOffset(for: today.date), 3)
        let stats = engine.stats(for: "low")
        // Same place before every period, even though the cycle day swings
        // from 22 to 38.
        XCTAssertEqual(stats.typicalStartOffset, 3)
        XCTAssertEqual(stats.typicalLength, 3)
        XCTAssertEqual(
            engine.symptomInsight(for: "low", on: today.date, generalLastShown: nil),
            .personal(daysLeft: 2, helper: nil, helperCount: 0, helperAnswers: 0)
        )
    }

    func testIrregularUserStillGetsHerKnownStretch() {
        let (engine, today) = userB()
        guard case let .knownStretch(feelings, cycleDay, beforePeriod, easesBy, _) = engine.todayLine(for: today) else {
            return XCTFail("expected the known stretch")
        }
        XCTAssertEqual(feelings, ["feeling low"])
        XCTAssertEqual(cycleDay, 30)
        XCTAssertTrue(beforePeriod)
        XCTAssertEqual(easesBy, 1)
    }

    // MARK: - C: lows that don't follow the cycle

    private func userC() -> (engine: CycleEngine, today: DayLog) {
        let lowDays: Set<Int> = [7, 8, 44, 67, 68, 104]
        return sampleUser(cycles: [28, 28, 28, 28], currentDay: 26) { place, log in
            if lowDays.contains(place.index) || (place.isCurrentCycle && place.cycleDay == 26) {
                log.symptoms = ["low"]
            }
        }
    }

    func testLowsThatDontFollowTheCycleAreNotCalledAPattern() {
        let (engine, today) = userC()
        XCTAssertEqual(engine.usableCycles.count, 4)
        XCTAssertTrue(engine.usualHardPositions.isEmpty)
        XCTAssertFalse(engine.isHardDay(today), "one hard symptom and a usual mood")
        XCTAssertEqual(engine.todayLine(for: today), .logged)
    }

    func testLowsThatDontFollowTheCycleOnlyGetDurationNotTiming() {
        let (engine, today) = userC()
        let stats = engine.stats(for: "low")
        XCTAssertEqual(stats.cyclesWithSymptom, 4)
        guard case let .personal(daysLeft, _, _, _) = engine.symptomInsight(for: "low", on: today.date, generalLastShown: nil) else {
            return XCTFail("expected a personal insight")
        }
        XCTAssertEqual(daysLeft, 1, "her low stretches usually run two days")
    }

    // MARK: - Tiers

    private func newUser(days: Int, shape: (Int, inout DayLog) -> Void = { _, _ in }) -> (engine: CycleEngine, today: DayLog) {
        let logs = (0..<days).map { i -> DayLog in
            var log = DayLog(date: day(i), seed: i)
            log.flow = .noFlow
            log.mood = 3
            shape(i, &log)
            return log
        }
        return (CycleEngine(logs: logs, profile: CycleProfile(), calendar: calendar), logs.last!)
    }

    func testGeneralTipShowsAtMostOnceAWeek() {
        let (engine, today) = newUser(days: 3) { i, log in if i == 2 { log.symptoms = ["cramps"] } }
        XCTAssertEqual(engine.symptomInsight(for: "cramps", on: today.date, generalLastShown: nil), .general)
        XCTAssertNil(engine.symptomInsight(for: "cramps", on: today.date, generalLastShown: day(-1)))
        XCTAssertEqual(engine.symptomInsight(for: "cramps", on: today.date, generalLastShown: day(-6)), .general)
    }

    func testRecentTierCountsThisWeek() {
        let (engine, today) = newUser(days: 8) { i, log in
            if [3, 5, 7].contains(i) { log.symptoms = ["cramps"] }
        }
        XCTAssertEqual(
            engine.symptomInsight(for: "cramps", on: today.date, generalLastShown: nil),
            .recent(ordinal: 3, lastCycleStartDay: nil)
        )
        XCTAssertEqual(
            InsightCopy.text(for: .recent(ordinal: 3, lastCycleStartDay: 25), symptomID: "cramps"),
            "This is your 3rd cramp day this week. Last cycle they started on day 25."
        )
    }

    func testFlagAfterThreeHeavierCycles() {
        let crampDays = [2, 2, 2, 5, 5, 5]
        let (engine, today) = sampleUser(cycles: [28, 28, 28, 28, 28, 28], currentDay: 1) { place, log in
            guard !place.isCurrentCycle else { return log.symptoms = ["cramps"] }
            let cycle = place.index / 28
            if place.cycleDay <= crampDays[cycle] { log.symptoms = ["cramps"] }
        }
        XCTAssertEqual(engine.stats(for: "cramps").daysPerCycle, crampDays)
        XCTAssertEqual(engine.symptomInsight(for: "cramps", on: today.date, generalLastShown: nil), .flag(cycles: 3))
        let text = InsightCopy.text(for: .flag(cycles: 3), symptomID: "cramps")
        XCTAssertTrue(text.hasSuffix("That might be worth mentioning to a doctor."))
    }

    func testUsableCycleNeedsSixtyPercentLogged() {
        // Two cycles; in the first only every other day is logged.
        var logs: [DayLog] = []
        for i in 0..<57 {
            let cycleDay = i % 28
            guard i >= 28 || cycleDay.isMultiple(of: 2) || cycleDay < 5 || i == 56 else { continue }
            var log = DayLog(date: day(i), seed: i)
            log.flow = cycleDay < 5 && i < 56 ? .medium : (i == 56 ? .medium : .noFlow)
            logs.append(log)
        }
        let engine = CycleEngine(logs: logs, profile: CycleProfile(), calendar: calendar)
        XCTAssertEqual(engine.completedCycles.count, 2)
        XCTAssertEqual(engine.usableCycles.map(\.start), [day(28)])
    }

    func testHardDayByMoodOrBySymptoms() {
        let (engine, _) = newUser(days: 10) { i, log in if i == 9 { log.mood = 2 } }
        XCTAssertTrue(engine.isHardDay(engine.log(on: day(9))!), "1 below a baseline of 3")
        var twoSymptoms = DayLog(date: day(10), seed: 0)
        twoSymptoms.symptoms = ["irritable", "cramps"]
        XCTAssertTrue(engine.isHardDay(twoSymptoms))
        var oneSymptom = DayLog(date: day(10), seed: 0)
        oneSymptom.symptoms = ["cramps", "bloating"]
        XCTAssertFalse(engine.isHardDay(oneSymptom), "bloating isn't one of the four")
    }

    func testEarlyDataAndNothingTodayLines() {
        let (engine, today) = newUser(days: 5)
        XCTAssertEqual(engine.todayLine(for: today), .earlyData)
        var nothing = today
        nothing.nothingToday = true
        XCTAssertEqual(engine.todayLine(for: nothing), .nothingToday)
        XCTAssertEqual(InsightCopy.text(for: .nothingToday), "Seed planted. Your streak is safe.")
    }

    // MARK: - Deck planning

    private func planner(profile: CycleProfile, logs: [DayLog] = []) -> DeckPlanner {
        DeckPlanner(engine: CycleEngine(logs: logs, profile: profile, calendar: calendar))
    }

    private var onboarded: CycleProfile {
        var profile = CycleProfile()
        profile.onboardingComplete = true
        profile.onboardedOn = day(0)
        return profile
    }

    func testOneTimeCardsStartOnDayTwoOneAtATime() {
        XCTAssertNil(planner(profile: onboarded).dueOneTimeQuestion(on: day(0)))
        XCTAssertEqual(planner(profile: onboarded).dueOneTimeQuestion(on: day(1)), .birthControl)
        var profile = onboarded
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = .answered
        XCTAssertNil(planner(profile: profile).dueOneTimeQuestion(on: day(1)), "period length waits for day 3")
        XCTAssertEqual(planner(profile: profile).dueOneTimeQuestion(on: day(2)), .periodLength)
    }

    func testSkippedCardComesBackOnceAWeekLater() {
        var profile = onboarded
        profile.oneTimeCards = Dictionary(uniqueKeysWithValues: OneTimeQuestion.allCases.dropFirst().map { ($0.id, .answered) })
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = OneTimeCardState(skips: [day(1)])
        XCTAssertNil(planner(profile: profile).dueOneTimeQuestion(on: day(7)))
        XCTAssertEqual(planner(profile: profile).dueOneTimeQuestion(on: day(8)), .birthControl)
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = OneTimeCardState(skips: [day(1), day(8)])
        XCTAssertNil(planner(profile: profile).dueOneTimeQuestion(on: day(30)))
    }

    func testFollowUpAfterCrampsAndItWaitsForAOneTimeCard() {
        var yesterday = DayLog(date: day(1), seed: 1)
        yesterday.symptoms = ["cramps"]
        yesterday.leadCard = ""

        // Nothing one-time due (all answered): the follow-up leads.
        var answeredAll = onboarded
        answeredAll.oneTimeCards = Dictionary(uniqueKeysWithValues: OneTimeQuestion.allCases.map { ($0.id, .answered) })
        let lead = planner(profile: answeredAll, logs: [yesterday]).chooseLead(on: day(2))
        XCTAssertEqual(lead, .followUp(day: day(1), symptomIDs: ["cramps"], daysAgo: 1))
        XCTAssertEqual(InsightCopy.followUpQuestion(symptomIDs: ["cramps"], daysAgo: 1, day: day(1)), "Yesterday you had cramps. What helped?")

        // A one-time card is due: it goes first…
        XCTAssertEqual(planner(profile: onboarded, logs: [yesterday]).chooseLead(on: day(2)), .oneTime(.birthControl))

        // …and the follow-up gets the next day.
        var today = DayLog(date: day(2), seed: 2)
        today.leadCard = OneTimeQuestion.birthControl.id
        var profile = onboarded
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = .answered
        XCTAssertEqual(
            planner(profile: profile, logs: [yesterday, today]).chooseLead(on: day(3)),
            .followUp(day: day(1), symptomIDs: ["cramps"], daysAgo: 2)
        )
    }

    func testAnsweredFollowUpIsntAskedAgain() {
        var yesterday = DayLog(date: day(1), seed: 1)
        yesterday.symptoms = ["headache"]
        yesterday.helpedNextDay = [Helper.rest.rawValue]
        XCTAssertNil(planner(profile: CycleProfile(), logs: [yesterday]).followUpCard(on: day(2), daysAgo: 1))
    }

    func testMostCommonSymptomsComeFirstAfterThreeWeeks() {
        let logs = (0..<22).map { i -> DayLog in
            var log = DayLog(date: day(i), seed: i)
            log.symptoms = i.isMultiple(of: 2) ? ["cravings", "headache"] : ["cravings"]
            return log
        }
        XCTAssertEqual(planner(profile: CycleProfile(), logs: Array(logs.prefix(10))).symptomOrder(on: day(10)), Symptom.catalog)
        let order = planner(profile: CycleProfile(), logs: logs).symptomOrder(on: day(22)).map(\.id)
        XCTAssertEqual(Array(order.prefix(3)), ["cravings", "headache", "anxious"])
    }

    // MARK: - Tips

    func testEverySymptomHasATipAndAnAction() {
        let tips = SymptomTips.shared
        for symptom in Symptom.catalog {
            XCTAssertFalse(tips[symptom.id]?.tip.isEmpty ?? true, symptom.id)
            XCTAssertNotNil(tips[symptom.id]?.action, symptom.id)
        }
        XCTAssertTrue(tips.laterActions(for: "cramps", profile: CycleProfile()).isEmpty, "later actions are off for Beta 1")
    }

    func testNoTipClaimsADiagnosis() {
        for entry in SymptomTips.shared.symptoms.values {
            XCTAssertFalse(entry.tip.lowercased().contains("you have"), entry.tip)
        }
    }
}

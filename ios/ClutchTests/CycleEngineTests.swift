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

    // MARK: - Period now and the window

    func testOnHerPeriodWithinHerUsualLengthUntilSheTapsEnded() {
        // The bug: started Sep 24, typical 5 days, day 2 showed "No period".
        var profile = CycleProfile()
        profile.lastPeriodStart = day(0)
        var yesterday = DayLog(date: day(0), seed: 0)
        yesterday.mood = 3
        let engine = CycleEngine(logs: [yesterday], profile: profile, calendar: calendar)
        XCTAssertTrue(engine.isOnPeriod(day(1)))
        XCTAssertEqual(engine.periodDay(for: day(1)), 2)
        XCTAssertFalse(engine.isOnPeriod(day(5)), "past her usual 5 days")

        var ended = DayLog(date: day(2), seed: 2)
        ended.periodEnded = true
        let afterEnd = CycleEngine(logs: [yesterday, ended], profile: profile, calendar: calendar)
        XCTAssertTrue(afterEnd.isOnPeriod(day(1)))
        XCTAssertFalse(afterEnd.isOnPeriod(day(2)))
        XCTAssertFalse(afterEnd.isOnPeriod(day(3)))
    }

    func testPeriodStartedButtonStartsANewCycle() {
        var started = DayLog(date: day(30), seed: 1)
        started.periodStarted = true
        var profile = CycleProfile()
        profile.lastPeriodStart = day(0)
        let engine = CycleEngine(logs: [started], profile: profile, calendar: calendar)
        XCTAssertEqual(engine.periodStarts, [day(0), day(30)])
        XCTAssertEqual(engine.cycleDay(for: day(31)), 2)
    }

    func testPredictionWindowWidensWithVariability() {
        let regular = userA().engine
        let window = regular.nextPeriodWindow(after: day(4 * 28 + 25))!
        XCTAssertEqual(window.likely, day(5 * 28), "last start + 28")
        XCTAssertEqual(window.earliest, day(5 * 28 - 1), "at least 1 day either side")
        XCTAssertEqual(window.latest, day(5 * 28 + 1))

        let irregular = userB().engine
        let wide = irregular.nextPeriodWindow(after: day(24 + 35 + 29 + 40 + 29))!
        XCTAssertEqual(irregular.days(from: wide.earliest, to: wide.latest), 14, "cycles 24–40 spread it the full 7 each side")
    }

    func testPeriodButtonOffersNearTheWindowOnly() {
        let engine = userA().engine
        XCTAssertTrue(engine.isNearPredictedPeriod(day(4 * 28 + 25)), "3 days before the window opens")
        XCTAssertFalse(engine.isNearPredictedPeriod(day(4 * 28 + 12)))
    }

    // MARK: - Phases

    func testTypicalPhasesCoverTheCycle() {
        let spans = CycleEngine.typicalPhases(cycleLength: 28, periodLength: 5)
        XCTAssertEqual(spans.map(\.phase), [.period, .rising, .strongest, .windingDown])
        XCTAssertEqual(spans.first?.firstDay, 1)
        XCTAssertEqual(spans.last?.lastDay, 28)
        XCTAssertEqual(spans[2].firstDay...spans[2].lastDay, 12...15, "around day 14")
        for (a, b) in zip(spans, spans.dropFirst()) { XCTAssertEqual(a.lastDay + 1, b.firstDay) }
    }

    // MARK: - What helps her, and which sections are ready

    func testHelperRankingFromFollowUps() {
        let (engine, _) = newUser(days: 6) { i, log in
            switch i {
            case 0, 1, 2: log.helpedNextDay = [Helper.walk.rawValue]
            case 3: log.helpedNextDay = [Helper.nap.rawValue, Helper.walk.rawValue]
            default: break
            }
        }
        XCTAssertEqual(engine.followUpAnswerCount, 4)
        XCTAssertEqual(engine.helperRanking.first, .init(helper: .walk, count: 4, outOf: 4))
        XCTAssertEqual(engine.helperRanking.last, .init(helper: .nap, count: 1, outOf: 4))
    }

    func testDetailsPlanForTheThreeSampleUsers() {
        let (a, aToday) = userA()
        let planA = a.detailsPlan(for: aToday)
        XCTAssertFalse(planA.isEarlyDays)
        XCTAssertEqual(planA.symptoms.map { $0.id }, ["anxious", "low"])
        XCTAssertEqual(planA.symptoms.map { $0.insight.tier }, [3, 3])

        let (b, bToday) = userB()
        XCTAssertEqual(b.detailsPlan(for: bToday).header.asksForMatch, true, "known stretch")

        let (c, cToday) = userC()
        let planC = c.detailsPlan(for: cToday)
        XCTAssertEqual(planC.header, .logged)
        XCTAssertFalse(planC.showsSupport)

        let (fresh, freshToday) = newUser(days: 2) { _, log in log.symptoms = ["cravings"] }
        let early = fresh.detailsPlan(for: freshToday)
        XCTAssertTrue(early.isEarlyDays)
        XCTAssertEqual(early.symptoms.map { $0.insight }, [.general], "tier 1 until there's data")
    }

    func testSupportLineAfterFiveLowDaysInARow() {
        let (engine, today) = newUser(days: 5) { _, log in log.symptoms = ["low"] }
        XCTAssertTrue(engine.detailsPlan(for: today).showsSupport)
    }

    // MARK: - Deck: four cards at most

    private func planner(profile: CycleProfile, logs: [DayLog] = []) -> DeckPlanner {
        DeckPlanner(engine: CycleEngine(logs: logs, profile: profile, calendar: calendar))
    }

    func testEverydayDeckIsThreeCards() {
        XCTAssertEqual(planner(profile: CycleProfile()).deck(on: day(0)), [.mood, .energy, .chips])
    }

    func testFlowIsCardFourOnlyDuringHerPeriod() {
        var profile = CycleProfile()
        profile.lastPeriodStart = day(0)
        XCTAssertEqual(planner(profile: profile).deck(on: day(1)), [.mood, .energy, .chips, .flow])
        XCTAssertEqual(planner(profile: profile).deck(on: day(8)).count, 3)
    }

    func testFollowUpIsCardFourAfterARoughDayUnlessFlowIs() {
        var yesterday = DayLog(date: day(9), seed: 1)
        yesterday.symptoms = ["cramps"]
        XCTAssertEqual(planner(profile: CycleProfile(), logs: [yesterday]).deck(on: day(10)).last, .followUp(day: day(9)))

        var onPeriod = CycleProfile()
        onPeriod.lastPeriodStart = day(9)
        let deck = planner(profile: onPeriod, logs: [yesterday]).deck(on: day(10))
        XCTAssertEqual(deck.last, .flow, "flow wins")
        XCTAssertLessThanOrEqual(deck.count, DeckCard.maxCards)

        yesterday.helpedNextDay = [Helper.rest.rawValue]
        XCTAssertEqual(planner(profile: CycleProfile(), logs: [yesterday]).deck(on: day(10)).count, 3, "already answered")
    }

    func testMostCommonChipsComeFirstAfterThreeWeeks() {
        let logs = (0..<22).map { i -> DayLog in
            var log = DayLog(date: day(i), seed: i)
            log.symptoms = i.isMultiple(of: 2) ? ["cravings", "headache"] : ["cravings"]
            return log
        }
        XCTAssertEqual(planner(profile: CycleProfile(), logs: Array(logs.prefix(10))).symptomOrder(on: day(10)), Symptom.catalog)
        let order = planner(profile: CycleProfile(), logs: logs).symptomOrder(on: day(22)).map(\.id)
        XCTAssertEqual(Array(order.prefix(3)), ["cravings", "headache", "anxious"])
    }

    // MARK: - Help Clutch know you

    func testQuestionsComeOneADayInOrder() {
        var profile = CycleProfile()
        XCTAssertEqual(planner(profile: profile).dueQuestion(on: day(0)), .birthControl)
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = OneTimeCardState(answered: true, answeredOn: day(0))
        XCTAssertNil(planner(profile: profile).dueQuestion(on: day(0)), "one a day")
        XCTAssertEqual(planner(profile: profile).dueQuestion(on: day(1)), .periodLength)
    }

    func testSkippedQuestionComesBackOnceAWeekLater() {
        var profile = CycleProfile()
        for question in DeckPlanner.questionOrder.dropFirst() { profile.oneTimeCards[question.id] = .answered }
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = OneTimeCardState(skips: [day(1)])
        XCTAssertNil(planner(profile: profile).dueQuestion(on: day(7)))
        XCTAssertEqual(planner(profile: profile).dueQuestion(on: day(8)), .birthControl)
        profile.oneTimeCards[OneTimeQuestion.birthControl.id] = OneTimeCardState(skips: [day(1), day(8)])
        XCTAssertNil(planner(profile: profile).dueQuestion(on: day(30)))
    }

    // MARK: - Learn library

    func testWhyTopicsOnlyShowWhenTheyConnect() {
        let library = LearnLibrary.shared
        XCTAssertEqual(library.topic(for: .init(symptoms: ["cravings"]))?.id, "cravings-period")
        XCTAssertEqual(library.topic(for: .init(symptoms: ["low"], phase: .windingDown))?.id, "pmdd-hormone-sensitivity")
        XCTAssertNil(library.topic(for: .init(symptoms: ["low"], phase: .rising)), "no random trivia")
        XCTAssertNil(library.topic(for: .init()))
        XCTAssertEqual(library.topic(for: .init(phase: .period, insights: ["lowEnergyOnPeriod", "cyclePhases"]))?.id, "energy-dip-period")
    }

    func testSourcesAreFromTrustedPlacesAndMarkedForReview() {
        let trusted = ["acog.org", "womenshealth.gov", "iapmd.org", "pubmed.ncbi.nlm.nih.gov", "pmc.ncbi.nlm.nih.gov",
                       "obgyn.onlinelibrary.wiley.com", "nature.com", "academic.oup.com"]
        for topic in LearnLibrary.shared.topics {
            XCTAssertTrue(topic.needsReview, topic.id)
            for source in topic.sources {
                XCTAssertTrue(trusted.contains { source.url.host()?.hasSuffix($0) == true }, source.url.absoluteString)
            }
        }
        XCTAssertFalse(LearnLibrary.shared.topics.first { $0.id == "cramps-relief" }!.sources.isEmpty)
        XCTAssertEqual(LearnLibrary.shared.topics.count, 12)
    }

    // MARK: - Missed logs, cycle check, stress, mood

    func testAMissedPeriodLogDoesntSkewThePrediction() {
        // Four 28-day cycles, then 56 days with one log in the middle: a
        // period she didn't log, not a real 56-day cycle.
        var logs: [DayLog] = []
        for start in [0, 28, 56, 84, 140] {
            for d in 0..<5 {
                var log = DayLog(date: day(start + d), seed: start + d)
                log.flow = .medium
                logs.append(log)
            }
        }
        for i in 5..<112 where !(0..<5).contains(i % 28) && (i < 84 || i == 110) {
            var log = DayLog(date: day(i), seed: i)
            log.flow = .noFlow
            logs.append(log)
        }
        let engine = CycleEngine(logs: logs, profile: CycleProfile(), calendar: calendar)
        XCTAssertEqual(engine.completedCycles.map(\.length), [28, 28, 28, 56])
        XCTAssertEqual(engine.plausibleCycles.map(\.length), [28, 28, 28])
        XCTAssertEqual(engine.typicalCycleLength, 28)
    }

    func testALongCycleSheLoggedThroughIsKept() {
        let (engine, _) = sampleUser(cycles: [28, 28, 28, 52], currentDay: 3)
        XCTAssertEqual(engine.plausibleCycles.map(\.length), [28, 28, 28, 52])
        guard case let .outsideRange(reasons) = engine.cycleCheck() else { return XCTFail("52 days is outside the range") }
        XCTAssertTrue(reasons.contains { $0.contains("52 days") })
    }

    func testCycleCheckAgainstTheUsualRanges() {
        XCTAssertEqual(userA().engine.cycleCheck(), .inRange(shortest: 28, longest: 28))
        XCTAssertEqual(newUser(days: 5).engine.cycleCheck(), .notEnoughData(have: 0))

        guard case let .outsideRange(reasons) = userB().engine.cycleCheck() else { return XCTFail("24–40 days varies too much") }
        XCTAssertEqual(reasons.count, 2, "40 days is too long, and 16 days' variation is too much")
    }

    func testTeensGetTheWiderAdolescentRange() {
        var teen = CycleProfile()
        teen.ageRange = .fifteenToSeventeen
        XCTAssertEqual(CycleEngine(logs: [], profile: teen, calendar: calendar).normalCycleRange, 21...45)
        XCTAssertEqual(CycleEngine(logs: [], profile: CycleProfile(), calendar: calendar).normalCycleRange, 24...38)
    }

    func testLoggedPeriodLength() {
        let engine = userA().engine
        XCTAssertEqual(engine.loggedPeriodDays(from: day(0)), 5)
        XCTAssertEqual(engine.usualPeriodLength, 5)
    }

    func testStressedCyclesRanLonger() {
        // Cycles 2 and 4 had a stressed week and ran 34 days, the rest 28.
        let lengths = [28, 34, 28, 34]
        let starts = lengths.reduce(into: [0]) { $0.append($0.last! + $1) }
        let (engine, _) = sampleUser(cycles: lengths, currentDay: 3) { place, log in
            guard let cycle = starts.lastIndex(where: { $0 <= place.index }), cycle < lengths.count else { return }
            if lengths[cycle] == 34 && (10..<15).contains(place.cycleDay) { log.symptoms = ["stressed"] }
        }
        XCTAssertEqual(engine.stressLink(), .init(difference: 6, stressedCycles: 2, calmCycles: 2))
        XCTAssertNil(userA().engine.stressLink(), "no stressed days logged")
    }

    func testMoodCheckFindsTheRegularUsersPremenstrualDip() {
        XCTAssertTrue(userA().engine.hasMoodPattern)
        XCTAssertFalse(userC().engine.hasMoodPattern, "her lows don't follow the cycle")
    }

    func testWhatClutchKnowsAboutHer() {
        let facts = userA().engine.personalFacts()
        XCTAssertEqual(facts.count, 3)
        XCTAssertEqual(facts.first?.topic, "pmdd-hormone-sensitivity")
        XCTAssertTrue(facts.first!.text.hasSuffix("it might be worth mentioning at your next visit."))
        XCTAssertTrue(newUser(days: 5).engine.personalFacts().isEmpty)
        for fact in facts { XCTAssertFalse(fact.text.lowercased().contains("you have "), fact.text) }
    }

    func testDoctorSummary() {
        let (engine, today) = userA()
        var profile = CycleProfile()
        profile.ageRange = .eighteenToTwentyFour
        let summary = DoctorSummaryContent.make(engine: engine, profile: profile, today: today.date)
        XCTAssertEqual(summary.about, ["Age 18 – 24"])
        XCTAssertEqual(summary.cycles.count, 4)
        XCTAssertEqual(summary.cycles.first?.periodDays, 5)
        XCTAssertEqual(summary.skippedGaps, 0)
        XCTAssertTrue(summary.check.first!.contains("within the usual range"))
        XCTAssertTrue(summary.symptoms.contains { $0.hasPrefix("Cramps:") })
        XCTAssertTrue(summary.patterns.first!.contains("at least 30% worse"))
        XCTAssertEqual(summary.logging, "Logged 90 of the last 90 days in Clutch.")
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

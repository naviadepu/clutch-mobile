import Foundation

/// The cycle maths behind the insights: period starts, cycle day, backward
/// offset, usable cycles, mood baseline, hard days, per-symptom stats, and
/// the pickers that choose what to say after a swipe and after the bloom.
///
/// Everything is derived from the logs and profile it's given, every time —
/// nothing here (cycle day included) is ever stored. Plain Swift, no UI.
struct CycleEngine {
    /// A cycle is usable when at least this share of its days are logged.
    static let usableCoverage = 0.6
    /// Baseline mood is the median over this many most recent mood logs…
    static let baselineWindow = 60
    /// …once there are at least this many.
    static let minimumBaselineDays = 5
    /// "Around the period" stretches look at the week either side of it.
    static let stretchReach = 7

    let profile: CycleProfile
    let calendar: Calendar
    /// Oldest first, one per day.
    let logs: [DayLog]
    /// First day of every known period, oldest first.
    let periodStarts: [Date]

    private let byDay: [Date: DayLog]

    init(logs: [DayLog], profile: CycleProfile, calendar: Calendar = .current) {
        self.profile = profile
        self.calendar = calendar
        var byDay: [Date: DayLog] = [:]
        for log in logs { byDay[calendar.startOfDay(for: log.date)] = log }
        self.byDay = byDay
        self.logs = byDay.values.sorted { $0.date < $1.date }
        periodStarts = Self.findPeriodStarts(in: self.logs, profile: profile, calendar: calendar)
    }

    // MARK: - Days

    func log(on day: Date) -> DayLog? { byDay[calendar.startOfDay(for: day)] }

    func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    func day(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    // MARK: - Periods and cycles

    /// A bleeding day starts a new period unless it follows another
    /// bleeding day, or comes within a period's length (plus two days of
    /// slack) of the last start. The start she gave in onboarding counts
    /// too, unless a logged start already covers it.
    private static func findPeriodStarts(in logs: [DayLog], profile: CycleProfile, calendar: Calendar) -> [Date] {
        func gap(_ a: Date, _ b: Date) -> Int { calendar.dateComponents([.day], from: a, to: b).day ?? 0 }
        let slack = profile.effectivePeriodLength + 2
        var starts: [Date] = []
        var previousBleed: Date?
        for log in logs where log.flow?.isBleeding == true {
            let day = calendar.startOfDay(for: log.date)
            let continuesPrevious = previousBleed.map { gap($0, day) <= 1 } ?? false
            let withinLastPeriod = starts.last.map { gap($0, day) < slack } ?? false
            if !continuesPrevious && !withinLastPeriod { starts.append(day) }
            previousBleed = day
        }
        if let given = profile.lastPeriodStart.map(calendar.startOfDay) {
            if !starts.contains(where: { abs(gap($0, given)) < slack }) {
                starts.append(given)
                starts.sort()
            }
        }
        return starts
    }

    struct Cycle: Equatable {
        let start: Date
        /// The first day of the next period, which ends this cycle.
        let nextStart: Date
        let length: Int
    }

    /// Every cycle with a known end, oldest first.
    var completedCycles: [Cycle] {
        zip(periodStarts, periodStarts.dropFirst()).map { start, next in
            Cycle(start: start, nextStart: next, length: days(from: start, to: next))
        }
    }

    func isUsable(_ cycle: Cycle) -> Bool {
        guard cycle.length > 0 else { return false }
        let logged = (0..<cycle.length).filter { log(on: day($0, from: cycle.start))?.isLogged == true }.count
        return Double(logged) / Double(cycle.length) >= Self.usableCoverage
    }

    var usableCycles: [Cycle] { completedCycles.filter(isUsable) }

    /// Her own median once two plausible cycles are known, otherwise what
    /// she told onboarding, otherwise the one cycle seen, otherwise 28.
    var typicalCycleLength: Int {
        let lengths = completedCycles.map(\.length).filter { (15...60).contains($0) }
        if lengths.count >= 2, let median = Self.median(lengths.map(Double.init)) { return Int(median.rounded()) }
        return profile.cycleLength ?? lengths.first ?? CycleProfile.typicalCycleLength
    }

    func cycleStart(for date: Date) -> Date? {
        let day = calendar.startOfDay(for: date)
        return periodStarts.last { $0 <= day }
    }

    /// Day 1 is the day the period started.
    func cycleDay(for date: Date) -> Int? {
        cycleStart(for: date).map { days(from: $0, to: date) + 1 }
    }

    /// The next period's first day: the real one for past cycles, a
    /// prediction for the current one. `nil` once the prediction has passed
    /// (a late period) — there's no honest offset then.
    func nextStart(after date: Date) -> Date? {
        let day = calendar.startOfDay(for: date)
        if let actual = periodStarts.first(where: { $0 > day }) { return actual }
        guard let start = cycleStart(for: day) else { return nil }
        let predicted = self.day(typicalCycleLength, from: start)
        return predicted > day ? predicted : nil
    }

    /// Days before the next period: 1 is the day before. Lines up cycles of
    /// different lengths by the end they share.
    func backwardOffset(for date: Date) -> Int? {
        nextStart(after: date).map { days(from: date, to: $0) }
    }

    /// Where a day sits around a period: +1…+7 for the first week of a
    /// cycle, −7…−1 for the week before the next one, `nil` in between.
    func position(for date: Date) -> Int? {
        if let cycleDay = cycleDay(for: date), cycleDay <= Self.stretchReach { return cycleDay }
        if let offset = backwardOffset(for: date), offset <= Self.stretchReach { return -offset }
        return nil
    }

    private static let positions = Array(-stretchReach...(-1)) + Array(1...stretchReach)

    private func day(atPosition position: Int, in cycle: Cycle) -> Date {
        position < 0 ? day(position, from: cycle.nextStart) : day(position - 1, from: cycle.start)
    }

    // MARK: - Mood

    /// Median mood over her last 60 logged moods before `date`.
    func baselineMood(before date: Date) -> Double? {
        let day = calendar.startOfDay(for: date)
        let moods = logs.filter { $0.date < day }.compactMap(\.mood).suffix(Self.baselineWindow)
        guard moods.count >= Self.minimumBaselineDays else { return nil }
        return Self.median(moods.map(Double.init))
    }

    /// Mood at least 1 below her baseline, or two or more of low, anxious,
    /// irritable and cramps.
    func isHardDay(_ log: DayLog) -> Bool {
        if Set(log.symptoms).intersection(Symptom.hardDayIDs).count >= 2 { return true }
        guard let mood = log.mood, let baseline = baselineMood(before: log.date) else { return false }
        return Double(mood) <= baseline - 1
    }

    // MARK: - Symptoms

    struct SymptomStats: Equatable {
        let symptomID: String
        var yesDays = 0
        var askedDays = 0
        var frequency: Double { askedDays == 0 ? 0 : Double(yesDays) / Double(askedDays) }
        /// Usable cycles it showed up in.
        var cyclesWithSymptom = 0
        /// Yes days in each usable cycle, oldest first.
        var daysPerCycle: [Int] = []
        /// Median days before the period that it starts.
        var typicalStartOffset: Int?
        /// Median cycle day it starts.
        var typicalStartDay: Int?
        /// Median run of consecutive days, from its first day in a cycle.
        var typicalLength: Int?
        /// The "what helped" answer logged most on its days (ties go to the
        /// one followed by the better next-day mood).
        var topHelper: Helper?
        var topHelperCount = 0
        /// Its days that have any "what helped" answer.
        var helperAnswers = 0
    }

    func stats(for symptomID: String) -> SymptomStats {
        var stats = SymptomStats(symptomID: symptomID)
        for log in logs {
            if log.said(symptomID) { stats.yesDays += 1 }
            if log.said(symptomID) || log.skipped.contains(symptomID) { stats.askedDays += 1 }
        }

        var startOffsets: [Double] = [], startDays: [Double] = [], lengths: [Double] = []
        for cycle in usableCycles {
            let cycleDays = (0..<cycle.length).map { day($0, from: cycle.start) }
            let yes = cycleDays.filter { said(symptomID, on: $0) }
            stats.daysPerCycle.append(yes.count)
            guard !yes.isEmpty else { continue }
            stats.cyclesWithSymptom += 1
            // The first run that begins inside this cycle.
            guard let first = yes.first(where: { !said(symptomID, on: day(-1, from: $0)) }) else { continue }
            startOffsets.append(Double(days(from: first, to: cycle.nextStart)))
            startDays.append(Double(days(from: cycle.start, to: first) + 1))
            lengths.append(Double(runLength(of: symptomID, from: first)))
        }
        stats.typicalStartOffset = Self.median(startOffsets).map { Int($0.rounded()) }
        stats.typicalStartDay = Self.median(startDays).map { Int($0.rounded()) }
        stats.typicalLength = Self.median(lengths).map { Int($0.rounded()) }

        var counts: [Helper: Int] = [:], moodChanges: [Helper: [Double]] = [:]
        for log in logs where log.said(symptomID) {
            let helpers = Set(log.allHelpers)
            guard !helpers.isEmpty else { continue }
            stats.helperAnswers += 1
            for helper in helpers where helper != .nothingReally {
                counts[helper, default: 0] += 1
                if let mood = log.mood, let next = self.log(on: day(1, from: log.date))?.mood {
                    moodChanges[helper, default: []].append(Double(next - mood))
                }
            }
        }
        func averageChange(_ helper: Helper) -> Double {
            let changes = moodChanges[helper] ?? []
            return changes.isEmpty ? 0 : changes.reduce(0, +) / Double(changes.count)
        }
        if let top = counts.max(by: { ($0.value, averageChange($0.key)) < ($1.value, averageChange($1.key)) }) {
            stats.topHelper = top.key
            stats.topHelperCount = top.value
        }
        return stats
    }

    func said(_ symptomID: String, on date: Date) -> Bool {
        log(on: date)?.said(symptomID) ?? false
    }

    /// Consecutive yes days starting at `date`.
    func runLength(of symptomID: String, from date: Date) -> Int {
        var length = 0
        while said(symptomID, on: day(length, from: date)) { length += 1 }
        return length
    }

    /// Consecutive yes days ending at `date`, `date` included.
    func currentRun(of symptomID: String, endingOn date: Date) -> Int {
        var length = 0
        while said(symptomID, on: day(-length, from: date)) { length += 1 }
        return length
    }

    /// Clearly more days than her usual — at least 2 more and at least
    /// half again as many — in each of the last 3 usable cycles, measured
    /// against the median of the usable cycles before them (two or more).
    func isFlagged(_ stats: SymptomStats) -> Bool {
        let perCycle = stats.daysPerCycle
        guard perCycle.count >= 5, let usual = Self.median(perCycle.dropLast(3).map(Double.init)) else { return false }
        return perCycle.suffix(3).allSatisfy { Double($0) >= usual + 2 && Double($0) >= usual * 1.5 }
    }

    // MARK: - What to say after a swipe (D1)

    enum SymptomInsight: Equatable {
        /// Tier 1: not enough data — the general tip.
        case general
        /// Tier 2: `ordinal` is which day this week today is ("your 3rd").
        case recent(ordinal: Int, lastCycleStartDay: Int?)
        /// Tier 3: from two or more usable cycles.
        case personal(daysLeft: Int, helper: Helper?, helperCount: Int, helperAnswers: Int)
        /// Tier 4: heavier than usual for three cycles running.
        case flag(cycles: Int)

        var tier: Int {
            switch self {
            case .general: 1
            case .recent: 2
            case .personal: 3
            case .flag: 4
            }
        }
    }

    /// The most specific insight the data supports for a symptom she just
    /// said yes to today. `nil` means don't flip: only the general tip is
    /// left and it was already shown this week.
    func symptomInsight(for symptomID: String, on date: Date, generalLastShown: Date?) -> SymptomInsight? {
        let stats = stats(for: symptomID)
        if isFlagged(stats) { return .flag(cycles: 3) }

        if stats.cyclesWithSymptom >= 2, let typical = stats.typicalLength {
            let soFar = currentRun(of: symptomID, endingOn: date)
            return .personal(
                daysLeft: max(0, typical - soFar),
                helper: stats.topHelper,
                helperCount: stats.topHelperCount,
                helperAnswers: stats.helperAnswers
            )
        }

        let thisWeek = (1...7).filter { said(symptomID, on: day(-$0, from: date)) }.count
        if thisWeek >= 2 {
            return .recent(ordinal: thisWeek + 1, lastCycleStartDay: lastCycleStartDay(of: symptomID, before: date))
        }

        if let shown = generalLastShown, days(from: shown, to: date) < 7 { return nil }
        return .general
    }

    /// The cycle day it first showed up in the cycle before this one.
    private func lastCycleStartDay(of symptomID: String, before date: Date) -> Int? {
        guard let current = cycleStart(for: date),
              let last = completedCycles.last(where: { $0.nextStart == current })
        else { return nil }
        return (0..<last.length).first { said(symptomID, on: day($0, from: last.start)) }.map { $0 + 1 }
    }

    // MARK: - Today in one line (D3)

    enum TodayLine: Equatable {
        /// Inside her usual hard stretch around the period. `easesBy` is a
        /// position: positive is a period day, negative a day before it;
        /// `inDays` is how far off that is.
        case knownStretch(feelings: [String], cycleDay: Int, beforePeriod: Bool, easesBy: Int, inDays: Int)
        case goodWindow
        case earlyData
        case nothingToday
        /// None of the above: enough data, nothing notable today.
        case logged

        var asksForMatch: Bool {
            switch self {
            case .knownStretch, .goodWindow: true
            default: false
            }
        }
    }

    /// "Nothing today" is checked first — it has no answers to read.
    func todayLine(for today: DayLog) -> TodayLine {
        if today.nothingToday { return .nothingToday }
        guard usableCycles.count >= 2 else { return .earlyData }
        if let stretch = knownStretch(for: today) { return stretch }
        if isGoodWindow(today) { return .goodWindow }
        return .logged
    }

    /// Positions (see `position(for:)`) that were hard in at least half of
    /// her usable cycles, among those with that day logged (two or more).
    var usualHardPositions: Set<Int> {
        let cycles = usableCycles
        return Set(Self.positions.filter { position in
            var logged = 0, hard = 0
            for cycle in cycles {
                guard let log = log(on: day(atPosition: position, in: cycle)), log.isLogged else { continue }
                logged += 1
                if isHardDay(log) { hard += 1 }
            }
            return logged >= 2 && Double(hard) / Double(logged) >= 0.5
        })
    }

    private func knownStretch(for today: DayLog) -> TodayLine? {
        guard let position = position(for: today.date), let cycleDay = cycleDay(for: today.date) else { return nil }
        let hard = usualHardPositions
        guard hard.contains(position), let start = Self.positions.firstIndex(of: position) else { return nil }
        var index = start
        while index < Self.positions.count, hard.contains(Self.positions[index]) { index += 1 }
        let easesBy = index < Self.positions.count ? Self.positions[index] : Self.stretchReach + 1

        var feelings = Symptom.catalog.filter { today.said($0.id) }.map(\.label)
        if !today.said("low"), let mood = today.mood, let baseline = baselineMood(before: today.date), Double(mood) <= baseline - 1 {
            feelings.append("low mood")
        }
        return .knownStretch(
            feelings: feelings, cycleDay: cycleDay, beforePeriod: position < 0, easesBy: easesBy, inDays: index - start
        )
    }

    /// Not a hard day, and the same days (±1, by backward offset) in her
    /// usable cycles were never hard and ran above her usual mood or high
    /// on energy.
    private func isGoodWindow(_ today: DayLog) -> Bool {
        guard !isHardDay(today),
              let baseline = baselineMood(before: today.date),
              let offset = backwardOffset(for: today.date)
        else { return false }
        if let mood = today.mood, Double(mood) < baseline { return false }

        var logged = 0, hard = 0
        var moods: [Double] = [], energies: [Double] = []
        for cycle in usableCycles {
            for o in (offset - 1)...(offset + 1) where o >= 1 {
                let date = day(-o, from: cycle.nextStart)
                guard date >= cycle.start, let log = log(on: date), log.isLogged, !log.nothingToday else { continue }
                logged += 1
                if isHardDay(log) { hard += 1 }
                if let mood = log.mood { moods.append(Double(mood)) }
                if let energy = log.energy { energies.append(Double(energy)) }
            }
        }
        guard logged >= 3, hard == 0 else { return false }
        let moodHigh = Self.mean(moods).map { $0 >= baseline + 0.5 } ?? false
        let energyHigh = Self.mean(energies).map { $0 >= 4 } ?? false
        return moodHigh || energyHigh
    }

    // MARK: - Helpers

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

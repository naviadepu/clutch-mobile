import Foundation

// What the details page and the 4-card log need on top of the core engine:
// whether she's on her period, the next-period window, typical phases, what
// helps her, and what the page should say. Plain Swift, no UI.
extension CycleEngine {
    // MARK: - Period now

    /// Her usual period length: the median of logged periods (to Ended, or
    /// the last day of flow) once there are two, otherwise what she told
    /// Clutch, otherwise 5 days.
    var usualPeriodLength: Int {
        let lengths = periodStarts.compactMap(loggedPeriodDays)
        if lengths.count >= 2, let median = Self.median(lengths.map(Double.init)) { return Int(median.rounded()) }
        return profile.effectivePeriodLength
    }

    /// On her period: within her usual length since the last start (or
    /// still logging flow a little past it), and she hasn't tapped Ended.
    func isOnPeriod(_ date: Date) -> Bool {
        guard let start = cycleStart(for: date) else { return false }
        let dayIn = days(from: start, to: date)
        guard dayIn >= 0, dayIn < 12 else { return false }
        if (0...dayIn).contains(where: { log(on: day($0, from: start))?.periodEnded == true }) { return false }
        if dayIn < usualPeriodLength { return true }
        let yesterday = log(on: day(-1, from: date))
        return yesterday?.flow?.isBleeding == true
    }

    /// "Period, day 2" — `nil` when she isn't on her period.
    func periodDay(for date: Date) -> Int? {
        guard isOnPeriod(date), let start = cycleStart(for: date) else { return nil }
        return days(from: start, to: date) + 1
    }

    // MARK: - Next period window

    struct PeriodWindow: Equatable {
        let earliest: Date
        let likely: Date
        let latest: Date
        /// The window has passed without a logged start: it's any day now.
        let isLate: Bool
    }

    /// Last start plus her median recent cycle length, widened by how much
    /// her cycles vary (at least 1 and at most 7 days either side).
    func nextPeriodWindow(after date: Date) -> PeriodWindow? {
        let today = calendar.startOfDay(for: date)
        guard let last = cycleStart(for: today) else { return nil }
        let recent = plausibleCycles.suffix(6).map(\.length)
        let length = recent.count >= 2 ? Int(Self.median(recent.map(Double.init))!.rounded()) : typicalCycleLength
        let spread: Int
        if recent.count >= 2, let low = recent.min(), let high = recent.max() {
            spread = min(7, max(1, Int((Double(high - low) / 2).rounded(.up))))
        } else {
            spread = profile.cycleLength == nil ? 3 : 2
        }
        let likely = day(length, from: last)
        let latest = day(spread, from: likely)
        guard latest >= today else {
            return PeriodWindow(earliest: today, likely: today, latest: day(spread, from: today), isLate: true)
        }
        return PeriodWindow(earliest: day(-spread, from: likely), likely: likely, latest: latest, isLate: false)
    }

    /// Within 3 days of the predicted window (or inside it): when the
    /// "My period started" button shows on the first log card.
    func isNearPredictedPeriod(_ date: Date) -> Bool {
        guard !isOnPeriod(date), let window = nextPeriodWindow(after: date) else { return false }
        let today = calendar.startOfDay(for: date)
        return today >= day(-3, from: window.earliest) && today <= day(3, from: window.latest)
    }

    // MARK: - Typical phases

    enum Phase: String, CaseIterable {
        case period, rising, strongest, windingDown

        var title: String {
            switch self {
            case .period: "Period"
            case .rising: "Rising"
            case .strongest: "Strongest"
            case .windingDown: "Winding down"
            }
        }
    }

    struct PhaseSpan: Equatable {
        let phase: Phase
        let firstDay: Int
        let lastDay: Int
    }

    /// A typical cycle split into phases: her period, the days after it,
    /// the few days around ovulation (about 14 days before the next
    /// period), and the stretch before the next period.
    static func typicalPhases(cycleLength: Int, periodLength: Int) -> [PhaseSpan] {
        let length = max(cycleLength, periodLength + 4)
        let ovulation = length - 14
        let strongestFirst = max(periodLength + 1, ovulation - 2)
        let strongestLast = min(length - 1, max(strongestFirst, ovulation + 1))
        var spans = [PhaseSpan(phase: .period, firstDay: 1, lastDay: periodLength)]
        if strongestFirst > periodLength + 1 {
            spans.append(PhaseSpan(phase: .rising, firstDay: periodLength + 1, lastDay: strongestFirst - 1))
        }
        spans.append(PhaseSpan(phase: .strongest, firstDay: strongestFirst, lastDay: strongestLast))
        spans.append(PhaseSpan(phase: .windingDown, firstDay: strongestLast + 1, lastDay: length))
        return spans
    }

    var phaseSpans: [PhaseSpan] {
        Self.typicalPhases(cycleLength: typicalCycleLength, periodLength: usualPeriodLength)
    }

    /// Her phase today. A period logged or still running always wins;
    /// past the end of a typical cycle she's still winding down.
    func phase(for date: Date) -> Phase? {
        guard let cycleDay = cycleDay(for: date) else { return nil }
        if isOnPeriod(date) { return .period }
        let spans = phaseSpans
        let found = spans.first { (max($0.firstDay, 1)...$0.lastDay).contains(cycleDay) }?.phase ?? .windingDown
        // Her period ended early: those days count as rising.
        return found == .period ? .rising : found
    }

    // MARK: - What helps her

    struct HelperRank: Equatable {
        let helper: Helper
        let count: Int
        /// Follow-up answers overall, for "helped 3 of 4 times".
        let outOf: Int
    }

    /// Her helpers from the "what helped?" follow-ups, most often first.
    var helperRanking: [HelperRank] {
        let answers = logs.compactMap(\.helpedNextDay).filter { !$0.isEmpty }
        var counts: [Helper: Int] = [:]
        for answer in answers {
            for helper in Set(answer.compactMap(Helper.init(rawValue:))) where helper != .nothingReally {
                counts[helper, default: 0] += 1
            }
        }
        return counts
            .map { HelperRank(helper: $0.key, count: $0.value, outOf: answers.count) }
            .sorted { a, b in
                a.count != b.count
                    ? a.count > b.count
                    : (Helper.allCases.firstIndex(of: a.helper) ?? 0) < (Helper.allCases.firstIndex(of: b.helper) ?? 0)
            }
    }

    var followUpAnswerCount: Int {
        logs.filter { !($0.helpedNextDay ?? []).isEmpty }.count
    }

    // MARK: - Which sections are ready

    /// What the details page should say today: the header (the early-days
    /// line until there's a usable cycle), each logged symptom's tier, and
    /// whether to show the support line.
    struct DetailsPlan: Equatable {
        /// No usable cycle yet: the early-days page.
        let isEarlyDays: Bool
        let header: TodayLine
        let symptoms: [(id: String, insight: SymptomInsight)]
        /// Low 5 or more days in a row.
        let showsSupport: Bool

        static func == (a: DetailsPlan, b: DetailsPlan) -> Bool {
            a.isEarlyDays == b.isEarlyDays && a.header == b.header
                && a.symptoms.map { $0.id } == b.symptoms.map { $0.id }
                && a.symptoms.map { $0.insight } == b.symptoms.map { $0.insight }
                && a.showsSupport == b.showsSupport
        }
    }

    func detailsPlan(for today: DayLog) -> DetailsPlan {
        let usable = usableCycles.count
        let symptoms = Symptom.catalog.filter { today.said($0.id) }.map { symptom in
            (id: symptom.id, insight: symptomInsight(for: symptom.id, on: today.date, generalLastShown: nil) ?? .general)
        }
        return DetailsPlan(
            isEarlyDays: usable == 0,
            header: todayLine(for: today),
            symptoms: symptoms,
            showsSupport: currentRun(of: "low", endingOn: today.date) >= InsightCopy.supportAfterLowDays
        )
    }
}

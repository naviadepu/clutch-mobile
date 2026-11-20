import Foundation

/// One day of history from another app, in Clutch's terms.
struct ImportedDay: Equatable {
    var date: Date
    var flow: Flow?
    var symptoms: Set<String> = []
    /// The other app marked this as the first day of a period.
    var periodStart = false
}

/// Where imported history came from.
enum ImportSource: String, CaseIterable {
    case clue, health

    var title: String {
        switch self {
        case .clue: "Clue"
        case .health: "Apple Health"
        }
    }
}

/// Folds history from other apps into the day logs. Her own Clutch
/// answers always win: an import only fills in what's missing. Imported
/// days don't grow bouquets or count toward the streak (they aren't
/// `completed`), but the cycle engine reads their flow like any other
/// day's, so predictions use them straight away.
enum PeriodImport {
    /// What an import added, for the payoff screen.
    struct Summary: Equatable {
        var daysAdded: Int
        var periodDays: Int
        var cycleLengths: [Int]
        var since: Date?

        var cycles: Int { cycleLengths.count }
        var averageLength: Int? {
            cycleLengths.isEmpty ? nil : Int((Double(cycleLengths.reduce(0, +)) / Double(cycleLengths.count)).rounded())
        }
    }

    /// Merges the days and returns how many logs changed.
    @discardableResult
    static func merge(_ days: [ImportedDay], source: ImportSource, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: .now)
        var byDay: [Date: ImportedDay] = [:]
        for day in days {
            let key = calendar.startOfDay(for: day.date)
            guard key <= today else { continue }
            var merged = byDay[key] ?? ImportedDay(date: key)
            if let flow = day.flow, (merged.flow == nil || merged.flow == .noFlow || flow.rank > merged.flow!.rank) {
                merged.flow = flow
            }
            merged.symptoms.formUnion(day.symptoms)
            merged.periodStart = merged.periodStart || day.periodStart
            byDay[key] = merged
        }

        var changed = 0
        for (date, day) in byDay {
            let existing = DayLogStore.load(for: date)
            var log = existing ?? DayLog(date: date, seed: Int.random(in: 0...Int.max / 2))
            let before = log
            let herOwn = existing.map(hasOwnAnswers) ?? false

            if log.flow == nil, let flow = day.flow { log.flow = flow }
            if day.periodStart && !herOwn && day.flow?.isBleeding != false { log.periodStarted = true }
            let known = Set(Symptom.catalog.map(\.id))
            for id in day.symptoms where known.contains(id) && !log.symptoms.contains(id) && !log.skipped.contains(id) {
                log.symptoms.append(id)
            }
            guard log != before else { continue }
            if !herOwn { log.importedFrom = source.rawValue }
            DayLogStore.save(log)
            changed += 1
        }
        adoptLatestStart()
        return changed
    }

    /// Takes back everything an import added. Days she also logged in
    /// Clutch keep her answers.
    static func undo(_ source: ImportSource) {
        for log in DayLogStore.allLogs() where log.importedFrom == source.rawValue {
            if hasOwnAnswers(log) {
                var kept = log
                kept.importedFrom = nil
                if !log.answeredCards.contains("flow") { kept.flow = nil }
                DayLogStore.save(kept)
            } else {
                DayLogStore.remove(for: log.date)
            }
        }
    }

    static func hasImported(_ source: ImportSource) -> Bool {
        DayLogStore.allLogs().contains { $0.importedFrom == source.rawValue }
    }

    /// The history as Clutch now sees it.
    static func summary(daysAdded: Int) -> Summary {
        let logs = DayLogStore.allLogs()
        let engine = CycleEngine(logs: logs, profile: CycleProfile.load() ?? CycleProfile())
        return Summary(
            daysAdded: daysAdded,
            periodDays: logs.filter { $0.flow?.isBleeding == true }.count,
            cycleLengths: engine.plausibleCycles.map(\.length),
            since: engine.periodStarts.first
        )
    }

    /// Anything she answered herself in Clutch.
    private static func hasOwnAnswers(_ log: DayLog) -> Bool {
        log.completed || log.nothingToday || !log.answeredCards.isEmpty || log.mood != nil || log.legacySymptoms != nil
    }

    /// An onboarding guess for her last period gives way to the real date
    /// once imported history knows a later or nearby start.
    private static func adoptLatestStart() {
        guard var profile = CycleProfile.load() else { return }
        var bare = profile
        bare.lastPeriodStart = nil
        guard let latest = CycleEngine(logs: DayLogStore.allLogs(), profile: bare).periodStarts.last else { return }
        if let given = profile.lastPeriodStart, given > latest.addingTimeInterval(10 * 86_400) { return }
        profile.lastPeriodStart = latest
        profile.save()
    }
}

extension Flow {
    /// For picking the heavier of two readings on the same day.
    var rank: Int {
        switch self {
        case .noFlow: 0
        case .light: 1
        case .medium: 2
        case .heavy: 3
        }
    }
}

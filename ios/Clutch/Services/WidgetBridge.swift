import Foundation
import WidgetKit

/// Keeps the cloud widget in step with her logs: works out the next few
/// weeks of cycle state and hands it to the widget through the App Group.
enum WidgetBridge {
    private static var refreshPending = false

    /// Coalesces bursts of saves into one refresh on the next run loop.
    static func setNeedsRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async {
            refreshPending = false
            refresh()
        }
    }

    static func refresh(now: Date = .now) {
        let logs = DayLogStore.allLogs()
        let profile = CycleProfile.load() ?? CycleProfile()
        let snapshot = snapshot(logs: logs, profile: profile, now: now)
        snapshot.save()
        Task { await GentleNudges.refreshHardDay(snapshot: snapshot, now: now) }
        WidgetCenter.shared.reloadTimelines(ofKind: ClutchShared.widgetKind)
    }

    static func snapshot(logs: [DayLog], profile: CycleProfile, now: Date, calendar: Calendar = .current) -> CycleSnapshot {
        let engine = CycleEngine(logs: logs, profile: profile, calendar: calendar)
        let hardPositions = engine.usualHardPositions
        let today = calendar.startOfDay(for: now)
        let predictedNext = engine.nextStart(after: today)

        var snapshot = CycleSnapshot()
        for log in logs { if let mood = log.mood { snapshot.moods[CycleSnapshot.dayKey(for: log.date, calendar: calendar)] = mood } }
        snapshot.loggedDays = Set(logs.filter { $0.completed || $0.nothingToday }.map { CycleSnapshot.dayKey(for: $0.date, calendar: calendar) })

        for offset in 0..<21 {
            let day = engine.day(offset, from: today)
            var cycleDay = engine.cycleDay(for: day)
            var daysUntil = predictedNext.map { engine.days(from: day, to: $0) }
            // Past the predicted start, count from the prediction instead.
            if let next = predictedNext, day >= next {
                cycleDay = engine.days(from: next, to: day) + 1
                daysUntil = nil
            }
            if let d = daysUntil, d <= 0 { daysUntil = nil }

            let kind: CycleDayState.Kind
            let pastPrediction = predictedNext.map { day >= $0 } ?? false
            if isPeriod(day: day, cycleDay: cycleDay, pastPrediction: pastPrediction, engine: engine) {
                kind = .period
            } else if let position = engine.position(for: day), hardPositions.contains(position) {
                kind = .hard
            } else if let d = daysUntil, d <= 2 {
                kind = .beforePeriod
            } else {
                kind = .normal
            }
            snapshot.days[CycleSnapshot.dayKey(for: day, calendar: calendar)] = CycleDayState(kind: kind, cycleDay: cycleDay, daysUntilPeriod: daysUntil)
        }
        return snapshot
    }

    /// A logged flow wins; then the engine's own "on her period" (which
    /// respects Ended); past the predicted start, her usual length.
    private static func isPeriod(day: Date, cycleDay: Int?, pastPrediction: Bool, engine: CycleEngine) -> Bool {
        if let flow = engine.log(on: day)?.flow { return flow.isBleeding }
        if pastPrediction, let cycleDay { return cycleDay <= engine.usualPeriodLength }
        return engine.isOnPeriod(day)
    }
}

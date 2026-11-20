import Foundation

/// The two opt-in nudges: a heads-up the evening before her usual hard
/// stretch, and a nightly wind-down. Both off until she turns them on.
enum GentleNudges {
    static let hardDayID = "clutch.hardday"
    static let windDownID = "clutch.winddown"

    private static let defaults = UserDefaults.standard
    private static let hardDayKey = "nudges.hardDay"
    private static let windDownKey = "nudges.windDown"
    private static let windDownTimeKey = "nudges.windDownMinutes"

    static var hardDayOn: Bool {
        get { defaults.bool(forKey: hardDayKey) }
        set { defaults.set(newValue, forKey: hardDayKey) }
    }

    static var windDownOn: Bool {
        get { defaults.bool(forKey: windDownKey) }
        set { defaults.set(newValue, forKey: windDownKey) }
    }

    /// Minutes after midnight; 9:30pm until she changes it.
    static var windDownMinutes: Int {
        get { defaults.object(forKey: windDownTimeKey) as? Int ?? 21 * 60 + 30 }
        set { defaults.set(newValue, forKey: windDownTimeKey) }
    }

    /// The first day of her next usual hard stretch, starting tomorrow.
    static func nextHardStretch(in snapshot: CycleSnapshot, from now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 1..<21 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let before = calendar.date(byAdding: .day, value: -1, to: day) else { continue }
            if snapshot.state(on: day).kind == .hard && snapshot.state(on: before).kind != .hard { return day }
        }
        return nil
    }

    /// Re-plans the hard-day heads-up from the latest snapshot. Never asks
    /// for permission: that happens when she flips the toggle.
    static func refreshHardDay(snapshot: CycleSnapshot, now: Date = .now, calendar: Calendar = .current) async {
        guard hardDayOn, await LocalReminders.alreadyAuthorized(),
              let first = nextHardStretch(in: snapshot, from: now, calendar: calendar),
              let evening = calendar.date(byAdding: .day, value: -1, to: first)
                .flatMap({ calendar.date(bySettingHour: 20, minute: 0, second: 0, of: $0) }),
              evening > now
        else {
            LocalReminders.cancel(id: hardDayID)
            return
        }
        await LocalReminders.schedule(id: hardDayID, body: "The next few days are often heavier for you. Be gentle with yourself. I'm here if you need me.", at: evening)
    }

    static func setWindDown(_ on: Bool, minutes: Int) async -> Bool {
        windDownMinutes = minutes
        guard on else {
            windDownOn = false
            LocalReminders.cancel(id: windDownID)
            return true
        }
        let time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        let ok = await LocalReminders.schedule(id: windDownID, body: "Time to wind down? Tell me how today felt.", at: time, repeatsDaily: true)
        windDownOn = ok
        return ok
    }
}

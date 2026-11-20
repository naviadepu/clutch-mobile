import Foundation
import UserNotifications

/// Reminders from the insight actions. Local notifications only — scheduled
/// and delivered on the device, nothing sent anywhere. Asks permission the
/// first time one is used.
enum LocalReminders {
    /// A one-off reminder at a set time.
    @discardableResult
    static func schedule(body: String, at date: Date, now: Date = .now) async -> Bool {
        guard await authorized() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Clutch"
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSince(now), 1), repeats: false)
        return (try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        )) != nil
    }

    /// A reminder that replaces any earlier one with the same id, so
    /// rescheduling never stacks duplicates. `repeatsDaily` keeps only the
    /// hour and minute.
    @discardableResult
    static func schedule(id: String, body: String, at date: Date, repeatsDaily: Bool = false, calendar: Calendar = .current) async -> Bool {
        guard await authorized() else { return false }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "Clutch"
        content.body = body
        content.sound = .default
        let parts: Set<Calendar.Component> = repeatsDaily ? [.hour, .minute] : [.year, .month, .day, .hour, .minute]
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(parts, from: date), repeats: repeatsDaily)
        return (try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))) != nil
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Asks for permission now (from a toggle she just turned on).
    static func requestPermission() async -> Bool { await authorized() }

    /// True only if she's already said yes; never prompts.
    static func alreadyAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Asks the first time; `false` if she's said no.
    private static func authorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied: return false
        default: return true
        }
    }

    /// Returns whether it was scheduled (`false` if she declined).
    @discardableResult
    static func schedule(_ action: SymptomTips.Action, now: Date = .now) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard await authorized() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Clutch"
        content.body = action.reminderBody ?? action.title
        content.sound = .default

        guard let fireDate = fireDate(for: action, now: now) else { return false }
        let interval = max(fireDate.timeIntervalSince(now), 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    /// `afterMinutes` from now, or the next `atHour:atMinute`.
    static func fireDate(for action: SymptomTips.Action, now: Date, calendar: Calendar = .current) -> Date? {
        if let minutes = action.afterMinutes {
            return now.addingTimeInterval(TimeInterval(minutes * 60))
        }
        guard let hour = action.atHour else { return nil }
        let today = calendar.date(bySettingHour: hour, minute: action.atMinute ?? 0, second: 0, of: now)
        guard let today else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }
}

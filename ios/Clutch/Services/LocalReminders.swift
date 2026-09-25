import Foundation
import UserNotifications

/// Reminders from the insight actions. Local notifications only — scheduled
/// and delivered on the device, nothing sent anywhere. Asks permission the
/// first time one is used.
enum LocalReminders {
    /// Returns whether it was scheduled (`false` if she declined).
    @discardableResult
    static func schedule(_ action: SymptomTips.Action, now: Date = .now) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return false }
        case .denied:
            return false
        default:
            break
        }

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

import Foundation

// MARK: - Tips file

/// The wording behind every insight, read from `symptomTips.json` so it can
/// be edited without touching code.
struct SymptomTips: Decodable {
    struct Entry: Decodable {
        let tip: String
        /// "Your cramps" — the start of personal sentences.
        let subject: String
        /// Picks "last" or "lasts", "they" or "it".
        let plural: Bool
        /// "cramp" in "your 3rd cramp day this week".
        let dayNoun: String
        let action: Action
    }

    struct Action: Decodable {
        enum Kind: String, Decodable {
            case breathe, shareSoftDay, reminder, addSnack
        }

        let kind: Kind
        let title: String
        var shareText: String?
        /// Reminders: either this many minutes from now…
        var afterMinutes: Int?
        /// …or at this time today (tomorrow, if it's already passed).
        var atHour: Int?
        var atMinute: Int?
        var reminderBody: String?
    }

    struct SupportLink: Decodable {
        let text: String
        let linkTitle: String
        let url: URL
    }

    /// Placeholder actions for later, each behind a `FeatureFlags` switch.
    struct LaterAction: Decodable {
        let flag: String
        let symptom: String
        let title: String
        /// Involves a partner (delivery, a store): never shown to 15–17.
        let partner: Bool
    }

    let supportLink: SupportLink
    let symptoms: [String: Entry]
    let laterActions: [LaterAction]

    subscript(symptomID: String) -> Entry? { symptoms[symptomID] }

    static let shared: SymptomTips = {
        guard let url = Bundle.main.url(forResource: "symptomTips", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            assertionFailure("symptomTips.json is missing from the bundle")
            return SymptomTips(supportLink: .init(text: "", linkTitle: "", url: URL(string: "https://988lifeline.org")!), symptoms: [:], laterActions: [])
        }
        do {
            return try JSONDecoder().decode(SymptomTips.self, from: data)
        } catch {
            assertionFailure("symptomTips.json didn't decode: \(error)")
            return SymptomTips(supportLink: .init(text: "", linkTitle: "", url: URL(string: "https://988lifeline.org")!), symptoms: [:], laterActions: [])
        }
    }()

    /// The later actions to show for a symptom: switched on, and never a
    /// partner action for someone 15–17.
    func laterActions(for symptomID: String, profile: CycleProfile) -> [LaterAction] {
        laterActions.filter { action in
            action.symptom == symptomID
                && FeatureFlags.isOn(action.flag)
                && !(action.partner && profile.isMinor)
        }
    }
}

/// Switches for actions that aren't built yet. All off for Beta 1.
enum FeatureFlags {
    static let restock = false
    static let studyPlanner = false
    static let comfortDelivery = false

    static func isOn(_ flag: String) -> Bool {
        switch flag {
        case "restock": restock
        case "studyPlanner": studyPlanner
        case "comfortDelivery": comfortDelivery
        default: false
        }
    }
}

// MARK: - Sentences

/// Turns engine results into the one-line insights. Plain, warm, and never
/// a diagnosis — the strongest it gets is "might be worth mentioning to a
/// doctor."
enum InsightCopy {
    /// Five or more low days in a row adds the support line.
    static let supportAfterLowDays = 5

    static func text(for insight: CycleEngine.SymptomInsight, symptomID: String, tips: SymptomTips = .shared) -> String {
        guard let entry = tips[symptomID] else { return "" }
        let pronoun = entry.plural ? "they" : "it"
        switch insight {
        case .general:
            return entry.tip

        case let .recent(ordinal, lastCycleStartDay):
            var text = "This is your \(ordinalString(ordinal)) \(entry.dayNoun) day this week."
            if let day = lastCycleStartDay {
                text += " Last cycle \(pronoun) started on day \(day)."
            }
            return text

        case let .personal(daysLeft, helper, helperCount, helperAnswers):
            var text = daysLeft > 0
                ? "\(entry.subject) usually \(entry.plural ? "last" : "lasts") about \(daysLeft) more day\(daysLeft == 1 ? "" : "s")."
                : "\(entry.subject) usually \(entry.plural ? "ease" : "eases") around now."
            if let helper, helperAnswers >= 2 {
                text += " \(helper.phrase.prefix(1).uppercased() + helper.phrase.dropFirst()) helped you \(helperCount) out of \(helperAnswers) times."
            }
            return text

        case let .flag(cycles):
            return "\(entry.subject) \(entry.plural ? "have" : "has") been heavier than usual for \(cycles) cycles. That might be worth mentioning to a doctor."
        }
    }

    static func text(for line: CycleEngine.TodayLine) -> String {
        switch line {
        case let .knownStretch(feelings, cycleDay, beforePeriod, easesBy, inDays):
            let stretch = beforePeriod ? "pre-period" : "period"
            var text: String
            if feelings.isEmpty {
                text = "Day \(cycleDay) is your usual \(stretch) stretch."
            } else {
                let list = feelings.joined(separator: ", ")
                text = list.prefix(1).uppercased() + list.dropFirst() + ", and day \(cycleDay) is your usual \(stretch) stretch."
            }
            if easesBy > CycleEngine.stretchReach {
                text += " For you, it usually eases after the first week of your period."
            } else if easesBy > 0 {
                text += " For you, it usually eases by day \(easesBy) of your period."
            } else {
                text += " For you, it usually eases in about \(inDays) day\(inDays == 1 ? "" : "s")."
            }
            return text
        case .goodWindow:
            return "You're in your strong days. Good time for the big stuff."
        case .earlyData:
            return "Logged. After your next period, Clutch can start showing your patterns."
        case .nothingToday:
            return "Seed planted. Your streak is safe."
        case .logged:
            return "Logged. Clutch is still learning what this part of your cycle looks like for you."
        }
    }

    /// "Yesterday you had cramps. What helped?"
    static func followUpQuestion(symptomIDs: [String], daysAgo: Int, day: Date) -> String {
        let when = daysAgo == 1 ? "Yesterday" : "On \(day.formatted(.dateTime.weekday(.wide)))"
        let names = symptomIDs.compactMap { Symptom.named($0)?.label }
        guard !names.isEmpty else { return "\(when) was a hard day. What helped?" }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "\(when) you had \(list). What helped?"
    }

    static func ordinalString(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Local insight history

/// What she's seen and said about insights, kept on the device only.
enum InsightStore {
    private static let defaults = UserDefaults.standard
    private static let generalShownKey = "insights.generalShown"
    private static let feedbackKey = "insights.feedback"
    private static let snackKey = "insights.snackList"

    /// When each symptom's general tip last showed, for the once-a-week rule.
    static func generalLastShown(_ symptomID: String) -> Date? {
        (defaults.dictionary(forKey: generalShownKey) as? [String: Date])?[symptomID]
    }

    static func markGeneralShown(_ symptomID: String, on date: Date = .now) {
        var shown = (defaults.dictionary(forKey: generalShownKey) as? [String: Date]) ?? [:]
        shown[symptomID] = date
        defaults.set(shown, forKey: generalShownKey)
    }

    /// Her "Does this match you?" answers.
    struct Feedback: Codable, Equatable {
        let date: Date
        /// "tier3.cramps", "tier4.low", "today.knownStretch", …
        let insight: String
        let text: String
        let matches: Bool
    }

    static func feedback() -> [Feedback] {
        defaults.data(forKey: feedbackKey).flatMap { try? JSONDecoder().decode([Feedback].self, from: $0) } ?? []
    }

    static func record(_ entry: Feedback) {
        let all = feedback() + [entry]
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: feedbackKey) }
    }

    static func snackList() -> [String] {
        defaults.stringArray(forKey: snackKey) ?? []
    }

    static func addSnack(_ snack: String) {
        let trimmed = snack.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(snackList() + [trimmed], forKey: snackKey)
    }
}

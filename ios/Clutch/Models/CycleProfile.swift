import Foundation

/// What onboarding and the one-time cards learn about her. Every cycle
/// answer is optional — `nil` means "Not sure", and the typical values
/// below stand in until real periods get logged.
struct CycleProfile: Codable, Equatable {
    static let typicalCycleLength = 28
    static let typicalPeriodLength = 5

    var ageRange: AgeRange?
    /// Exact age, kept only from the first version of onboarding. New
    /// users give just a range.
    var age: Int?
    /// `nil` when she isn't sure; she logs it when the next one starts.
    var lastPeriodStart: Date?
    /// First day of one period to the first day of the next.
    var cycleLength: Int?
    var periodLength: Int?

    // Asked by the one-time cards; `nil` until answered.
    var birthControl: BirthControl?
    var products: [PeriodProduct]?
    var isStudent: Bool?
    var goals: [HelpGoal]?

    /// When onboarding finished. One-time cards count days from here.
    var onboardedOn: Date?
    var onboardingComplete = false
    /// Answered or skipped one-time cards, keyed by `OneTimeQuestion` id.
    var oneTimeCards: [String: OneTimeCardState] = [:]

    init() {}

    var effectiveCycleLength: Int { cycleLength ?? Self.typicalCycleLength }
    var effectivePeriodLength: Int { periodLength ?? Self.typicalPeriodLength }

    /// Partner actions (delivery and the like) are hidden for 15–17.
    var isMinor: Bool { ageRange == .fifteenToSeventeen }

    /// Logging a period today either starts a new cycle — giving an exact
    /// start date, even after "Not sure" — or continues the one already
    /// running. Returns the new start date, or `nil` if the current one
    /// still holds.
    static func newPeriodStart(
        loggedOn day: Date,
        yesterdayHadPeriod: Bool,
        currentStart: Date?,
        periodLength: Int,
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: day)
        if yesterdayHadPeriod { return nil }
        if let currentStart {
            let start = calendar.startOfDay(for: currentStart)
            let daysIn = calendar.dateComponents([.day], from: start, to: today).day ?? .max
            // Still inside the period she already told us about (with a day
            // or two of slack for a longer-than-usual one).
            if daysIn >= 0 && daysIn < periodLength + 2 { return nil }
        }
        return today
    }

    private static let storageKey = "cycleProfile"

    static func load(from defaults: UserDefaults = .standard) -> CycleProfile? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CycleProfile.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension CycleProfile {
    private enum CodingKeys: String, CodingKey {
        case ageRange, age, lastPeriodStart, cycleLength, periodLength, birthControl, products,
             isStudent, goals, onboardedOn, onboardingComplete, oneTimeCards
    }

    /// Reads both versions. A first-version profile was only ever saved at
    /// the end of onboarding, so it counts as onboarded, its exact age
    /// becomes a range, and the questions it already answered (birth
    /// control, period length) are marked done so they aren't asked again.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        lastPeriodStart = try c.decodeIfPresent(Date.self, forKey: .lastPeriodStart)
        cycleLength = try c.decodeIfPresent(Int.self, forKey: .cycleLength)
        periodLength = try c.decodeIfPresent(Int.self, forKey: .periodLength)
        birthControl = try c.decodeIfPresent(BirthControl.self, forKey: .birthControl)
        products = try c.decodeIfPresent([PeriodProduct].self, forKey: .products)
        isStudent = try c.decodeIfPresent(Bool.self, forKey: .isStudent)
        goals = try c.decodeIfPresent([HelpGoal].self, forKey: .goals)
        onboardedOn = try c.decodeIfPresent(Date.self, forKey: .onboardedOn)
        oneTimeCards = try c.decodeIfPresent([String: OneTimeCardState].self, forKey: .oneTimeCards) ?? [:]
        ageRange = try c.decodeIfPresent(AgeRange.self, forKey: .ageRange) ?? age.map(AgeRange.init(age:))

        if let complete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) {
            onboardingComplete = complete
        } else {
            onboardingComplete = true
            oneTimeCards[OneTimeQuestion.birthControl.id] = .answered
            oneTimeCards[OneTimeQuestion.periodLength.id] = .answered
        }
    }
}

enum AgeRange: String, Codable, CaseIterable, Identifiable {
    case fifteenToSeventeen = "15-17"
    case eighteenToTwentyFour = "18-24"
    case twentyFiveToThirtyFive = "25-35"
    case thirtySixToSeventy = "36-70"

    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "-", with: " – ") }

    /// For migrating an exact age. The first onboarding allowed 13 and 14,
    /// which land in the youngest range.
    init(age: Int) {
        switch age {
        case ...17: self = .fifteenToSeventeen
        case 18...24: self = .eighteenToTwentyFour
        case 25...35: self = .twentyFiveToThirtyFive
        default: self = .thirtySixToSeventy
        }
    }
}

enum BirthControl: String, Codable, CaseIterable, Identifiable {
    case none
    case pillPatchOrRing
    case hormonalIUD
    case copperIUD
    case implantOrShot
    case other
    case preferNotToSay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .pillPatchOrRing: "The pill, patch, or ring"
        case .hormonalIUD: "Hormonal IUD"
        case .copperIUD: "Copper IUD"
        case .implantOrShot: "Implant or shot"
        case .other: "Something else"
        case .preferNotToSay: "Prefer not to say"
        }
    }

    /// How the cycle should be read: "Prefer not to say" counts as no birth
    /// control until she changes it.
    var effective: BirthControl {
        self == .preferNotToSay ? .none : self
    }
}

enum PeriodProduct: String, Codable, CaseIterable, Identifiable {
    case pads, tampons, cup
    case periodUnderwear = "period-underwear"
    case mix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pads: "Pads"
        case .tampons: "Tampons"
        case .cup: "Cup"
        case .periodUnderwear: "Period underwear"
        case .mix: "A mix"
        }
    }
}

enum HelpGoal: String, Codable, CaseIterable, Identifiable {
    case mood, pain, energy, planning
    case understandingMyBody = "understanding-my-body"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .understandingMyBody: "Understanding my body"
        default: rawValue.capitalized
        }
    }
}

/// The one-time questions that open the daily deck, one a day from day 2.
enum OneTimeQuestion: String, CaseIterable, Identifiable {
    case birthControl, periodLength, products, student, goals

    var id: String { "onetime.\(rawValue)" }

    /// The first day (counting onboarding as day 1) it can show.
    var day: Int {
        switch self {
        case .birthControl: 2
        case .periodLength: 3
        case .products: 4
        case .student: 5
        case .goals: 6
        }
    }

    /// Spelled out on the card's crossword.
    var word: String {
        switch self {
        case .birthControl: "birth control"
        case .periodLength: "period days"
        case .products: "products"
        case .student: "student"
        case .goals: "help with"
        }
    }

    var question: String {
        switch self {
        case .birthControl: "Are you on birth control?"
        case .periodLength: "How long does your period usually last?"
        case .products: "What do you use?"
        case .student: "Are you a student?"
        case .goals: "What do you want help with most?"
        }
    }
}

/// A one-time card's history. Skipped once, it comes back a week later;
/// skipped twice, it's gone (still editable from the details page).
struct OneTimeCardState: Codable, Equatable {
    var answered = false
    var skips: [Date] = []

    static let answered = OneTimeCardState(answered: true)
}

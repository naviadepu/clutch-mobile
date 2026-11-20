import Foundation

/// One day's log. `seed` is what makes the garden deterministic — flower
/// shape, position and sway all derive from it, so the same day always
/// renders the same bouquet instead of reshuffling on every redraw.
///
/// Version 1 logs (the five-card deck: period, feeling low, anxious, mood
/// swings, irritable) are migrated as they're decoded; their original
/// answers stay in `legacySymptoms` / `legacySkipped`.
struct DayLog: Codable, Equatable {
    static let currentVersion = 2

    let date: Date
    let seed: Int
    var version = Self.currentVersion

    /// `nil` until the Flow card is answered.
    var flow: Flow?
    /// 1–5, `nil` until answered.
    var mood: Int?
    var energy: Int?
    /// Symptoms she swiped yes on.
    var symptoms: [String] = []
    /// Symptoms she swiped no on.
    var skipped: [String] = []
    /// What helped, from the What helped card on a hard day.
    var helped: [String] = []
    /// What helped, asked the next morning. `nil` until that's answered.
    var helpedNextDay: [String]?
    /// She tapped "Nothing today": the log ends there, and still counts.
    var nothingToday = false
    /// She tapped "My period started" today: a new cycle begins.
    var periodStarted = false
    /// She tapped "Ended" on the Flow card: her period ended today.
    var periodEnded = false
    /// The streak milestone celebrated today ("7", "14", "28", "cycle"),
    /// which adds a special flower to the bouquet.
    var milestone: String?

    /// Card ids answered today, so a relaunch resumes the deck.
    var answeredCards: [String] = []
    /// The card chosen to open today's deck (a one-time question or a
    /// follow-up), fixed once picked so a relaunch doesn't change it.
    /// `nil` until decided, `""` for none.
    var leadCard: String?
    /// Flowers grown today, one per card answered. Past bouquets regrow
    /// from this.
    var planted = 0
    /// The deck was finished, or ended with "Nothing today". Completed
    /// days make up the streak.
    var completed = false

    /// The retired yes/no mood swings card. A yes/no can't honestly become
    /// a 1–5 mood, so it's kept as it was and `mood` stays empty.
    var moodSwings: Bool?
    /// A version 1 log's answers, exactly as stored.
    var legacySymptoms: [String]?
    var legacySkipped: [String]?
    /// Where data on this day came from when it wasn't logged in Clutch
    /// ("clue", "health"), so an import can be undone.
    var importedFrom: String?

    init(date: Date, seed: Int) {
        self.date = date
        self.seed = seed
    }

    /// Anything at all was logged — what counts toward a usable cycle.
    var isLogged: Bool {
        completed || nothingToday || !answeredCards.isEmpty || flow != nil || periodStarted || legacySymptoms != nil
    }

    func said(_ symptomID: String) -> Bool { symptoms.contains(symptomID) }

    /// Every "what helped" answer for this day, same-day and next-day.
    var allHelpers: [Helper] {
        (helped + (helpedNextDay ?? [])).compactMap(Helper.init(rawValue:))
    }
}

extension DayLog {
    private enum CodingKeys: String, CodingKey {
        case date, seed, version, flow, mood, energy, symptoms, skipped, helped, helpedNextDay,
             nothingToday, periodStarted, periodEnded, milestone, answeredCards, leadCard, planted, completed, moodSwings, legacySymptoms, legacySkipped, importedFrom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let date = try c.decode(Date.self, forKey: .date)
        let seed = try c.decode(Int.self, forKey: .seed)
        let flow = try c.decodeIfPresent(Flow.self, forKey: .flow)
        let storedSymptoms = try c.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        let storedSkipped = try c.decodeIfPresent([String].self, forKey: .skipped) ?? []

        guard let storedVersion = try c.decodeIfPresent(Int.self, forKey: .version) else {
            self.init(migratingV1: date, seed: seed, flow: flow, symptoms: storedSymptoms, skipped: storedSkipped)
            return
        }
        self.init(date: date, seed: seed)
        version = storedVersion
        self.flow = flow
        symptoms = storedSymptoms
        skipped = storedSkipped
        mood = try c.decodeIfPresent(Int.self, forKey: .mood)
        energy = try c.decodeIfPresent(Int.self, forKey: .energy)
        helped = try c.decodeIfPresent([String].self, forKey: .helped) ?? []
        helpedNextDay = try c.decodeIfPresent([String].self, forKey: .helpedNextDay)
        nothingToday = try c.decodeIfPresent(Bool.self, forKey: .nothingToday) ?? false
        periodStarted = try c.decodeIfPresent(Bool.self, forKey: .periodStarted) ?? false
        periodEnded = try c.decodeIfPresent(Bool.self, forKey: .periodEnded) ?? false
        milestone = try c.decodeIfPresent(String.self, forKey: .milestone)
        answeredCards = try c.decodeIfPresent([String].self, forKey: .answeredCards) ?? []
        leadCard = try c.decodeIfPresent(String.self, forKey: .leadCard)
        planted = try c.decodeIfPresent(Int.self, forKey: .planted) ?? 0
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        moodSwings = try c.decodeIfPresent(Bool.self, forKey: .moodSwings)
        legacySymptoms = try c.decodeIfPresent([String].self, forKey: .legacySymptoms)
        legacySkipped = try c.decodeIfPresent([String].self, forKey: .legacySkipped)
        importedFrom = try c.decodeIfPresent(String.self, forKey: .importedFrom)
    }

    /// Version 1 → 2. "feeling low" and "anxious" already used the ids the
    /// new `low` and `anxious` swipes use, and "irritable" is unchanged, so
    /// those carry straight over. The period card's flow carries over too.
    /// Mood swings becomes `moodSwings`. Nothing is thrown away: the
    /// original lists are kept, and the bouquet keeps its flower count.
    private init(migratingV1 date: Date, seed: Int, flow: Flow?, symptoms: [String], skipped: [String]) {
        self.init(date: date, seed: seed)
        let current = Set(Symptom.catalog.map(\.id))
        self.flow = flow
        self.symptoms = symptoms.filter(current.contains)
        self.skipped = skipped.filter(current.contains)
        legacySymptoms = symptoms
        legacySkipped = skipped
        if symptoms.contains(Symptom.legacyMoodSwingsID) {
            moodSwings = true
        } else if skipped.contains(Symptom.legacyMoodSwingsID) {
            moodSwings = false
        }
        planted = symptoms.count + skipped.count
        // The old deck had five cards; answering all five collected the day.
        completed = planted >= 5
        answeredCards = (self.symptoms + self.skipped).map { "symptom.\($0)" }
        if (symptoms + skipped).contains(Symptom.legacyPeriodID) { answeredCards.append("flow") }
    }
}

/// A tiny local store for `DayLog`s, keyed by calendar day. Health data
/// stays on the device: nothing here is sent anywhere.
enum DayLogStore {
    private static let defaults = UserDefaults.standard

    private static let keyPrefix = "garden.log."

    private static func key(for date: Date) -> String {
        keyPrefix + dayKey(for: date)
    }

    /// Every stored day, oldest first.
    static func allLogs() -> [DayLog] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .compactMap { key in
                defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DayLog.self, from: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func load(for date: Date) -> DayLog? {
        guard let data = defaults.data(forKey: key(for: date)) else { return nil }
        return try? JSONDecoder().decode(DayLog.self, from: data)
    }

    static func save(_ log: DayLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: key(for: log.date))
        WidgetBridge.setNeedsRefresh()
    }

    static func remove(for date: Date) {
        defaults.removeObject(forKey: key(for: date))
        WidgetBridge.setNeedsRefresh()
    }

    /// Loads or mints today's log, so the seed (and therefore the garden's
    /// look) is stable across app launches for the same day.
    static func loadOrCreate(for date: Date) -> DayLog {
        if let existing = load(for: date) { return existing }
        let fresh = DayLog(date: date, seed: Int.random(in: 0...Int.max / 2))
        save(fresh)
        return fresh
    }
}

/// Deterministic RNG (SplitMix64) so a stored `seed` always reproduces the
/// same sequence of "random" flower values.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

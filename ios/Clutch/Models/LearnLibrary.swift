import Foundation

/// The "Why?" topics, read from `learnLibrary.json` so the founder can add
/// and edit them without touching code. A topic only shows when it
/// connects to something she logged, her phase, or what's coming next.
struct LearnLibrary: Decodable {
    struct Topic: Decodable, Identifiable, Equatable {
        struct Triggers: Decodable, Equatable {
            var symptoms: [String] = []
            var phases: [String] = []
            var insights: [String] = []
        }

        struct Source: Decodable, Equatable, Hashable {
            let title: String
            let publisher: String
            let year: Int?
            let url: URL
            let takeaway: String
        }

        let id: String
        var needsReview = true
        let triggers: Triggers
        let forYouTemplate: String
        let explainer: String
        let sources: [Source]

        func forYou(dayPhrase: String) -> String {
            forYouTemplate.replacingOccurrences(of: "{day}", with: dayPhrase)
        }
    }

    let topics: [Topic]

    /// What a "Why?" link knows about the moment it's attached to.
    struct Context: Equatable {
        var symptoms: Set<String> = []
        var phase: CycleEngine.Phase?
        var insights: Set<String> = []
    }

    /// The best topic for a context: every trigger group it sets must
    /// match, and the one matching the most groups wins. `nil` when
    /// nothing connects — then there's no "Why?" link.
    func topic(for context: Context) -> Topic? {
        let scored = topics.compactMap { topic -> (Topic, Int)? in
            let t = topic.triggers
            var matched = 0
            if !t.symptoms.isEmpty {
                guard !context.symptoms.isDisjoint(with: t.symptoms) else { return nil }
                matched += 1
            }
            if !t.phases.isEmpty {
                guard let phase = context.phase, t.phases.contains(phase.rawValue) else { return nil }
                matched += 1
            }
            if !t.insights.isEmpty {
                guard !context.insights.isDisjoint(with: t.insights) else { return nil }
                matched += 1
            }
            return matched > 0 ? (topic, matched) : nil
        }
        return scored.max { $0.1 < $1.1 }?.0
    }

    static let shared: LearnLibrary = {
        guard let url = Bundle.main.url(forResource: "learnLibrary", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            assertionFailure("learnLibrary.json is missing from the bundle")
            return LearnLibrary(topics: [])
        }
        do {
            return try JSONDecoder().decode(LearnLibrary.self, from: data)
        } catch {
            assertionFailure("learnLibrary.json didn't decode: \(error)")
            return LearnLibrary(topics: [])
        }
    }()
}

extension LearnLibrary.Topic.Triggers {
    private enum CodingKeys: String, CodingKey { case symptoms, phases, insights }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symptoms = try c.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        phases = try c.decodeIfPresent([String].self, forKey: .phases) ?? []
        insights = try c.decodeIfPresent([String].self, forKey: .insights) ?? []
    }
}

extension CycleEngine {
    /// Facts about her the "Why?" topics can hang off.
    func learnInsights(for today: DayLog) -> Set<String> {
        var insights: Set<String> = []
        if let periodDay = periodDay(for: today.date), periodDay <= 3, (today.energy ?? 5) <= 3 {
            insights.insert("lowEnergyOnPeriod")
        }
        let lengths = completedCycles.map(\.length).filter { (15...60).contains($0) }
        if let low = lengths.min(), let high = lengths.max(), high - low > 7 {
            insights.insert("irregularCycles")
        }
        if lengths.count >= 3, let last = lengths.last,
           let usual = Self.median(lengths.dropLast().map(Double.init)), abs(Double(last) - usual) >= 5 {
            insights.insert("cycleLengthChanged")
        }
        switch profile.birthControl {
        case .pillPatchOrRing, .hormonalIUD, .implantOrShot: insights.insert("hormonalBirthControl")
        default: break
        }
        return insights
    }
}

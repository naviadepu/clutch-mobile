import Foundation

/// One finished day's bouquet, rebuilt from that day's log.
struct CollectedBouquet: Identifiable {
    let day: Date
    let flowers: [PlantedFlower]
    var style: BouquetStyle = .plain

    var id: Date { day }
}

/// Every day she finishes the deck (or taps "Nothing today") adds that
/// day's bouquet to her collection; consecutive days build a streak.
enum BouquetCollection {
    /// Newest first.
    static func load() -> [CollectedBouquet] {
        DayLogStore.allLogs()
            .filter(\.completed)
            .reversed()
            .map { CollectedBouquet(day: $0.date, flowers: BouquetGenerator.flowers(for: $0), style: BouquetStyle(log: $0)) }
    }

    /// Consecutive collected days ending today — or ending yesterday, so a
    /// streak isn't shown as broken before today's cards are done.
    static func streak(collectedDays: [Date], today: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(collectedDays.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

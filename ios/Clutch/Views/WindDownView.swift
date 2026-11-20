import SwiftUI

/// One night's wind-down. Stays on the phone.
struct JournalEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let date: Date
    let feelings: [String]
    let text: String
}

enum JournalStore {
    private static let key = "journal.entries"

    static func all() -> [JournalEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([JournalEntry].self, from: data) else { return [] }
        return entries.sorted { $0.date > $1.date }
    }

    static func add(_ entry: JournalEntry) {
        guard let data = try? JSONEncoder().encode(all() + [entry]) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum Feeling: String, CaseIterable, Identifiable {
    case calm, happy, grateful, tired, anxious, sad, angry, overwhelmed
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .calm: "leaf"
        case .happy: "sun.max"
        case .grateful: "heart"
        case .tired: "moon.zzz"
        case .anxious: "waveform.path"
        case .sad: "cloud.drizzle"
        case .angry: "flame"
        case .overwhelmed: "tornado"
        }
    }
    var isHeavy: Bool { [.tired, .anxious, .sad, .angry, .overwhelmed].contains(self) }
}

/// Two minutes before bed: how today felt, write it out, breathe with the
/// cloud, close the day.
struct WindDownView: View {
    private enum Step { case feel, write, breathe, done }

    @State private var step = Step.feel
    @State private var feelings: [Feeling] = []
    @State private var text = ""
    @State private var past = JournalStore.all()
    @State private var reminderOn = GentleNudges.windDownOn
    @State private var reminderTime = Calendar.current.date(bySettingHour: GentleNudges.windDownMinutes / 60, minute: GentleNudges.windDownMinutes % 60, second: 0, of: .now) ?? .now
    @State private var reminderNote: String?
    @State private var reading: JournalEntry?
    @FocusState private var writing: Bool

    var body: some View {
        ClutchPage(title: "wind down", subtitle: "Two quiet minutes before bed.") {
            switch step {
            case .feel: feelCard
            case .write: writeCard
            case .breathe:
                VStack(spacing: 10) {
                    CloudBreathing { finish() }
                    Button("Skip") { finish() }.buttonStyle(.plain).font(.custom("DMSans-Light", size: 13)).foregroundStyle(Color.cardSoft)
                }
                .frame(maxWidth: .infinity)
            case .done:
                VStack(spacing: 10) {
                    FuzzyCloud(face: .sleepy).frame(width: 180)
                    Text(feelings.contains(where: \.isHeavy) ? "Thanks for letting it out. I'll be here tomorrow." : "Today counted. Sleep well.")
                        .font(.system(size: 17, design: .serif).italic())
                        .foregroundStyle(Color.cardInk)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            if !past.isEmpty { pastCard }
            reminderCard
        }
    }

    private var feelCard: some View {
        VStack(spacing: 16) {
            Text("HOW DID TODAY FEEL? UP TO 3").detailsLabel()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 14) {
                ForEach(Feeling.allCases) { feeling in
                    let on = feelings.contains(feeling)
                    Button {
                        if on { feelings.removeAll { $0 == feeling } } else if feelings.count < 3 { feelings.append(feeling) }
                    } label: {
                        IconBubble(symbol: feeling.symbol, title: feeling.rawValue, filled: on, size: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            PagePrimaryButton(title: "Next", symbol: "arrow.right") { withAnimation { step = .write } }
                .disabled(feelings.isEmpty)
                .opacity(feelings.isEmpty ? 0.5 : 1)
        }
    }

    private var writeCard: some View {
        DetailsCard(title: prompt) {
            TextEditor(text: $text)
                .focused($writing)
                .font(.custom("DMSans-Light", size: 15))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Label("Stays on your phone", systemImage: "lock.fill").font(.custom("DMSans-Light", size: 12)).foregroundStyle(Color.cardSoft)
            PagePrimaryButton(title: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip writing" : "Done") {
                writing = false
                withAnimation { step = .breathe }
            }
        }
    }

    private var prompt: String {
        if feelings.contains(where: \.isHeavy) { return "What's weighing on you tonight?" }
        if feelings.contains(.grateful) { return "What are you grateful for today?" }
        return "What's one thing from today you want to remember?"
    }

    private func finish() {
        JournalStore.add(JournalEntry(date: .now, feelings: feelings.map(\.rawValue), text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        past = JournalStore.all()
        withAnimation { step = .done }
    }

    /// One quiet row: a bell, and the time when it's on.
    private var reminderCard: some View {
        Panel(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: reminderOn ? "bell.fill" : "bell")
                    .foregroundStyle(Color.cardInk)
                    .frame(width: 34, height: 34)
                    .background(reminderOn ? Color.strawberry : Color.white.opacity(0.6), in: Circle())
                Toggle(isOn: $reminderOn) { Text("Nightly nudge").detailsBody() }
                    .tint(Color.matcha)
            }
            if reminderOn {
                DatePicker("At", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .font(.custom("DMSans-Light", size: 15))
            }
            if let reminderNote { Text(reminderNote).detailsSmall() }
        }
        .onChange(of: reminderOn) { _, _ in saveReminder() }
        .onChange(of: reminderTime) { _, _ in if reminderOn { saveReminder() } }
    }

    private func saveReminder() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let minutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 30)
        Task {
            let ok = await GentleNudges.setWindDown(reminderOn, minutes: minutes)
            if reminderOn && !ok {
                reminderOn = false
                reminderNote = "Turn on notifications for Clutch in Settings first."
            } else {
                reminderNote = reminderOn ? "See you tonight at \(reminderTime.formatted(date: .omitted, time: .shortened))." : nil
            }
        }
    }

    /// The last seven nights as a strip: each night's first feeling, or
    /// an empty dot. Tap one to read what she wrote.
    private var pastCard: some View {
        let calendar = Calendar.current
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now)) }
        return Panel(padding: 14) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let entry = past.first { calendar.isDate($0.date, inSameDayAs: day) }
                    let feeling = entry?.feelings.first.flatMap(Feeling.init)
                    Button { reading = entry } label: {
                        VStack(spacing: 6) {
                            Image(systemName: feeling?.symbol ?? "circle.dotted")
                                .font(.system(size: 14))
                                .foregroundStyle(feeling == nil ? Color.cardRule : Color.cardInk)
                                .frame(width: 34, height: 34)
                                .background(feeling == nil ? Color.clear : (feeling!.isHeavy ? Color(hex: 0xD9C8EE) : Color.strawberry), in: Circle())
                            Text(day.formatted(.dateTime.weekday(.narrow))).detailsSmall()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry == nil)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)) + (entry.map { ": " + $0.feelings.joined(separator: ", ") } ?? ": no entry"))
                }
            }
            if let reading {
                Text(reading.text.isEmpty ? reading.feelings.joined(separator: " \u{00B7} ") : reading.text).detailsSmall()
            }
        }
    }
}

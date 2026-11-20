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

/// Two minutes before bed: how today felt, breathe with the cloud, close
/// the day. (Writing lives in the Journal.)
struct WindDownView: View {
    private enum Step { case feel, breathe, done }

    @State private var step = Step.feel
    @State private var feelings: [Feeling] = []
    @State private var past = JournalStore.all()
    @State private var reminderOn = GentleNudges.windDownOn
    @State private var reminderTime = Calendar.current.date(bySettingHour: GentleNudges.windDownMinutes / 60, minute: GentleNudges.windDownMinutes % 60, second: 0, of: .now) ?? .now
    @State private var reminderNote: String?
    @State private var reading: JournalEntry?

    var body: some View {
        ClutchPage(title: "wind down", subtitle: "Two quiet minutes before bed.") {
            switch step {
            case .feel: feelCard
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
            PagePrimaryButton(title: "Next", symbol: "arrow.right") { withAnimation { step = .breathe } }
                .disabled(feelings.isEmpty)
                .opacity(feelings.isEmpty ? 0.5 : 1)
        }
    }

    private func finish() {
        JournalStore.add(JournalEntry(date: .now, feelings: feelings.map(\.rawValue), text: ""))
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

/// A private place to write: one gentle prompt (tap for another), the
/// page, and what she's written before.
struct JournalView: View {
    @State private var text = ""
    @State private var promptIndex = Int.random(in: 0..<JournalView.prompts.count)
    @State private var entries = JournalStore.all().filter { !$0.text.isEmpty }
    @State private var saved = false
    @FocusState private var writing: Bool

    static let prompts = [
        "What's on your mind tonight?",
        "One thing from today you want to remember",
        "What made you smile today?",
        "What's weighing on you?",
        "What are you grateful for?",
        "What do you need more of this week?",
    ]

    var body: some View {
        ClutchPage(title: "journal", subtitle: "Just for you. It stays on your phone.") {
            Panel {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { promptIndex = (promptIndex + 1) % Self.prompts.count }
                } label: {
                    HStack(spacing: 8) {
                        Text(Self.prompts[promptIndex])
                            .font(.custom("CormorantGaramond-Light", size: 22))
                            .foregroundStyle(Color.cardInk)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13)).foregroundStyle(Color.cardSoft)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows another prompt")

                TextEditor(text: $text)
                    .focused($writing)
                    .font(.custom("DMSans-Light", size: 16))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 170)
                    .padding(10)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                PagePrimaryButton(title: saved ? "Saved" : "Save", symbol: saved ? "checkmark" : "lock") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saved ? 0.5 : 1)
            }

            if !entries.isEmpty {
                Text("BEFORE").detailsLabel().padding(.leading, 4)
                ForEach(entries.prefix(20)) { entry in
                    Panel(padding: 16) {
                        HStack(spacing: 6) {
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day())).detailsLabel()
                            ForEach(entry.feelings, id: \.self) { name in
                                if let feeling = Feeling(rawValue: name) {
                                    Image(systemName: feeling.symbol).font(.system(size: 11)).foregroundStyle(Color.cardSoft)
                                }
                            }
                        }
                        Text(entry.text).detailsBody().lineLimit(5)
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        JournalStore.add(JournalEntry(date: .now, feelings: [], text: trimmed))
        writing = false
        withAnimation(.easeInOut(duration: 0.3)) {
            entries = JournalStore.all().filter { !$0.text.isEmpty }
            text = ""
            saved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}

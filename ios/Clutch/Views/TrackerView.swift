import SwiftUI

/// Everything the tracker screen reads and the edits it can make. Built
/// from the stored logs every time, like the rest of the engine.
@MainActor
final class TrackerModel: ObservableObject {
    @Published private(set) var engine: CycleEngine
    @Published private(set) var profile: CycleProfile
    let today: Date

    init(now: Date = .now) {
        today = Calendar.current.startOfDay(for: now)
        let profile = CycleProfile.load() ?? CycleProfile()
        self.profile = profile
        engine = CycleEngine(logs: DayLogStore.allLogs(), profile: profile)
    }

    func reload() {
        profile = CycleProfile.load() ?? CycleProfile()
        engine = CycleEngine(logs: DayLogStore.allLogs(), profile: profile)
    }

    var window: CycleEngine.PeriodWindow? { engine.nextPeriodWindow(after: today) }
    var periodDay: Int? { engine.periodDay(for: today) }
    var cycleDay: Int? { engine.cycleDay(for: today) }
    var phase: CycleEngine.Phase? { engine.phase(for: today) }
    var hardPositions: Set<Int> { engine.usualHardPositions }

    /// Days until the likely start, or nil when late / unknown / on period.
    var daysUntil: Int? {
        guard periodDay == nil, let window, !window.isLate else { return nil }
        return max(0, engine.days(from: today, to: window.likely))
    }

    /// How far round the ring today is: cycle day over her usual length.
    var progress: Double {
        guard let cycleDay else { return 0 }
        return min(1, Double(cycleDay) / Double(max(engine.typicalCycleLength, 1)))
    }

    // MARK: Edits

    /// "My period started" on any day, today included.
    func startPeriod(on date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        var log = DayLogStore.loadOrCreate(for: day)
        log.periodStarted = true
        log.periodEnded = false
        if log.flow == nil || log.flow == .noFlow { log.flow = .medium }
        DayLogStore.save(log)
        if day >= (profile.lastPeriodStart.map { Calendar.current.startOfDay(for: $0) } ?? .distantPast) {
            var profile = profile
            profile.lastPeriodStart = day
            profile.save()
        }
        reload()
    }

    /// Undo a start logged on the wrong day.
    func clearStart(on date: Date) {
        guard var log = DayLogStore.load(for: date) else { return }
        log.periodStarted = false
        if log.flow?.isBleeding == true { log.flow = nil }
        DayLogStore.save(log)
        if let last = profile.lastPeriodStart, Calendar.current.isDate(last, inSameDayAs: date) {
            var profile = profile
            profile.lastPeriodStart = engine.periodStarts.last { !Calendar.current.isDate($0, inSameDayAs: date) }
            profile.save()
        }
        reload()
    }

    func endPeriod(on date: Date) {
        var log = DayLogStore.loadOrCreate(for: date)
        log.periodEnded = true
        log.flow = .noFlow
        DayLogStore.save(log)
        reload()
    }

    func isStart(_ date: Date) -> Bool {
        engine.periodStarts.contains { Calendar.current.isDate($0, inSameDayAs: date) }
    }

    // MARK: Calendar

    enum DayMark { case period, predicted, window, none }

    func mark(for date: Date) -> DayMark {
        let day = Calendar.current.startOfDay(for: date)
        if day <= today {
            if engine.log(on: day)?.flow?.isBleeding == true || engine.isOnPeriod(day) { return .period }
            return .none
        }
        // The rest of a period that's running now.
        if periodDay != nil, let start = engine.cycleStart(for: today),
           day <= engine.day(engine.usualPeriodLength - 1, from: start) {
            return .predicted
        }
        guard let window, !window.isLate else { return .none }
        let likelyEnd = engine.day(engine.usualPeriodLength - 1, from: window.likely)
        if day >= window.likely && day <= likelyEnd { return .predicted }
        if day >= window.earliest && day <= window.latest { return .window }
        return .none
    }

    func isUsuallyHard(_ date: Date) -> Bool {
        guard let position = engine.position(for: date) else { return false }
        return hardPositions.contains(position)
    }
}

extension CycleEngine.Phase {
    var symbol: String {
        switch self {
        case .period: "drop.fill"
        case .rising: "leaf.fill"
        case .strongest: "sun.max.fill"
        case .windingDown: "moon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .period: Color(hex: 0xE9A6BC)
        case .rising: Color(hex: 0xCAD5A6)
        case .strongest: Color(hex: 0xA9B47A)
        case .windingDown: Color(hex: 0xD9C8EE)
        }
    }
}

/// The tracker: one wheel that shows the whole cycle at a glance, three
/// buttons, and the month. Everything else is a tap away.
struct TrackerView: View {
    @StateObject private var model = TrackerModel()
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var editing: Date?
    @State private var pickingStart = false
    @State private var pickedStart = Date.now
    @State private var headsUp = GentleNudges.hardDayOn
    @State private var note: String?
    @State private var importing = false

    var body: some View {
        ClutchPage(title: "your cycle", subtitle: subtitle) {
            CycleWheel(model: model)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            if let window = model.window, !window.isLate, model.periodDay == nil {
                Label("Likely \(DetailsData.range(window.earliest, window.latest))", systemImage: "drop")
                    .font(.custom("DMSans-Regular", size: 15))
                    .foregroundStyle(Color.cardInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.cream, in: Capsule())
                    .frame(maxWidth: .infinity)
            }

            actions
            if let note { Text(note).detailsSmall().frame(maxWidth: .infinity) }

            // New to Clutch but not to tracking: bring the history in.
            if model.engine.plausibleCycles.count < 2 && !PeriodImport.hasImported(.clue) && !HealthSync.shared.isConnected {
                Button { importing = true } label: {
                    HStack(spacing: 12) {
                        AuraTile(palette: AuraTile.hints[2], symbol: "square.and.arrow.down").frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Used Clue or another app?").font(.custom("DMSans-Regular", size: 15)).foregroundStyle(Color.cardInk)
                            Text("Bring your history for sharper predictions").font(.custom("DMSans-Light", size: 12)).foregroundStyle(Color.cardSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.cardSoft)
                    }
                    .padding(14)
                    .background(Color.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color(hex: 0x4A3328).opacity(0.08), radius: 14, y: 7)
                }
                .buttonStyle(.plain)
            }

            calendar
        }
        .confirmationDialog(editing.map { $0.formatted(.dateTime.weekday(.wide).month().day()) } ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), titleVisibility: .visible) {
            if let day = editing {
                if model.isStart(day) {
                    Button("This wasn't a period start", role: .destructive) { model.clearStart(on: day) }
                } else if day <= model.today {
                    Button("My period started this day") { model.startPeriod(on: day) }
                }
                if day <= model.today, model.engine.isOnPeriod(day) {
                    Button("My period ended this day") { model.endPeriod(on: day) }
                }
            }
        }
        .sheet(isPresented: $importing, onDismiss: model.reload) { ImportView() }
        .sheet(isPresented: $pickingStart) {
            NavigationStack {
                DatePicker("Started on", selection: $pickedStart, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color.matcha)
                    .padding()
                    .navigationTitle("When did it start?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pickingStart = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { model.startPeriod(on: pickedStart); pickingStart = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var subtitle: String {
        if let day = model.periodDay { return "Period, day \(day)" }
        if model.window?.isLate == true { return "A little later than usual. That happens." }
        if let phase = model.phase, let day = model.cycleDay { return "Day \(day) \u{00B7} \(phase.title.lowercased())" }
        return "Tap the drop when your period starts"
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            if model.periodDay == nil {
                Button { model.startPeriod(on: .now) } label: {
                    IconBubble(symbol: "drop.fill", title: "Started today", filled: true)
                }
            } else {
                Button { model.endPeriod(on: .now) } label: {
                    IconBubble(symbol: "drop", title: "Ended today", filled: true)
                }
            }
            Button { pickedStart = .now; pickingStart = true } label: {
                IconBubble(symbol: "calendar.badge.plus", title: "Another day")
            }
            Button { importing = true } label: {
                IconBubble(symbol: "square.and.arrow.down", title: "Import")
            }
            .accessibilityHint("Bring in your history from Clue or Apple Health")
            Button { headsUp.toggle(); setHeadsUp(headsUp) } label: {
                IconBubble(symbol: headsUp ? "bell.fill" : "bell", title: headsUp ? "Heads-up on" : "Heads-up", filled: headsUp)
            }
            .accessibilityHint("A note the evening before your usually harder days")
        }
        .buttonStyle(.plain)
    }

    private func setHeadsUp(_ on: Bool) {
        Task {
            if on {
                let ok = await LocalReminders.requestPermission()
                GentleNudges.hardDayOn = ok
                headsUp = ok
                note = ok
                    ? (model.hardPositions.isEmpty ? "I'll warn you once I've spotted your harder days." : "I'll warn you the evening before a harder day.")
                    : "Turn on notifications for Clutch in Settings first."
                WidgetBridge.refresh()
            } else {
                GentleNudges.hardDayOn = false
                LocalReminders.cancel(id: GentleNudges.hardDayID)
                note = nil
            }
        }
    }

    // MARK: Calendar

    private var calendar: some View {
        Panel {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.custom("CormorantGaramond-Light", size: 22))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                    .accessibilityLabel("Next month")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.cardInk)
            .buttonStyle(.plain)

            let days = monthDays
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(Calendar.current.veryShortStandaloneWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).detailsSmall()
                }
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] { dayCell(day) } else { Color.clear.frame(height: 34) }
                }
            }

            HStack(spacing: 14) {
                legendItem(Circle().fill(Color(hex: 0xE9A6BC)), "period")
                legendItem(Circle().strokeBorder(Color(hex: 0xE9A6BC), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])), "likely")
                legendItem(Circle().fill(Color.matcha.opacity(0.6)).frame(width: 5, height: 5), "harder")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func legendItem(_ shape: some View, _ label: String) -> some View {
        HStack(spacing: 4) {
            shape.frame(width: 10, height: 10)
            Text(label).font(.custom("DMSans-Light", size: 11)).foregroundStyle(Color.cardSoft)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let mark = model.mark(for: day)
        let isToday = Calendar.current.isDate(day, inSameDayAs: model.today)
        let pink = Color(hex: 0xE9A6BC)
        return Button { editing = day } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.custom(isToday ? "DMSans-Regular" : "DMSans-Light", size: 14))
                    .foregroundStyle(Color.cardInk)
                    .frame(width: 32, height: 32)
                    .background {
                        switch mark {
                        case .period: Circle().fill(pink)
                        case .predicted: Circle().fill(pink.opacity(0.25)).overlay(Circle().strokeBorder(pink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                        case .window: Circle().strokeBorder(pink.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        case .none: EmptyView()
                        }
                    }
                    .overlay { if isToday { Circle().strokeBorder(Color.cardInk, lineWidth: 1.2) } }
                Circle().fill(Color.matcha.opacity(model.isUsuallyHard(day) ? 0.6 : 0)).frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (mark == .period ? ", period" : mark == .predicted ? ", likely period" : ""))
        .accessibilityHint("Mark a period start or end")
    }

    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }

    private func shiftMonth(_ by: Int) {
        month = Calendar.current.date(byAdding: .month, value: by, to: month) ?? month
    }
}

/// The whole cycle as a wheel: one colored arc per phase with its icon on
/// it, a marker for today, and the countdown in the middle with the cloud.
struct CycleWheel: View {
    @ObservedObject var model: TrackerModel
    var diameter: CGFloat = 250
    private let line: CGFloat = 26

    var body: some View {
        let length = Double(max(model.engine.typicalCycleLength, 1))
        let spans = model.engine.phaseSpans
        let known = model.cycleDay != nil
        let radius = diameter / 2

        ZStack {
            Circle().stroke(Color.cream, lineWidth: line + 8)
            ForEach(spans, id: \.phase) { span in
                Circle()
                    .trim(from: Double(span.firstDay - 1) / length + 0.003, to: Double(span.lastDay) / length - 0.003)
                    .stroke(span.phase.tint.opacity(known ? (model.phase == span.phase ? 1 : 0.55) : 0.3), style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Image(systemName: span.phase.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(point(at: (Double(span.firstDay - 1) + Double(span.lastDay)) / 2 / length, radius: radius))
                    .accessibilityHidden(true)
            }
            if known {
                Circle()
                    .fill(Color.cardInk)
                    .frame(width: line + 6, height: line + 6)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .overlay(Text("today").font(.custom("DMSans-Regular", size: 7)).foregroundStyle(.white))
                    .offset(point(at: model.progress == 1 ? 0.998 : max(0.01, model.progress - 0.5 / length), radius: radius))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            VStack(spacing: 2) {
                FuzzyCloud(face: model.periodDay != nil ? .soft : .happy)
                    .frame(width: 70)
                Text(centerNumber)
                    .font(.custom("InterTight-SemiBold", size: 46))
                    .tracking(-1.5)
                    .foregroundStyle(Color.cardInk)
                Text(centerCaption)
                    .font(.custom("DMSans-Light", size: 12))
                    .foregroundStyle(Color.cardSoft)
            }
        }
        .frame(width: diameter, height: diameter)
        .padding(line / 2 + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centerNumber) \(centerCaption)" + (model.phase.map { ", \($0.title) phase" } ?? ""))
    }

    private func point(at fraction: Double, radius: CGFloat) -> CGSize {
        let angle = fraction * 2 * .pi - .pi / 2
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    private var centerNumber: String {
        if let day = model.periodDay { return "\(day)" }
        if let days = model.daysUntil { return "\(days)" }
        if model.window?.isLate == true { return "soon" }
        return "\u{2014}"
    }

    private var centerCaption: String {
        if model.periodDay != nil { return "period day" }
        if let days = model.daysUntil { return days == 1 ? "day to go" : "days to go" }
        if model.window?.isLate == true { return "any day now" }
        return "log a period to start"
    }
}

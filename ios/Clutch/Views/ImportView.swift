import SwiftUI
import UniformTypeIdentifiers

/// "Bring your history": Apple Health (one tap, keeps syncing) or a Clue
/// export file (one-off). Ends on what Clutch now knows about her cycle.
struct ImportView: View {
    /// Called after a successful import, e.g. so onboarding can fill in
    /// her last period for her.
    var onImported: ((PeriodImport.Summary) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var health = HealthSync.shared
    @State private var pickingFile = false
    @State private var working = false
    @State private var result: PeriodImport.Summary?
    @State private var source: ImportSource?
    @State private var problem: String?
    /// Clue's zip, waiting for its password.
    @State private var lockedZip: Data?
    @State private var password = ""

    var body: some View {
        ClutchPage(title: "bring your history", subtitle: "Every past cycle makes your predictions sharper.") {
            if let result, let source {
                resultView(result, source: source)
            } else {
                sourceTile(
                    symbol: "heart",
                    palette: [Color(hex: 0xFFFBF0), Color(hex: 0xFDDCE6), Color(hex: 0xE7DCF6)],
                    title: "Apple Health",
                    detail: health.isConnected ? "Connected \u{00B7} keeps syncing" : "Clue, Flo & more \u{00B7} keeps syncing",
                    done: health.isConnected,
                    action: connectHealth
                )
                .opacity(HealthSync.isAvailable ? 1 : 0.4)
                .disabled(!HealthSync.isAvailable || working)

                sourceTile(
                    symbol: "doc",
                    palette: [Color(hex: 0xFFFFFF), Color(hex: 0xF5DFF9), Color(hex: 0xE9D5F7)],
                    title: "Clue export file",
                    detail: "One-time import",
                    done: PeriodImport.hasImported(.clue),
                    action: { pickingFile = true }
                )
                .disabled(working)

                clueSteps

                if working { ProgressView().tint(Color.cardInk).frame(maxWidth: .infinity) }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.custom("DMSans-Light", size: 13))
                        .foregroundStyle(Color.cardInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label("Stays on your phone. Read-only.", systemImage: "lock.fill")
                    .font(.custom("DMSans-Light", size: 12))
                    .foregroundStyle(Color.cardSoft)
                    .frame(maxWidth: .infinity)
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.zip, .folder, .json, .commaSeparatedText, .plainText, .data]) { picked in
            if case let .success(url) = picked { importFile(url) }
        }
        .alert("Clue's password", isPresented: Binding(get: { lockedZip != nil }, set: { if !$0 { lockedZip = nil } })) {
            SecureField("Password", text: $password)
            Button("Import") {
                if let zip = lockedZip { importData(zip, password: password) }
                lockedZip = nil
            }
            Button("Cancel", role: .cancel) { lockedZip = nil }
        } message: {
            Text("Clue showed you a password when you asked to download your data.")
        }
    }

    // MARK: Sources

    private func sourceTile(symbol: String, palette: [Color], title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                AuraTile(palette: palette, symbol: symbol)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.custom("DMSans-Regular", size: 17)).foregroundStyle(Color.cardInk)
                    Text(detail).font(.custom("DMSans-Light", size: 13)).foregroundStyle(Color.cardSoft)
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: done ? 20 : 14, weight: .medium))
                    .foregroundStyle(done ? Color.matcha : Color.cardSoft)
            }
            .padding(16)
            .background(Color.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: 0x4A3328).opacity(0.08), radius: 18, y: 9)
        }
        .buttonStyle(.plain)
    }

    /// How to get the file out of Clue, as three pictures.
    private var clueSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GETTING YOUR CLUE FILE").detailsLabel()
            HStack(alignment: .top, spacing: 6) {
                step("1", "gearshape", "Clue \u{203A} Settings \u{203A} Download my data")
                step("2", "envelope.open", "Save the zip from Clue's email")
                step("3", "doc.zipper", "Pick it here, then type Clue's password")
            }
        }
        .padding(.top, 4)
    }

    private func step(_ number: String, _ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.cardInk)
                .frame(width: 46, height: 46)
                .background(Color.cream, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Text(number)
                        .font(.custom("DMSans-Regular", size: 10))
                        .foregroundStyle(Color.cardInk)
                        .frame(width: 17, height: 17)
                        .background(Color.strawberry, in: Circle())
                }
            Text(text)
                .font(.custom("DMSans-Light", size: 11.5))
                .foregroundStyle(Color.cardInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Result

    private func resultView(_ summary: PeriodImport.Summary, source: ImportSource) -> some View {
        VStack(spacing: 18) {
            FuzzyCloud(face: .happy).frame(width: 120)

            VStack(spacing: 2) {
                Text("\(summary.cycles)")
                    .font(.custom("InterTight-SemiBold", size: 56))
                    .tracking(-2)
                    .foregroundStyle(Color.cardInk)
                Text(summary.cycles == 1 ? "cycle from \(source.title)" : "cycles from \(source.title)")
                    .font(.custom("DMSans-Light", size: 14))
                    .foregroundStyle(Color.cardSoft)
            }

            if summary.cycleLengths.count >= 2 {
                CycleLengthBars(lengths: Array(summary.cycleLengths.suffix(14)))
                    .frame(height: 110)
            }

            HStack(spacing: 8) {
                if let average = summary.averageLength { statChip("arrow.triangle.2.circlepath", "\(average)-day cycles") }
                if let since = summary.since { statChip("calendar", "since \(since.formatted(.dateTime.month(.abbreviated).year()))") }
            }

            PagePrimaryButton(title: "Done", symbol: "checkmark") { dismiss() }

            Button("Undo import") {
                PeriodImport.undo(source)
                if source == .health { health.disconnect() }
                withAnimation { result = nil; self.source = nil }
            }
            .buttonStyle(.plain)
            .font(.custom("DMSans-Light", size: 13))
            .foregroundStyle(Color.cardSoft)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private func statChip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.custom("DMSans-Regular", size: 13))
            .foregroundStyle(Color.cardInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.cream, in: Capsule())
    }

    // MARK: Actions

    private func connectHealth() {
        problem = nil
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await health.connect()
                let summary = PeriodImport.summary(daysAdded: 0)
                guard PeriodImport.hasImported(.health) || summary.periodDays > 0 else {
                    problem = "Nothing found in Health yet. In Clue, turn on Apple Health in settings, then try again."
                    return
                }
                finish(summary, from: .health)
            } catch {
                problem = "Couldn't reach Apple Health. Try again in a moment."
            }
        }
    }

    private func importFile(_ url: URL) {
        problem = nil
        do {
            importData(try ClueImport.readPicked(url), password: nil)
        } catch {
            problem = "Couldn't open that (\(error.localizedDescription)). Pick the zip from Clue's email."
        }
    }

    private func importData(_ data: Data, password: String?) {
        problem = nil
        do {
            let days = try ClueImport.days(from: data, password: password)
            let added = PeriodImport.merge(days, source: .clue)
            password_reset()
            finish(PeriodImport.summary(daysAdded: added), from: .clue)
        } catch ZipReader.Failure.needsPassword {
            password_reset()
            lockedZip = data
        } catch ZipReader.Failure.wrongPassword {
            problem = "That password didn't work. It's the one Clue showed when you asked for your data."
            password_reset()
            lockedZip = data
        } catch ClueImport.Failure.noPeriodData {
            problem = "That file doesn't have any period days in it."
        } catch {
            // The reason, so a beta tester can tell us what went wrong.
            problem = "Couldn't read that (\(String(describing: error))). Pick the zip from Clue's email."
        }
    }

    private func password_reset() { password = "" }

    private func finish(_ summary: PeriodImport.Summary, from source: ImportSource) {
        WidgetBridge.refresh()
        withAnimation(.easeInOut(duration: 0.3)) {
            self.source = source
            result = summary
        }
        onImported?(summary)
    }
}

/// Her cycle lengths as soft bars, with her average as a dashed line.
struct CycleLengthBars: View {
    let lengths: [Int]

    var body: some View {
        let top = Double((lengths.max() ?? 30) + 3)
        let floor = Double(max((lengths.min() ?? 20) - 6, 0))
        let average = Double(lengths.reduce(0, +)) / Double(max(lengths.count, 1))
        GeometryReader { geo in
            let height = geo.size.height - 16
            let y = { (value: Double) in height * (1 - (value - floor) / (top - floor)) }
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(lengths.enumerated()), id: \.offset) { _, length in
                        VStack(spacing: 3) {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(LinearGradient(colors: [Color(hex: 0xF4B6C8), Color(hex: 0xE58DAA)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(6, height - y(Double(length))))
                            Text("\(length)")
                                .font(.custom("DMSans-Light", size: 9))
                                .foregroundStyle(Color.cardSoft)
                                .frame(height: 13)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y(average)))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y(average)))
                }
                .stroke(Color.cardInk.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle lengths: " + lengths.map(String.init).joined(separator: ", ") + " days")
    }
}

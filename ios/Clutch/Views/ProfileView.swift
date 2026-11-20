import AuthenticationServices
import SwiftUI

/// Tap her name on the home screen: her scribble, what Clutch knows about
/// her, where her history comes from, and her account.
struct ProfileView: View {
    let signature: UIImage?

    @StateObject private var account = AccountService.shared
    @StateObject private var health = HealthSync.shared
    @State private var importing = false
    @State private var confirmDelete = false
    @State private var data = DetailsData.load()

    var body: some View {
        ClutchPage(title: "you", subtitle: data.dayLabel) {
            nameCard
            detailsCard
            historyCard
            accountCard
        }
        .sheet(isPresented: $importing, onDismiss: { data = DetailsData.load() }) { ImportView() }
        .confirmationDialog("Delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete my account and data", role: .destructive) {
                Task { await account.deleteEverything() }
            }
        } message: {
            Text("This removes your account and every log, bouquet and journal entry on this phone. It can't be undone.")
        }
    }

    // MARK: Cards

    private var nameCard: some View {
        Panel(padding: 20) {
            Group {
                if let signature {
                    Image(uiImage: signature).resizable().scaledToFit()
                } else {
                    Text("your name")
                        .font(.custom("Fredoka-SemiBold", size: 36))
                        .tracking(-1.2)
                        .foregroundStyle(Color.cardSoft)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 120)
            if let name = account.state.name, !name.isEmpty {
                Text(name).detailsSmall().frame(maxWidth: .infinity)
            }
        }
    }

    private var detailsCard: some View {
        let engine = data.engine
        let profile = data.profile
        return Panel(padding: 18) {
            Text("YOUR DETAILS").detailsLabel()
            row("person", 0, "Age", profile.ageRange?.title ?? "Not set")
            row("arrow.triangle.2.circlepath", 1, "Cycle", "\(engine.typicalCycleLength) days")
            row("drop", 1, "Period", "\(engine.usualPeriodLength) days")
            row("calendar", 2, "Last period", engine.periodStarts.last.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Not logged yet")
            row("pills", 3, "Birth control", profile.birthControl?.title ?? "Not set")
            row("number", 4, "Cycles logged", "\(engine.plausibleCycles.count)")
        }
    }

    private var historyCard: some View {
        Panel(padding: 18) {
            Text("YOUR HISTORY").detailsLabel()
            Button { importing = true } label: {
                rowContent("heart", 1, "Apple Health", health.isConnected ? "Connected" : "Connect")
            }
            .buttonStyle(.plain)
            Button { importing = true } label: {
                rowContent("doc", 2, "Clue", PeriodImport.hasImported(.clue) ? "Imported" : "Import")
            }
            .buttonStyle(.plain)
        }
    }

    private var accountCard: some View {
        Panel(padding: 18) {
            Text("ACCOUNT").detailsLabel()
            if account.state.signedInWithApple {
                rowContent("apple.logo", 0, "Signed in with Apple", account.state.email ?? "")
                Button("Sign out") { account.signOut() }
                    .buttonStyle(.plain)
                    .font(.custom("DMSans-Regular", size: 15))
                    .foregroundStyle(Color.cardInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.6), in: Capsule())
            } else {
                Text("Sign in so you can get your account back on a new phone. Your logs stay private.")
                    .detailsSmall()
                SignInWithAppleButton(.signIn) { request in
                    account.prepare(request)
                } onCompletion: { result in
                    account.complete(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(Capsule())
            }
            if let problem = account.problem {
                Text(problem).detailsSmall()
            }
            Button("Delete my account and data", role: .destructive) { confirmDelete = true }
                .buttonStyle(.plain)
                .font(.custom("DMSans-Light", size: 13))
                .foregroundStyle(Color(hex: 0xB0405F))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    // MARK: Rows

    private func row(_ symbol: String, _ palette: Int, _ title: String, _ value: String) -> some View {
        rowContent(symbol, palette, title, value, chevron: false)
    }

    private func rowContent(_ symbol: String, _ palette: Int, _ title: String, _ value: String, chevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            AuraTile(palette: AuraTile.hints[palette], symbol: symbol).frame(width: 36, height: 36)
            Text(title).font(.custom("DMSans-Regular", size: 15)).foregroundStyle(Color.cardInk)
            Spacer(minLength: 8)
            Text(value).font(.custom("DMSans-Light", size: 14)).foregroundStyle(Color.cardSoft).lineLimit(1)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.cardSoft)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

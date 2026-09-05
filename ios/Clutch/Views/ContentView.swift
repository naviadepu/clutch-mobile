import SwiftUI

struct ContentView: View {
    @State private var check = ConnectivityCheck()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("Clutch")
                    .font(.largeTitle.bold())
                Text("Beta")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())

                statusCard

                Button {
                    Task { await check.run() }
                } label: {
                    Text(check.state == .running ? "Checking…" : "Run backend check")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(check.state == .running)
            }
            .padding()
            .navigationTitle("Dev Console")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if case .idle = check.state { await check.run() }
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(check.targetDescription, systemImage: "server.rack")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch check.state {
            case .idle:
                Text("Not checked yet.")
            case .running:
                ProgressView("Contacting backend…")
            case let .ok(uid, doc):
                Label("Connected", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Signed in as \(uid.prefix(8))…")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Firestore round-trip doc: \(doc.prefix(8))…")
                    .font(.footnote).foregroundStyle(.secondary)
            case let .failed(message):
                Label("Failed", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}

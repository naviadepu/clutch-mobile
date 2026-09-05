import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Small end-to-end smoke test used by `ContentView` to confirm the app can
/// reach whichever backend it is configured for (local emulators in DEBUG).
@MainActor
@Observable
final class ConnectivityCheck {

    enum State: Equatable {
        case idle
        case running
        case ok(uid: String, roundTripDoc: String)
        case failed(String)
    }

    private(set) var state: State = .idle

    var targetDescription: String {
        FirebaseBootstrap.useEmulators
            ? "Local emulators (\(FirebaseBootstrap.emulatorHost))"
            : "Production Firebase"
    }

    func run() async {
        state = .running
        do {
            let user = try await signIn()
            let doc = try await roundTrip(uid: user.uid)
            state = .ok(uid: user.uid, roundTripDoc: doc)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func signIn() async throws -> User {
        if let current = Auth.auth().currentUser { return current }
        return try await Auth.auth().signInAnonymously().user
    }

    private func roundTrip(uid: String) async throws -> String {
        let ref = Firestore.firestore()
            .collection("connectivity_checks")
            .document(uid)

        let payload: [String: Any] = [
            "uid": uid,
            "checkedAt": FieldValue.serverTimestamp(),
            "platform": "ios",
        ]
        try await ref.setData(payload, merge: true)

        let snapshot = try await ref.getDocument()
        guard snapshot.exists else {
            throw NSError(
                domain: "ConnectivityCheck",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Wrote a document but could not read it back."]
            )
        }
        return snapshot.documentID
    }
}

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation

/// Her account. Everyone starts signed in anonymously (it's what lets her
/// report a stocked or empty spot). Signing in with Apple upgrades that same
/// account, keeping its id, so she can get her account back on a new phone.
/// Signing out returns to a fresh anonymous account; her logs stay on this
/// phone. Deleting removes the account and everything Clutch keeps here.
@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    struct State: Equatable {
        var signedInWithApple = false
        var email: String?
        var name: String?
    }

    @Published private(set) var state = State()
    @Published var problem: String?

    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    private init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.update(user) }
        }
        update(Auth.auth().currentUser)
    }

    private func update(_ user: User?) {
        let apple = user?.providerData.first { $0.providerID == "apple.com" }
        state = State(
            signedInWithApple: apple != nil,
            email: apple?.email ?? user?.email,
            name: apple?.displayName ?? user?.displayName
        )
    }

    // MARK: Sign in with Apple

    /// Sets up the Apple request: name and email, and a hashed nonce so the
    /// returned token can't be replayed.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) {
        problem = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                problem = "Couldn't sign in with Apple. Try again in a moment."
            }
        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = apple.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                  let nonce = currentNonce else {
                problem = "Couldn't sign in with Apple. Try again in a moment."
                return
            }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
            Task { await signIn(with: credential) }
        }
    }

    /// Upgrades the anonymous account when there is one, so nothing tied to
    /// it is lost. If this Apple ID already has a Clutch account (say, from
    /// an old phone), signs into that one instead.
    private func signIn(with credential: AuthCredential) async {
        do {
            if let user = Auth.auth().currentUser, user.isAnonymous {
                do {
                    _ = try await user.link(with: credential)
                } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                    let existing = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
                    _ = try await Auth.auth().signIn(with: existing)
                }
            } else {
                _ = try await Auth.auth().signIn(with: credential)
            }
            update(Auth.auth().currentUser)
        } catch {
            problem = "Couldn't sign in right now. Check your connection and try again."
        }
    }

    // MARK: Sign out and delete

    /// Back to a fresh anonymous account. Her logs stay on this phone.
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            problem = "Couldn't sign out. Try again."
            return
        }
        Task { _ = try? await Auth.auth().signInAnonymously() }
    }

    /// Deletes the account and everything Clutch keeps on this phone, then
    /// starts over from the first screen.
    func deleteEverything() async {
        if let user = Auth.auth().currentUser {
            try? await user.delete()
        }
        try? Auth.auth().signOut()
        LocalData.eraseAll()
        AppRouter.shared.restart()
    }

    // MARK: Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Everything Clutch keeps on the phone, for "Delete my data".
@MainActor
enum LocalData {
    static func eraseAll() {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        UserDefaults(suiteName: ClutchShared.appGroup)?.removePersistentDomain(forName: ClutchShared.appGroup)
        SignatureStore.save(nil)
        LocalReminders.cancel(id: GentleNudges.hardDayID)
        LocalReminders.cancel(id: GentleNudges.windDownID)
        HealthSync.shared.disconnect()
        WidgetBridge.refresh()
    }
}

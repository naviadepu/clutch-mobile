import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Central Firebase setup. In DEBUG builds the app points at the local
/// Firebase Emulator Suite (`firebase emulators:start`) unless the
/// `USE_FIREBASE_EMULATORS` environment variable is explicitly set to "0".
enum FirebaseBootstrap {

    /// Host the simulator can reach the developer machine on.
    static let emulatorHost = "127.0.0.1"
    static let authEmulatorPort = 9099
    static let firestoreEmulatorPort = 8080

    static var useEmulators: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATORS"] != "0"
        #else
        return false
        #endif
    }

    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()

        guard useEmulators else {
            print("🔥 Firebase configured against production project.")
            return
        }

        Auth.auth().useEmulator(withHost: emulatorHost, port: authEmulatorPort)

        let settings = Firestore.firestore().settings
        settings.host = "\(emulatorHost):\(firestoreEmulatorPort)"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings

        print("🔥 Firebase configured against LOCAL emulators "
              + "(auth :\(authEmulatorPort), firestore :\(firestoreEmulatorPort)). "
              + "Emulator UI: http://\(emulatorHost):4000")
    }
}

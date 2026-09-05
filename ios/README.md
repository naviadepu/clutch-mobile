# Clutch iOS (beta)

Native SwiftUI rewrite of the Clutch app. Talks to Firebase (Auth + Firestore).
In `DEBUG` builds it points at the **Firebase Local Emulator Suite** on your
machine, so you can develop with zero cloud setup.

## Prerequisites

| Tool | Install | Notes |
|------|---------|-------|
| Xcode 26+ | App Store | Then: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and `sudo xcodebuild -license accept` |
| XcodeGen | `brew install xcodegen` | Generates `Clutch.xcodeproj` from `project.yml` |
| Firebase CLI | `brew install firebase-cli` | Runs the local emulators |
| Java 17+ | `brew install openjdk` | Required by the Firestore emulator |

Run `make doctor` from the repo root to check all of the above.

> The project file (`Clutch.xcodeproj`) is **generated** and git-ignored.
> Edit `project.yml` instead, then run `make project`.

## First-time setup

```bash
# from repo root
make deps        # generates the project + downloads the Firebase SDK
```

## Day-to-day

Two terminals:

```bash
# Terminal 1 — local backend
make emulators              # auth :9099, firestore :8080, UI http://localhost:4000
# or: make emulators-persist   (keeps data between runs in ./emulator-data)

# Terminal 2 — the app
make app                   # build + install + launch on the iPhone 17 simulator
```

Or just open `ios/Clutch.xcodeproj` in Xcode and hit ▶. The `Clutch` scheme
already sets `USE_FIREBASE_EMULATORS=1`.

The first screen ("Dev Console") runs an anonymous sign-in + a Firestore
read/write round-trip and shows whether the backend is reachable. When the
emulators are running you should see **Connected**; check the writes at
<http://localhost:4000/firestore>.

## Tests

```bash
make test
```

## How the emulator wiring works

`Clutch/Services/FirebaseBootstrap.swift` calls `FirebaseApp.configure()` and,
when `useEmulators` is true, redirects Auth and Firestore to `127.0.0.1`.
`useEmulators` is `true` in `DEBUG` unless `USE_FIREBASE_EMULATORS=0`.

`Clutch/Resources/GoogleService-Info.plist` is a **placeholder** with
`PROJECT_ID = demo-clutch`. The `demo-` prefix is what lets the emulators run
fully offline. Before shipping a build that hits production, drop the real
`GoogleService-Info.plist` from the Firebase console in its place (and it will
be git-ignored via `*.plist.prod` conventions — store secrets outside git).

## Adding dependencies

Add to `packages:` / `dependencies:` in `ios/project.yml`, then `make deps`.

# Clutch Mobile 💌

> 1st Place, HackHers (MLH) — A peer-to-peer menstrual product sharing app for college campuses.

Clutch is a community-powered safety net ensuring no student is caught without essential personal care items. Built with React Native and Expo.

---

## The Problem

Needing a tampon or pad with no way to get one quickly. Campus vending machines are unreliable. Pharmacies are far. Clutch fixes that.

---

## Features

### Give & Request Flow
- One-tap item requests with cute icons
- Uber-style matching connects nearest giver to requester
- In-app chat to coordinate pickup
- Givers earn rewards for every donation

### Live Campus Map
- Real-time pinpoints of nearby givers
- Closest match highlighted automatically
- Built with react-native-maps and Firebase

### AI Recommendations
- Tells givers what items are most needed nearby
- Alerts requesters when items are available close by
- Powered by OpenAI and live Firebase data

---

## Tech Stack

- **Framework:** React Native + Expo
- **Navigation:** Expo Router
- **Database:** Firebase Firestore
- **Auth:** Firebase Auth
- **AI:** OpenAI API
- **Maps:** react-native-maps

---

## Getting Started
```bash
git clone https://github.com/naviadepu/clutch-mobile.git
cd clutch-mobile
npm install
npx expo start
```

---

## Native iOS beta (Swift)

A native SwiftUI rewrite lives in [`ios/`](ios/README.md). It uses the same
Firebase backend and runs against the local Firebase Emulator Suite for
development. Quick start:

```bash
make doctor   # check toolchain
make deps     # generate project + fetch Firebase SDK
make emulators   # terminal 1: local backend
make app          # terminal 2: build + run on the simulator
```

## Links

- Web app: [clutch-care.vercel.app](https://clutch-care.vercel.app)

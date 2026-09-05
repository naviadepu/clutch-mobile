#!/usr/bin/env node
/**
 * Seeds the local Firestore emulator with a bit of sample Clutch data so the
 * app has something to show. Safe to run repeatedly.
 *
 *   1. start the emulators:  make emulators
 *   2. in another terminal:  node scripts/seed-emulator.mjs
 */
import { initializeApp } from "firebase/app";
import {
  getFirestore,
  connectFirestoreEmulator,
  doc,
  setDoc,
  serverTimestamp,
} from "firebase/firestore";

const app = initializeApp({ projectId: "demo-clutch" });
const db = getFirestore(app);
connectFirestoreEmulator(db, "127.0.0.1", 8080);

const givers = [
  { id: "g1", name: "Maya",  items: ["tampon", "pad"],  lat: 40.5008, lng: -74.4474 },
  { id: "g2", name: "Priya", items: ["pad", "liner"],   lat: 40.5231, lng: -74.4390 },
  { id: "g3", name: "Sam",   items: ["tampon"],          lat: 40.5142, lng: -74.4629 },
];

for (const g of givers) {
  await setDoc(doc(db, "givers", g.id), {
    name: g.name,
    availableItems: g.items,
    location: { latitude: g.lat, longitude: g.lng },
    active: true,
    updatedAt: serverTimestamp(),
  });
  console.log(`seeded giver ${g.name}`);
}

console.log("done — check http://127.0.0.1:4000/firestore");
process.exit(0);

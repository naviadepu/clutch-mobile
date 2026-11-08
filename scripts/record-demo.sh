#!/usr/bin/env bash
# Records the demo video: runs the DemoWalkthrough UI test on a fresh
# simulator install and records the screen between the test's start and
# stop markers. Usage: scripts/record-demo.sh [output.mp4]
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/clutch-demo.mp4}"
SIM="${DEMO_SIM:-iPhone 17 Pro}"
MARKERS="$(mktemp -d)"

UDID=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
# Clean status bar and a fresh install, so onboarding starts from the top.
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
xcrun simctl uninstall "$UDID" com.love.clutch 2>/dev/null || true
# Georgia State, so "sort by closest" on the Request screen means something.
xcrun simctl location "$UDID" set 33.7531,-84.3853

(
  while [ ! -f "$MARKERS/start" ]; do sleep 0.2; done
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT" &
  REC=$!
  while [ ! -f "$MARKERS/stop" ]; do sleep 0.2; done
  sleep 1
  kill -INT $REC
  wait $REC
) &
WATCHER=$!

cd "$ROOT/ios"
TEST_RUNNER_DEMO_MARKER_DIR="$MARKERS" xcodebuild -project Clutch.xcodeproj -scheme Clutch \
  -destination "id=$UDID" -only-testing:ClutchUITests/DemoWalkthrough test -quiet || true
touch "$MARKERS/stop"
wait $WATCHER
xcrun simctl status_bar "$UDID" clear
echo "Saved $OUT"

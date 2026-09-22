#!/usr/bin/env bash
# Build SpeedAlert and run it in the iOS Simulator, then capture a screenshot.
#   ./run_sim.sh
# Resolves the simulator by UDID (device *names* have odd whitespace for simctl).
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found: brew install xcodegen"; exit 1
fi

echo "==> generating Xcode project"
xcodegen generate

UDID="${SIM_UDID:-$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/{print $2; exit}')}"
echo "==> simulator UDID: ${UDID:-<none>}"
[ -n "${UDID:-}" ] || { echo "no iPhone simulator available"; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

echo "==> building for simulator"
xcodebuild -project SpeedAlert.xcodeproj -scheme SpeedAlert \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build | tail -5

APP="$(find build/Build/Products -name 'SpeedAlert.app' -maxdepth 3 | head -1)"
echo "==> installing: $APP"
xcrun simctl install "$UDID" "$APP"

echo "==> launching"
xcrun simctl launch "$UDID" tw.speedalert.app || true

sleep 5
OUT="${HOME}/Desktop/speedalert.png"
xcrun simctl io "$UDID" screenshot "$OUT"
echo "==> screenshot saved: $OUT"

echo "==> SpeedAlert logs (last 3m) =="
xcrun simctl spawn "$UDID" log show --last 3m --style compact \
  --predicate 'eventMessage CONTAINS "[SpeedAlert]"' 2>/dev/null | tail -40 || true

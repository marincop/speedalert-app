#!/usr/bin/env bash
# Build SpeedAlert on macOS. Verifies the project compiles (simulator, no signing).
# Usage:
#   ./build.sh              # compile check only (no device needed)
#   ./build.sh device       # build for a connected device (needs signing team)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it first:  brew install xcodegen"
  exit 1
fi

echo "==> generating Xcode project"
xcodegen generate

MODE="${1:-sim}"

if [ "$MODE" = "device" ]; then
  echo "==> building for device (requires DEVELOPMENT_TEAM in project.yml)"
  xcodebuild -project SpeedAlert.xcodeproj -scheme SpeedAlert \
    -configuration Debug build | tail -40
else
  echo "==> compile check for iOS Simulator (no signing)"
  xcodebuild -project SpeedAlert.xcodeproj -scheme SpeedAlert \
    -sdk iphonesimulator -configuration Debug \
    CODE_SIGNING_ALLOWED=NO build | tail -40
fi

echo "==> done"

#!/usr/bin/env bash
# Build (and optionally upload) a TestFlight build for SpeedAlert.
#
# Export IPA only:
#   TEAM=ABCDE12345 ./release.sh
#
# Archive + export + UPLOAD via App Store Connect API key (no Apple ID password):
#   TEAM=ABCDE12345 \
#   ASC_KEY_NAME=AuthKey_ABC123XYZ.p8 \
#   ASC_KEY_ID=ABC123XYZ \
#   ASC_ISSUER=00000000-0000-0000-0000-000000000000 \
#   ./release.sh upload
#
# Where to get the key: appstoreconnect.apple.com → Users and Access →
# Integrations → App Store Connect API → generate a key (role: App Manager),
# download the .p8 (name it AuthKey_<KEYID>.p8) and note Key ID + Issuer ID.
# Put the .p8 in ~/.appstoreconnect/private_keys/
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-export}"
command -v xcodegen >/dev/null 2>&1 || { echo "install: brew install xcodegen"; exit 1; }
: "${TEAM:?set TEAM=YOUR_TEAM_ID}"

KEY_DIR="${HOME}/.appstoreconnect/private_keys"
KEY_PATH="${KEY_DIR}/${ASC_KEY_NAME:-}"

echo "==> generating project"
xcodegen generate

echo "==> archiving (Release, device)"
rm -rf build/SpeedAlert.xcarchive
xcodebuild -project SpeedAlert.xcodeproj -scheme SpeedAlert \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/SpeedAlert.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  -authenticationKeyPath "${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}/${ASC_KEY_NAME:-AuthKey_HK7BDA46FU.p8}" \
  -authenticationKeyID "${ASC_KEY_ID:-HK7BDA46FU}" \
  -authenticationKeyIssuerID "${ASC_ISSUER:-4eaad410-f804-4969-aa23-4e904f33e887}" \
  archive

DEST="export"
[ "$MODE" = "upload" ] && DEST="upload"

echo "==> export options (destination=$DEST)"
mkdir -p build
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>$DEST</string>
</dict></plist>
PLIST

echo "==> exporting"
rm -rf build/ipa
if [ "$MODE" = "upload" ]; then
  : "${ASC_KEY_ID:?set ASC_KEY_ID}"
  : "${ASC_ISSUER:?set ASC_ISSUER}"
  [ -f "$KEY_PATH" ] || { echo "missing API key: $KEY_PATH"; exit 1; }
  xcodebuild -exportArchive \
    -archivePath build/SpeedAlert.xcarchive \
    -exportOptionsPlist build/ExportOptions.plist \
    -exportPath build/ipa \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER"
  echo "==> uploaded to App Store Connect (see TestFlight in ~5-15 min)"
else
  xcodebuild -exportArchive \
    -archivePath build/SpeedAlert.xcarchive \
    -exportOptionsPlist build/ExportOptions.plist \
    -exportPath build/ipa \
    -allowProvisioningUpdates
  echo "==> IPA ready in build/ipa (drag into Transporter.app to upload,"
  echo "    or re-run with 'upload' + ASC_* env vars for scripted upload)"
  ls -la build/ipa
fi

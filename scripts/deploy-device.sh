#!/usr/bin/env bash
# Builds SkyRay signed for a physical iPhone, installs it and launches it.
# Requires an Apple account signed in to Xcode (Settings > Apple Accounts).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_UDID="${DEVICE_UDID:-00008140-0009453C22E8801C}"       # iPhone Ehsun (iPhone 16 Pro)
DEVICE_ID="${DEVICE_ID:-3D326CB2-D284-59E4-9A32-82842B959858}"  # devicectl identifier
DD="$ROOT/build/DerivedData"
cd "$ROOT"
xcodegen generate >/dev/null
xcodebuild -project SkyRay.xcodeproj -scheme SkyRay \
  -destination "platform=iOS,id=$DEVICE_UDID" -derivedDataPath "$DD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
APP="$DD/Build/Products/Debug-iphoneos/SkyRay.app"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" com.allion.skyray -- "$@"
echo "DEPLOYED"

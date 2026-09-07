#!/usr/bin/env bash
# Builds android/app/libs/raycore.aar containing BOTH Xray-core (libXray) and
# sing-box in one Go runtime, mirroring Frameworks/LibXray.xcframework for iOS
# (built by build-core.sh). Requires gomobile and the Android SDK/NDK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NDK_DIR="$(ls -d "$ANDROID_HOME"/ndk/*/ | sort -V | tail -1)"
export ANDROID_HOME
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${NDK_DIR%/}}"
mkdir -p "$ROOT/android/app/libs"
cd "$ROOT/core/raycore"
export PATH="$PATH:$(go env GOPATH)/bin"
gomobile bind -v -target android -androidapi 24 -trimpath -ldflags="-s -w -checklinkname=0 -X github.com/sagernet/sing-box/constant.Version=1.14.0" \
  -tags with_quic,with_utls \
  -o "$ROOT/android/app/libs/raycore.aar" \
  github.com/xtls/libxray github.com/ehsan/rayclient/raycore
echo "Built $ROOT/android/app/libs/raycore.aar"

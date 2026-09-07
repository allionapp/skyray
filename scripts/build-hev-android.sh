#!/usr/bin/env bash
# Builds hev-socks5-tunnel's native .so for all 4 Android ABIs (ndk-build,
# using the upstream Android.mk/Application.mk unmodified) and copies them
# into android/app/src/main/jniLibs, mirroring HevSocks5Tunnel.xcframework
# on iOS. Requires the Android NDK (installed via Android Studio > SDK Manager).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
NDK_DIR="$(ls -d "$ANDROID_HOME"/ndk/*/ | sort -V | tail -1)"
NDK="${ANDROID_NDK_HOME:-${NDK_DIR%/}}"
cd "$ROOT/third_party/hev-socks5-tunnel"

"$NDK/ndk-build" \
  NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk NDK_APPLICATION_MK=./Application.mk \
  NDK_LIBS_OUT=./android-libs NDK_OUT=./android-obj -j"$(sysctl -n hw.ncpu)"

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  mkdir -p "$ROOT/android/app/src/main/jniLibs/$abi"
  cp "android-libs/$abi/libhev-socks5-tunnel.so" "$ROOT/android/app/src/main/jniLibs/$abi/"
done
echo "Copied libhev-socks5-tunnel.so into android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86,x86_64}"

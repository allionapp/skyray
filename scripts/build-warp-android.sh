#!/bin/bash
# Builds the WARP core (Aether, AGPL-3.0) from source for Android and drops the
# binaries into the app's jniLibs, the same shape as build-core-android.sh.
#
# Aether has no library entry point we can load with System.loadLibrary, so the
# executable is packaged as libaether.so: Android only unpacks and allows
# exec on files under lib/<abi>/ that are named that way.
set -euo pipefail

REPO="https://github.com/CluvexStudio/Aether.git"
REF="${AETHER_REF:-0e6f6a5218e65ed4cddc68d1a71d9b9633f89e3f}"   # pinned; bump deliberately
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/third_party/aether"
OUT="$ROOT/android/app/src/main/jniLibs"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
export CARGO_TARGET_DIR="$SRC/target"
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"

command -v cargo >/dev/null || { echo "rust is missing: brew install rustup && rustup default stable"; exit 1; }
command -v cargo-ndk >/dev/null || cargo install cargo-ndk
command -v cmake >/dev/null || { echo "cmake is missing: brew install cmake"; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  git clone --recursive "$REPO" "$SRC"
fi
git -C "$SRC" fetch --all --tags
git -C "$SRC" checkout "$REF"
git -C "$SRC" submodule update --init --recursive

for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do
  rustup target add "$target" >/dev/null
done

cd "$SRC/aether"
declare -a abis=(arm64-v8a armeabi-v7a x86_64)
declare -a triples=(aarch64-linux-android armv7-linux-androideabi x86_64-linux-android)
for i in "${!abis[@]}"; do
  echo "== ${abis[$i]}"
  cargo ndk -t "${abis[$i]}" -P 24 build --release --bin aether
  install -m 0755 "$CARGO_TARGET_DIR/${triples[$i]}/release/aether" "$OUT/${abis[$i]}/libaether.so"
done

echo "built from $REF"
ls -la "$OUT"/*/libaether.so

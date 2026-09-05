#!/usr/bin/env bash
# Rebuilds the two native libraries the app embeds:
#   - LibXray.xcframework        (Xray-core wrapped by XTLS/libXray, via gomobile)
#   - HevSocks5Tunnel.xcframework (heiher/hev-socks5-tunnel, TUN -> SOCKS5 bridge)
# Requirements: Xcode, Go, python3, git. gomobile is installed automatically by libXray's script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TP="$ROOT/third_party"
mkdir -p "$TP" "$ROOT/Frameworks"

if [ ! -d "$TP/libXray" ]; then
  git clone --depth 1 https://github.com/XTLS/libXray.git "$TP/libXray"
fi
(cd "$TP/libXray" && python3 build/main.py apple gomobile)
rm -rf "$ROOT/Frameworks/LibXray.xcframework"
cp -R "$TP/libXray/LibXray.xcframework" "$ROOT/Frameworks/"

if [ ! -d "$TP/hev-socks5-tunnel" ]; then
  git clone --recursive --depth 1 https://github.com/heiher/hev-socks5-tunnel.git "$TP/hev-socks5-tunnel"
fi
(cd "$TP/hev-socks5-tunnel" && ./build-apple.sh)
rm -rf "$ROOT/Frameworks/HevSocks5Tunnel.xcframework"
cp -R "$TP/hev-socks5-tunnel/HevSocks5Tunnel.xcframework" "$ROOT/Frameworks/"

echo "Done. Now run: xcodegen generate && open SkyRay.xcodeproj"

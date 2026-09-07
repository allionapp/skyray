#!/usr/bin/env bash
# Builds Frameworks/LibXray.xcframework containing BOTH Xray-core (libXray) and
# sing-box (raycore) in a single Go runtime. Requires gomobile (installed by
# third_party/libXray's build script) and the libXray checkout in third_party/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/core/raycore"
export PATH="$PATH:$(go env GOPATH)/bin"
gomobile bind -v -target ios,iossimulator -iosversion 15.0 -trimpath -ldflags="-s -w -X github.com/sagernet/sing-box/constant.Version=1.14.0" \
  -tags with_quic,with_utls \
  -o "$ROOT/Frameworks/LibXray.xcframework" \
  github.com/xtls/libxray github.com/ehsan/rayclient/raycore
echo "Built $ROOT/Frameworks/LibXray.xcframework"

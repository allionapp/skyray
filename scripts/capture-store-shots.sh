#!/usr/bin/env bash
# Captures raw simulator screenshots for the App Store using the app's demo
# router (-DemoMode YES -DemoScreen …), then composes the framed images.
# Usage: scripts/capture-store-shots.sh <iphone-udid> <ipad-udid>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
IPHONE=$1; IPAD=$2
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/SkyRay.app
BUNDLE=com.allion.skyray
[ -x build/make-store-shot ] || swiftc -O -o build/make-store-shot scripts/make-store-shot.swift
for U in $IPHONE $IPAD; do
  xcrun simctl bootstatus $U -b >/dev/null 2>&1 || true
  xcrun simctl install $U "$APP"
  xcrun simctl status_bar $U override --time "9:41" --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
done
capture() { # udid lang dir
  local U=$1 LANG=$2 DIR=$3; mkdir -p "$DIR"
  local LOC="en_US"; [ "$LANG" = fa ] && LOC="fa_IR"
  local i=1
  for pair in "home:" "servers:servers" "chooser:chooser" "paste:paste" "added:added"; do
    local name=${pair%%:*} screen=${pair#*:}
    xcrun simctl terminate $U $BUNDLE >/dev/null 2>&1 || true
    if [ -n "$screen" ]; then
      xcrun simctl launch $U $BUNDLE -DemoMode YES -DemoScreen "$screen" -AppleLanguages "($LANG)" -AppleLocale "$LOC" >/dev/null
    else
      xcrun simctl launch $U $BUNDLE -DemoMode YES -AppleLanguages "($LANG)" -AppleLocale "$LOC" >/dev/null
    fi
    sleep 4
    xcrun simctl io $U screenshot "$DIR/0$i-$name.png" >/dev/null 2>&1
    i=$((i+1))
  done
}
if [ "${SKIP_CAPTURE:-0}" != 1 ]; then
  capture $IPHONE en build/shots/en-iphone; capture $IPHONE fa build/shots/fa-iphone
  capture $IPAD en build/shots/en-ipad; capture $IPAD fa build/shots/fa-ipad
fi

compose() { # lang device W H
  local lang=$1; local dev=$2; local W=$3; local H=$4
  local out=store/screenshots/$lang-$dev; rm -rf "$out"; mkdir -p "$out"
  local rtl="" T1 S1 T2 S2 T3 S3 T4 S4 T5 S5
  if [ "$lang" = en ]; then
    T1="One tap to connect"; S1="Live speed, ping and traffic while you browse."
    T2="All your servers, ranked by speed"; S2="Real latency tests. Pick the fastest in one tap."
    T3="Three ways in"; S3="Paste a link, scan a QR code, or add a subscription."
    T4="Paste it. We fill in the rest."; S4="Name, address and type are read from the link."
    T5="Checked before it's saved"; S5="Every link is read, validated and reached first."
  else
    rtl="rtl"
    T1="با یک ضربه متصل شوید"; S1="سرعت، پینگ و ترافیک زنده در حین استفاده"
    T2="همه‌ی سرورها، مرتب بر اساس سرعت"; S2="تست تأخیر واقعی و انتخاب سریع‌ترین با یک ضربه"
    T3="سه راه برای افزودن"; S3="لینک بچسبانید، کد QR اسکن کنید یا اشتراک اضافه کنید"
    T4="بچسبانید، بقیه با ما"; S4="نام، آدرس و نوع سرور از لینک خوانده می‌شود"
    T5="قبل از ذخیره بررسی می‌شود"; S5="هر لینک اول خوانده، اعتبارسنجی و آزمایش می‌شود"
  fi
  local i=1
  for pair in "01-home|$T1|$S1" "02-servers|$T2|$S2" "03-chooser|$T3|$S3" "04-paste|$T4|$S4" "05-added|$T5|$S5"; do
    local f=${pair%%|*}; local rest=${pair#*|}; local t=${rest%%|*}; local s=${rest#*|}
    build/make-store-shot "build/shots/$lang-$dev/$f.png" "$out/$f.png" $W $H "$t" "$s" $rtl >/dev/null
    i=$((i+1))
  done
}
compose en iphone 1320 2868; compose fa iphone 1320 2868; compose en ipad 2064 2752; compose fa ipad 2064 2752
rm -rf store/raw-simulator-shots; cp -R build/shots store/raw-simulator-shots
echo "Done: store/screenshots"

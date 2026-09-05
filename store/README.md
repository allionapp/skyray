# App Store assets

- `screenshots/en-iphone`, `screenshots/fa-iphone` — 1320×2868 (iPhone 6.9"), 5 per language. Upload to the 6.9" slot; App Store Connect reuses them for smaller iPhones.
- `screenshots/en-ipad`, `screenshots/fa-ipad` — 2064×2752 (iPad 13"), 5 per language. Required because the app targets iPad too.
- `raw-simulator-shots/` — the untouched simulator captures the frames were built from.

Regenerate: launch the app in the simulator with `-DemoMode YES` (fake connected state and demo servers,
nothing persisted), capture with `xcrun simctl io <udid> screenshot`, then run
`swift scripts/make-store-shot.swift <in> <out> <W> <H> "<title>" "<subtitle>" [rtl]`.

Suggested App Store text (EN): "SkyRay – Fast Proxy & VPN". Subtitle: "VLESS, Reality, Hysteria2, SSH, TUIC".

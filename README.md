# SkyRay (iOS)

A native Swift/SwiftUI iOS client in the spirit of v2rayNG: it embeds
[Xray-core](https://github.com/XTLS/Xray-core) through
[libXray](https://github.com/XTLS/libXray) and routes all device traffic through it
with a Network Extension packet tunnel.

## Features

- Import servers from `vmess://`, `vless://`, `trojan://`, `ss://`, `socks://`, `hysteria2://` links,
  raw Xray JSON, subscription URLs (plain or base64), or QR codes.
- System-wide VPN mode (NEPacketTunnelProvider + hev-socks5-tunnel -> Xray SOCKS5 inbound).
- Real latency test through each server (`pingBatch` from libXray).
- Traffic counters while connected, tunnel log viewer.
- LAN/loopback ranges bypass the proxy; everything else goes through the selected server.

## Design

The UI follows the "Modernist" design Ehsan made in Claude Design (project `65380c3a-…`, file
`V2Box Add Config.dc.html`): flat and square, ink `#201e1d` on a warm light ground `#f3f2f2`, 2px rules,
Archivo (display/body) and IBM Plex Mono (data), red `#ec3013` as the one field colour (the connected
state) and purple `#8013EC` for primary actions. `App/Theme/SkyTheme.swift` holds the tokens, rules,
button styles, square toggle and boxed field. Fonts are bundled under `App/Resources/Fonts` (SIL OFL).

Screens: Home (no config / off / connected), Servers, and the guided Add-config flow — chooser, paste,
narrated check (read → validate → reach → measure, all real), added poster, unreadable-link help,
QR scan, subscription. Settings and the server detail sheet keep the system look for now.

Demo/screenshot mode: `-DemoMode YES` (fake connected state and demo servers, nothing persisted) plus
`-DemoScreen servers|chooser|paste|added` opens a screen directly. `scripts/capture-store-shots.sh` uses it.

## Layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec (app + `PacketTunnel` extension) |
| `App/` | SwiftUI app: views, `VPNManager`, `ProfilesViewModel` |
| `PacketTunnel/` | Network Extension: starts Xray, finds the utun fd, runs hev-socks5-tunnel |
| `Shared/` | Code compiled into both targets: profile model/store, libXray wrapper, config builder, link parser |
| `Frameworks/` | `LibXray.xcframework` (Xray-core **and** sing-box in one Go runtime, built by `scripts/build-core.sh`), `HevSocks5Tunnel.xcframework` (`scripts/build-libs.sh`); not committed |
| `core/raycore/` | Go module that bundles libXray with sing-box and exports `SingboxStart/Stop/Ping/Test` |
| `scripts/build-libs.sh` | Rebuilds the native libraries |
| `scripts/capture-store-shots.sh` | Captures all App Store screenshots from both simulators via demo mode and composes them |
| `scripts/make-store-shot.swift` | Composes App Store screenshots from simulator captures (see `store/README.md`); the app's `-DemoMode YES` launch argument shows a demo connected state |
| `scripts/make-icon.swift` | Renders the app icon (comet on a sky gradient) into the asset catalog: `swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/Icon-1024.png` |

## Build

```bash
brew install xcodegen go
./scripts/build-libs.sh      # hev-socks5-tunnel + libXray checkout (~5-10 min the first time)
./scripts/build-core.sh      # combined Xray + sing-box framework (~10 min)
xcodegen generate
open SkyRay.xcodeproj
```

Two cores, one Go runtime: `core/raycore` imports both libXray and sing-box and is bound
with gomobile into a single `LibXray.xcframework`. Profiles carry a `core` field; the tunnel
extension starts Xray for most protocols and sing-box for `ssh://` and `tuic://` links, always
behind the same local SOCKS inbound that hev-socks5-tunnel feeds.

Then in Xcode:

1. Select your team for **both** targets (`SkyRay` and `PacketTunnel`).
2. Make sure the App IDs have the **Network Extensions** and **App Groups** capabilities
   (group id `group.com.allion.skyray`), or change the identifiers in `project.yml`
   and `Shared/AppConstants.swift`.
3. Run on a **physical device**. The iOS Simulator cannot run packet tunnel extensions,
   so only the UI, link parsing, and latency tests work there.

## How the tunnel works

1. The app saves the selected profile to the App Group and starts the tunnel.
2. The extension builds a runtime config (`Shared/XrayConfigBuilder.swift`) with a local
   SOCKS5 inbound on `127.0.0.1:10808` and the user's outbound, then calls `runXray`.
3. It applies `NEPacketTunnelNetworkSettings` (default routes, DNS 1.1.1.1 / 8.8.8.8).
4. It locates the utun file descriptor and hands it to hev-socks5-tunnel, which turns
   IP packets into SOCKS5 connections to Xray.

Keep the extension lean: iOS kills Network Extensions above roughly 50 MB, so geosite/geoip
data files are intentionally not loaded there.

## Feature parity with Hiddify / Streisand / Happ / V2Box / Karing (v0.3)

| Feature | SkyRay |
| --- | --- |
| Protocols | VLESS (Reality, Vision, XHTTP, WS, gRPC, httpupgrade, mKCP), VMess, Trojan, Shadowsocks, SOCKS, Hysteria2, WireGuard (Xray-core); SSH and TUIC (sing-box, same framework) |
| Import | share links, subscription URLs (plain / base64 / Clash YAML / Xray JSON), QR, launcher deep links (hiddify://, v2box://, clash://, sing-box://, streisand://, happ://, sub://), `skyray://` scheme |
| Subscription headers | subscription-userinfo (quota/expiry), profile-title, profile-update-interval, profile-web-page-url, support-url, announce |
| Subscriptions | auto-update interval, keep latencies/selection on refresh, per-subscription quota, provider website/support buttons |
| Latency | proxy ping (real HTTP through the server, 15 parallel), TCP ping, sort by latency, select fastest, ping on open |
| Routing | proxy-all / bypass Iran (geosite:category-ir + geoip:ir) / global, ad & tracker blocking (geosite:category-ads-all), custom domain/IP rules (proxy/direct/block), search |
| DNS | DoH/DoT/plain remote DNS, separate direct DNS for Iranian domains, tunnel DNS servers |
| Anti-censorship | TLS fragment (packets/length/interval), mux, uTLS fingerprint and Reality from links, allowInsecure honored |
| Connection | connect on demand (auto-reconnect), kill switch, stay connected on sleep, auto-connect on launch (last used / fastest), switch server while connected |
| Sharing | per-server QR code + link + share sheet, copy/share all links, JSON backup export/restore, LAN proxy sharing (SOCKS5 + HTTP) |
| Editing | rename, edit outbound JSON with validation, reorder, delete (row button, swipe, all, unreachable) |
| Automation | Siri / Shortcuts intents (connect, disconnect, toggle) on iOS 16+, URL scheme actions (`skyray://connect`, `disconnect`, `toggle`, `add?url=`, `import/<url>`) |
| UX | English + Persian (RTL), light/dark/system theme, live speed and traffic, tunnel log viewer/copy, no ads, no analytics |
| Not on iOS / not yet | per-app proxy (impossible without MDM on iOS), iCloud sync, home-screen widget |

## Lessons from V2Box's 1–2 star reviews (287 reviews, 13 storefronts, 2023–2026)

| Complaint about V2Box | What SkyRay does instead |
| --- | --- |
| Ads interrupt every action and even disconnect the VPN | No ads, no analytics, no tracking (see `PrivacyInfo.xcprivacy`) |
| Extension hits the 50 MB cap and the VPN drops | Extension reads only the active profile, no geo data, Go memory limit, memory logged by a watchdog |
| Random disconnects, "reset VPN" prompts, wipes configs | Watchdog cancels the tunnel with a real error instead of hanging; profiles live in the App Group with a backup and per-item decoding |
| Freezes / crashes with hundreds of servers or on "ping all" | Import parses off the main thread; ping runs 3 batches of 5 concurrently, cancellable, with progress |
| allowInsecure removed, Reality/XHTTP/gRPC/httpupgrade missing, old core | Latest Xray-core (26.x); `allowInsecure=1` honored from links; Clash YAML subscriptions |
| Aggressive `connIdle`/`uplinkOnly` policy drops connections | Explicit Xray default policy (connIdle 300) |
| No routing options / direct rule broken | Routing modes: proxy all + bypass LAN, bypass Iran (.ir), global |
| Battery drain and CPU heat | Stats polling only while the app is in the foreground; no background timers |
| Crashes on older iOS | Deployment target iOS 15 |
| UI stuck in a foreign language | English + Persian localization following the system language |
| Stops working when the phone sleeps | `disconnectOnSleep = false`; optional Connect On Demand auto-reconnect; optional kill switch |
| Confusing subscription / quota | Quota and expiry from `subscription-userinfo` shown on the home screen |

## Store listing links

- Privacy policy: https://allionapp.github.io/skyray-site/privacy.html (Persian: `privacy-fa.html`)
- Support: https://allionapp.github.io/skyray-site/support.html
- Terms: https://allionapp.github.io/skyray-site/terms.html
- Source of the site: https://github.com/allionapp/skyray-site (public, GitHub Pages)
- App Privacy answers for App Store Connect / Play Data safety: **Data Not Collected** (no tracking, no analytics, no accounts).

## Licenses

Xray-core and libXray are MPL-2.0; hev-socks5-tunnel is MIT.

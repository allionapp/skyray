# SkyRay — Handover

_Last updated: 2026-09-05. Written for whoever picks this project up next (a developer or a future AI session)._

## 1. What this is

**SkyRay** is a native Swift/SwiftUI iOS VPN client in the style of v2rayNG / Hiddify / Streisand / Happ.
It embeds two proxy cores inside a Network Extension packet tunnel:

- **Xray-core** (via [XTLS/libXray](https://github.com/XTLS/libXray)) for VLESS (Reality, Vision, XHTTP, WS, gRPC, httpupgrade, mKCP), VMess, Trojan, Shadowsocks, SOCKS, Hysteria2, WireGuard.
- **sing-box 1.14** for SSH and TUIC.

Both cores are compiled into **one** Go runtime and one framework (`Frameworks/LibXray.xcframework`).
The tunnel extension starts whichever core the selected profile needs, always listening on a local SOCKS5
inbound (`127.0.0.1:10808`), and [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel) turns the
device's utun packets into SOCKS5 connections.

Owner: Ehsan (ehusa86@gmail.com). Ehsan writes Persian; the UI is localized in English and Persian.
Android is explicitly postponed. Ehsan also has an older Flutter product "Sifaro" (`~/dev/Sifaro`) with the same Xray+hev design.

## 2. Current status (v0.4.0, build 4)

Verified on a real device (iPhone 16 Pro "iPhone Ehsun", iOS 26, UDID `00008140-0009453C22E8801C`):

| Check | Result |
| --- | --- |
| Packet tunnel starts (Xray, utun fd, hev) | OK |
| Real traffic through Ehsan's EthaVPN subscription (VLESS+XHTTP over Cloudflare) | Google 204, exit IP = VPN server |
| Iran bypass + ad block + TLS fragment | OK, extension memory 15 MB start / 27 MB under load |
| SSH through sing-box (local test server on the Mac) | OK |
| TUIC through sing-box (local test server on the Mac) | OK, memory 10 MB start / 17 MB under load |
| Persian RTL UI | OK (simulator) |
| Delete/edit/QR/backup/rules/settings screens | OK (simulator) |

Not verified: Hysteria2 and WireGuard against real servers (parsed and configured, never connected); LAN sharing from another device; Siri/Shortcuts intents on device; Connect-on-demand and kill switch behaviour over long sessions.

## 3. Machine / accounts

- Mac: Xcode 26.6 (iOS 26.5 SDK), Go 1.27, XcodeGen 2.46, python3, gomobile (installed by libXray's build script into `$GOPATH/bin`).
- Apple team: **ALLION LLC, `SG5BT8WSLT`** (signed in to Xcode). Automatic signing already created the App IDs
  `com.allion.skyray` and `com.allion.skyray.PacketTunnel` with Network Extensions + App Group `group.com.allion.skyray`.
- Signing identity in use: "Apple Development: ehsan karimi (57FZL75W5W)".
- Source: **https://github.com/allionapp/skyray** (private, branch `main`, pushed 2026-09-05). `third_party/`, `Frameworks/*.xcframework`, `build/` and the generated `SkyRay.xcodeproj` are gitignored; run `xcodegen generate` after cloning.

## 4. Repository layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec. Two targets: `SkyRay` (app) and `PacketTunnel` (network extension). Run `xcodegen generate` after any file add/remove. |
| `App/` | SwiftUI app: `SkyRayApp.swift` (launch args, URL scheme, auto-connect, theme), `Theme/SkyTheme.swift` (design tokens), `Views/` + `Views/AddConfig/`, `Services/` (`VPNManager`, `ProfilesViewModel`, `SubscriptionFetcher`, `TCPPing`, `AppIntents`), `Resources/` (en/fa strings, privacy manifest). |
| `PacketTunnel/` | `PacketTunnelProvider` (starts the right core, watchdog, memory log, sleep/wake), `HevTunnel`, `TunnelFD`, `TunnelLog`, `MemoryMonitor`, `GeoData/` (trimmed geoip/geosite). |
| `Shared/` | Compiled into both targets: `ServerProfile` (+ `core` field), `ProfileStore` (App Group persistence, backup, active profile, settings), `AppSettings`, `XrayCore`/`SingboxCore` wrappers, `XrayConfigBuilder`/`SingboxConfigBuilder`, `ShareLinkParser`, `SingboxLinkParser`, `SubscriptionLinkResolver`. |
| `core/raycore/` | Go module bundling libXray + sing-box. Exports `SingboxStart/Stop/Running/Test/Ping/Version`. `cmd/probe` is a Mac-side smoke test. |
| `Frameworks/` | `LibXray.xcframework` (190 MB, arm64 + simulator) and `HevSocks5Tunnel.xcframework`. Rebuildable, not committed. |
| `scripts/build-libs.sh` | Clones/builds hev-socks5-tunnel and the libXray checkout (needed by raycore's `replace`). |
| `scripts/build-core.sh` | gomobile bind of libXray + raycore into `Frameworks/LibXray.xcframework` (~10 min). |
| `scripts/deploy-device.sh` | Build signed for the iPhone, install, launch. Extra args go to the app (see §7). |
| `scripts/geotrim.go` | Trims Iran-v2ray-rules `geoip.dat`/`geosite.dat` to `ir`/`private` and `category-ir`/`category-ads`/`private`. |
| `README.md` | Feature matrix vs competitors and the V2Box-review-driven design decisions. |
| `third_party/` | libXray and hev-socks5-tunnel checkouts (gitignored). |

## 5. Build from scratch

```bash
brew install xcodegen go
./scripts/build-libs.sh     # hev xcframework + libXray checkout (libXray's own framework is then replaced by the next step)
./scripts/build-core.sh     # combined Xray + sing-box framework
xcodegen generate
open SkyRay.xcodeproj    # or ./scripts/deploy-device.sh
```

Simulator build (no signing):

```bash
xcodebuild -project SkyRay.xcodeproj -scheme SkyRay \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
```

The simulator cannot run packet tunnels; only UI, parsing and latency tests work there.

## 6. How the tunnel works

1. The app writes the selected profile to `active-profile.json` and settings to `settings.json` in the App Group, then starts the `NETunnelProviderManager`.
2. The extension reads **only** the active profile (never the full list; memory), sets `XRAY_LOCATION_ASSET` to its bundle for the geo files, builds the runtime config and starts Xray or sing-box.
3. It applies `NEPacketTunnelNetworkSettings` (default v4/v6 routes, LAN excluded unless routing mode is Global, DNS from settings).
4. It finds the utun fd (`packetFlow.value(forKeyPath: "socket.fileDescriptor")`, fallback: scan fds with `getsockopt UTUN_OPT_IFNAME`) and starts hev-socks5-tunnel on a 4 MB-stack thread.
5. A watchdog checks the core every 15 s, logs memory every 60 s, and cancels the tunnel with a real error if the core dies. Logs go to `tunnel.log` in the App Group; the app mirrors them to its `Documents/tunnel.log`.

Memory budget: iOS kills the extension around 50 MB. Keep geo lists small (the full `category-ads-all` cost ~10 MB extra), keep `domainMatcher: linear`, and never parse the whole server list in the extension.

## 7. Testing without touching the phone

`scripts/deploy-device.sh` forwards arguments to the app (`UserDefaults` argument domain):

| Argument | Effect |
| --- | --- |
| `-ImportLink '<links, one per line>'` | import share links |
| `-ImportSubscription '<url or launcher link>'` | import a subscription |
| `-SelectName '<profile name>'` | select a server |
| `-SettingsB64 '<base64 of partial settings JSON>'` | merge settings (raw JSON args get dropped by devicectl) |
| `-AutoConnect YES` | (re)connect, restarting the tunnel |
| `-SelfTest YES` | after connecting, fetch Google 204 + api.ipify.org through the tunnel and write the result to the log |
| `-AutoDisconnect YES` | disconnect and exit the flow |

Read results from the Mac:

```bash
xcrun devicectl device copy from --device 3D326CB2-D284-59E4-9A32-82842B959858 \
  --source Documents/tunnel.log --destination /tmp/tunnel.log \
  --domain-type appDataContainer --domain-identifier com.allion.skyray
```

`Documents/import.log` records subscription import results the same way.

Local SSH/TUIC test servers used for the sing-box verification live in the session scratchpad
(`testservers/main.go`: gliderlabs/ssh on `:2222`, sing-box TUIC inbound on `:8443`, self-signed cert).
Re-create them if needed; the phone must be on the same Wi-Fi as the Mac.

Simulator quirks: the keyboard is a Persian layout, so put text on the clipboard with `xcrun simctl pbcopy <udid>` and use the in-app Paste button. Launch in Persian with `-AppleLanguages "(fa)" -AppleLocale fa_IR`.

## 8. Design decisions worth knowing

- **No ads, no analytics.** The single biggest complaint in 287 one/two-star V2Box reviews. Privacy manifests declare no tracking.
- **Profiles are decoded one by one** with a backup file so an update can never wipe the list.
- **Import parses off the main thread**; ping runs 3 batches of 5 in parallel and is cancellable.
- **`allowInsecure=1` in links is honored**; libXray's converter drops it, `ShareLinkParser.applyLinkExtras` puts it back.
- **Launcher deep links** (`hiddify://import/…`, `v2box://…`, `clash://…`, `sing-box://…`, `streisand://…`, `happ://…`, `sub://…`) and HTTP 307 redirects to them are unwrapped by `SubscriptionLinkResolver` / `SubscriptionFetcher`.
- **Subscription headers** supported: `subscription-userinfo`, `profile-title`, `profile-update-interval`, `profile-web-page-url`, `support-url`, `announce`.
- **Routing modes:** proxy-all (LAN direct), bypass Iran (`geosite:category-ir` + `geoip:ir` + `domain:ir`), global. Custom rules and a compact ad-block list on top.
- **sing-box 1.14** requires the new DNS server object format (`{"type":"https","server":…}`); `SingboxConfigBuilder.dnsServer` converts the user's string.
- **sing-box latency probe uses plain HTTP** (`cp.cloudflare.com/generate_204`) because HTTPS through the local TUIC test server returned EOF from Go, while HTTPS from the phone worked. Revisit if a real TUIC server also fails.
- Deployment target is **iOS 15** (older iPhones common among the target users).

## 9. Known gaps / next steps

1. **Design (done 2026-09-05):** the Claude Design "Modernist" screens are implemented (Home states, Servers, the whole Add-config flow). The design file was pulled through Ehsan's logged-in Chrome (`GetFile` RPC on claude.ai/design) into `build/design/` — re-fetch the same way if the design changes. Still on the system look: Settings, Rules, Backup and the server detail sheet; restyle them with `SkyTheme` when there is time.
2. Verify Hysteria2 and WireGuard against real servers.
3. Test LAN sharing from a second device, Connect-on-demand and kill switch over hours, and background battery use.
4. Optional features not done: iCloud sync, home-screen widget, more languages (ru, zh), per-app proxy is impossible on iOS.
5. App Store prep: privacy policy / support / terms pages are live at https://allionapp.github.io/skyray-site/ (repo allionapp/skyray-site, public). Launch screen still to do (the app icon and screenshots are done: `store/screenshots/`, `scripts/make-store-shot.swift`, demo mode via `-DemoMode YES`; `scripts/make-icon.swift` renders `App/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`), `ITSAppUsesNonExemptEncryption` is already `false`, export compliance notes for the crypto in Xray/sing-box.
6. Repo is on GitHub (private). Consider adding a CI workflow that runs `xcodegen generate` + a simulator build.
7. Android client (Kotlin, same architecture) when Ehsan re-opens that decision.

## 10. Licenses

Xray-core and libXray: MPL-2.0. sing-box: GPL-3.0 (note: linking sing-box makes the combined core GPL-3.0; keep that in mind before publishing closed-source). hev-socks5-tunnel: MIT. Geo data: Iran-v2ray-rules (GPL-3.0 / upstream licenses).

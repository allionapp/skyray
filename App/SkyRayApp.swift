import SwiftUI

@main
struct SkyRayApp: App {
    @StateObject private var vpn = VPNManager()
    @StateObject private var profiles = ProfilesViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(vpn)
                .environmentObject(profiles)
                .preferredColorScheme(colorScheme)
                .task { await onLaunch() }
                .onChange(of: scenePhase) { phase in
                    vpn.setActive(phase == .active)
                    if phase == .active { Task { await profiles.updateStaleSubscriptions(defaultHours: vpn.settings.subscriptionAutoUpdateHours) } }
                }
                .onOpenURL { url in
                    Task { await handleOpenURL(url) }
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch vpn.settings.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// skyray://import/<subscription url>, skyray://connect, skyray://disconnect,
    /// skyray://add?url=<share link>, or any launcher link handed to the app.
    @MainActor
    private func handleOpenURL(_ url: URL) async {
        let text = url.absoluteString
        if url.scheme?.lowercased() == "skyray" {
            switch url.host?.lowercased() {
            case "connect":
                if let p = profiles.selectedProfile { await vpn.connect(profile: p) }
                return
            case "disconnect":
                vpn.disconnect()
                return
            case "toggle":
                await vpn.toggle(profile: profiles.selectedProfile)
                return
            case "add":
                if let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value {
                    _ = await profiles.importText(link)
                }
                return
            default: break
            }
        }
        if ShareLinkParser.containsShareLink(text) {
            _ = await profiles.importText(text)
        } else if SubscriptionLinkResolver.resolve(text) != nil {
            await profiles.importSubscription(text)
        }
    }

    @MainActor
    private func onLaunch() async {
        if UserDefaults.standard.bool(forKey: "DemoMode") {
            profiles.loadDemoData()
            vpn.enableDemo()
            return
        }
        await handleLaunchArguments()
        if vpn.settings.pingOnOpen { Task { await profiles.pingAll() } }
        if vpn.settings.autoConnectOnLaunch, !vpn.isConnected, !UserDefaults.standard.bool(forKey: "AutoDisconnect") {
            var target = profiles.selectedProfile
            if vpn.settings.autoConnectChoice == .fastest {
                await profiles.pingAll()
                target = profiles.selectFastest() ?? target
            }
            if let target { await vpn.connect(profile: target) }
        }
    }

    /// Developer conveniences passed as launch arguments, e.g. from
    /// `xcrun devicectl device process launch ... -- -ImportLink "vless://..." -AutoConnect YES`.
    @MainActor
    private func handleLaunchArguments() async {
        let defaults = UserDefaults.standard
        await vpn.load()
        if defaults.bool(forKey: "AutoDisconnect") {
            vpn.disconnect()
            return
        }
        if let link = defaults.string(forKey: "ImportLink"), !link.isEmpty {
            let added = await profiles.importText(link)
            if added > 0, let last = profiles.profiles.last { profiles.select(last) }
        }
        if let sub = defaults.string(forKey: "ImportSubscription"), !sub.isEmpty {
            await profiles.importSubscription(sub)
        }
        if let name = defaults.string(forKey: "SelectName"),
           let match = profiles.profiles.first(where: { $0.name == name }) {
            profiles.select(match)
        }
        // UserDefaults parses a `{...}` launch argument as a plist dictionary, so accept both forms.
        var patchObject: [String: Any]?
        if let dict = defaults.dictionary(forKey: "SettingsJSON") { patchObject = dict }
        else if let json = defaults.string(forKey: "SettingsJSON"), let data = json.data(using: .utf8) {
            patchObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else if let b64 = defaults.string(forKey: "SettingsB64"), let data = Data(base64Encoded: b64) {
            patchObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        if let patch = patchObject {
            // Merge a partial settings JSON over the stored settings (testing aid).
            let encoder = JSONEncoder(); let decoder = JSONDecoder()
            if var current = try? JSONSerialization.jsonObject(with: try encoder.encode(vpn.settings)) as? [String: Any] {
                for (k, v) in patch { current[k] = v }
                if let merged = try? JSONSerialization.data(withJSONObject: current),
                   let s = try? decoder.decode(AppSettings.self, from: merged) { vpn.settings = s }
            }
        }
        if defaults.bool(forKey: "AutoConnect"), let profile = profiles.selectedProfile {
            await vpn.reconnect(profile: profile, force: true)
            if defaults.bool(forKey: "SelfTest") {
                for _ in 0..<40 where !vpn.isConnected {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                await vpn.runSelfTest()
            }
        }
    }
}

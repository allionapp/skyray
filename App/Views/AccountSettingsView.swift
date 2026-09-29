import SwiftUI
import UIKit

/// Settings, as in SkyRay's Android build: a short list of what a customer needs, in the same
/// order. (Android's "Apps that bypass the VPN" has no iOS counterpart: iOS gives a VPN app no
/// per-app routing.) Everything else — rules, routing, backups, WARP and the rest — waits
/// behind expert mode (seven taps on the version in About), where the full settings screen
/// appears as "Advanced".
struct SettingsView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("EthaExpertMode") private var expertMode = false
    @State private var showServers = false
    @State private var showAdvanced = false
    @State private var showLogs = false
    @State private var confirmDelete = false
    @State private var toast: String?

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Etha.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        row("Choose a server", detail: serverDetail) { showServers = true }
                        row("Language", detail: currentLanguage) { openAppSettings() }
                        row("Check for update", detail: nil) { open(AppConstants.appStoreURL) }
                        row("Send logs to support", detail: String(localized: "Only when support asks for it")) { showLogs = true }
                        NavigationLink {
                            AboutView(expertMode: $expertMode) { show($0) }
                        } label: {
                            rowLabel("About", detail: versionText)
                        }
                        row("Privacy policy", detail: nil) { open(AppConstants.privacyPolicyURL) }
                        if AdsManager.shared.privacyChoicesRequired || UserDefaults.standard.bool(forKey: "DemoMode") {
                            // Google's consent can be changed here any time (asked for by its EU rules).
                            row("Privacy choices", detail: String(localized: "Change what you agreed to for ads")) { privacyChoices() }
                        }
                        row("Delete account", detail: String(localized: "Removes your subscription and all its data from this phone"),
                            destructive: true) { confirmDelete = true }
                        if expertMode {
                            row("Advanced", detail: String(localized: "The full settings. For support only.")) { showAdvanced = true }
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                if let toast {
                    Text(toast).font(.system(size: 15)).foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color.black.opacity(0.82)).clipShape(Capsule())
                        .padding(.bottom, 28).padding(.horizontal, 24)
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
            .alert(String(localized: "Delete account"), isPresented: $confirmDelete) {
                Button(String(localized: "Delete"), role: .destructive) { deleteAccount() }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Your subscription, its servers and all account data are removed from this phone. Your link keeps working, so you can add it again any time.")
            }
        }
        .navigationViewStyle(.stack)
        .tint(Etha.brand)
        .sheet(isPresented: $showServers) { LinkServerSheet() }
        .sheet(isPresented: $showAdvanced) { FullSettingsView() }
        .sheet(isPresented: $showLogs) { ActivitySheet(items: [logText()]) }
    }

    // MARK: Rows

    private func row(_ title: LocalizedStringKey, detail: String?, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, detail: detail, destructive: destructive) }
            .buttonStyle(.plain)
    }

    private func rowLabel(_ title: LocalizedStringKey, detail: String?, destructive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 18)).foregroundColor(destructive ? .red : Etha.ink)
            if let detail {
                Text(verbatim: detail).font(.system(size: 15)).foregroundColor(Etha.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private var serverDetail: String {
        if profiles.isAutomatic {
            let best = profiles.profiles.filter { $0.core != .warp && ($0.latencyMs ?? -1) > 0 }.min { $0.latencyMs! < $1.latencyMs! }
            return best.map { String(format: String(localized: "Auto · %@"), $0.name) } ?? String(localized: "Auto (fastest)")
        }
        return profiles.selectedProfile?.name ?? "—"
    }

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }

    // MARK: Actions

    /// iOS keeps each app's language in its own Settings page.
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// Google's form runs over the tunnel only, so it needs a connection.
    private func privacyChoices() {
        guard vpn.isConnected, let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            show(String(localized: "Connect first, then open Privacy choices."))
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        AdsManager.shared.showPrivacyChoices(from: top) { shown in
            if !shown { show(String(localized: "Connect first, then open Privacy choices.")) }
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { UIApplication.shared.open(url) }
    }

    private func logText() -> String {
        let version = versionText
        return "SkyRay iOS \(version)\n\n" + ProfileStore.shared.readTunnelLog()
    }

    /// Every subscription and server leaves the phone; the links themselves keep working.
    private func deleteAccount() {
        if vpn.isConnected || vpn.isBusy { vpn.disconnect() }
        profiles.deleteAll()
        show(String(localized: "Account deleted from this phone"))
    }

    private func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == text { toast = nil }
        }
    }
}

/// "Choose a server", as on Android: Auto and the servers of the link in use, with their
/// latency, and Test again. A new choice while connected moves the connection over.
private struct LinkServerSheet: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Button { chooseAuto() } label: {
                    line(String(localized: "Auto (fastest)"), detail: nil, chosen: profiles.isAutomatic)
                }
                ForEach(profiles.linkServers) { p in
                    Button { choose(p) } label: {
                        line(p.name, detail: latency(p), chosen: !profiles.isAutomatic && p.id == profiles.selectedId)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(Text("Choose a server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(Text("Close"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await testAgain() } } label: {
                        if profiles.isPinging { ProgressView() } else { Text("Test again") }
                    }
                    .disabled(profiles.isPinging)
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(Etha.brand)
    }

    private func line(_ title: String, detail: String?, chosen: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 17)).foregroundColor(Etha.ink).lineLimit(1)
                if let detail { Text(verbatim: detail).font(.system(size: 14)).foregroundColor(Etha.muted) }
            }
            Spacer()
            if chosen { Image(systemName: "checkmark").foregroundColor(Etha.brand) }
        }
        .contentShape(Rectangle())
    }

    private func latency(_ p: ServerProfile) -> String {
        switch p.latencyMs {
        case nil: return String(localized: "not tested")
        case let ms? where ms < 0: return String(localized: "failed")
        case let ms?: return "\(ms) ms"
        }
    }

    private func chooseAuto() {
        profiles.isAutomatic = true
        dismiss()
        Task {
            if !profiles.latenciesAreFresh { await profiles.pingAll(only: profiles.linkServers, markFresh: true) }
            await moveToBestIfConnected()
        }
    }

    private func choose(_ p: ServerProfile) {
        profiles.choose(p)
        dismiss()
        if vpn.isConnected { Task { await vpn.reconnect(profile: p) } }
    }

    private func testAgain() async {
        await profiles.pingAll(only: profiles.linkServers, markFresh: true)
        if profiles.isAutomatic { await moveToBestIfConnected() }
    }

    private func moveToBestIfConnected() async {
        let current = profiles.selectedId
        guard let best = profiles.selectFastest(), best.id != current, vpn.isConnected else { return }
        await vpn.reconnect(profile: best)
    }
}

/// About: the version, what SkyRay is built on, and the seven-tap switch for expert mode.
private struct AboutView: View {
    @Binding var expertMode: Bool
    let announce: (String) -> Void
    @State private var taps = 0

    var body: some View {
        ZStack {
            Etha.canvas.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 56)).foregroundColor(Etha.brand).padding(.top, 40)
                Text("SkyRay").font(.system(size: 26, weight: .semibold)).foregroundColor(Etha.ink)
                Text(verbatim: version)
                    .font(.system(size: 16)).foregroundColor(Etha.muted)
                    .padding(.horizontal, 24).padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { tapVersion() }
                Text("Based on Xray-core and sing-box").font(.system(size: 15)).foregroundColor(Etha.muted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text("About"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return String(format: String(localized: "Version %@"), "\(v) (\(b))")
    }

    private func tapVersion() {
        taps += 1
        guard taps >= 7 else { return }
        taps = 0
        expertMode.toggle()
        announce(expertMode ? String(localized: "Expert mode on: Advanced is now in Settings") : String(localized: "Expert mode off"))
    }
}

/// UIKit's share sheet, for iOS 15 where SwiftUI has no ShareLink.
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

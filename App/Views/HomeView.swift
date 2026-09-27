import SwiftUI

/// Home, as in SkyRay's Android build: one card with the connect button, the state and the
/// server choice ("Auto" picks the fastest and moves to another if the line stops answering),
/// and one card for the account — days and data left, the provider's message, Support.
/// With nothing added yet it is only "Paste link" and "Scan QR code".
struct HomeView: View {
    @EnvironmentObject private var vpn: VPNManager
    @EnvironmentObject private var profiles: ProfilesViewModel
    @State private var showSettings = false
    @State private var showScanner = false
    @State private var showAddLink = false
    /// Automatic mode tests every server before connecting; that wait needs its own label.
    @State private var findingFastest = false
    @State private var toast: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Etha.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 16) {
                        if profiles.profiles.isEmpty {
                            emptyCard
                        } else {
                            statusCard
                            accountCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.bottom, 28).padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showScanner) { scanner }
        .confirmationDialog(Text("+ Add another link"), isPresented: $showAddLink, titleVisibility: .visible) {
            Button(String(localized: "Paste link")) { pasteLink() }
            Button(String(localized: "Scan QR code")) { showScanner = true }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .task(id: vpn.isConnected) { await watchLine() }
        .onAppear {
            switch DemoRouter.screen {
            case "settings": showSettings = true
            default: break
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vpn.isConnected)
        .animation(.easeInOut(duration: 0.2), value: toast)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("SkyRay").font(.system(size: 26, weight: .regular)).foregroundColor(Etha.ink)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 22, weight: .regular)).foregroundColor(Etha.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Settings"))
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
    }

    // MARK: Nothing added yet

    private var emptyCard: some View {
        EthaCard {
            VStack(spacing: 14) {
                Image(systemName: "link.badge.plus").font(.system(size: 44)).foregroundColor(Etha.brand)
                    .padding(.top, 6)
                Text("Almost there").font(.system(size: 24, weight: .semibold)).foregroundColor(Etha.ink)
                Text("👇 Tap Paste link — that's all.").font(.system(size: 16)).foregroundColor(Etha.muted)
                    .multilineTextAlignment(.center)
                Button { pasteLink() } label: {
                    if profiles.isImporting { ProgressView().tint(.white) } else { Text("Paste link") }
                }
                .buttonStyle(EthaFilledButton())
                .disabled(profiles.isImporting)
                .padding(.top, 8)
                Button { showScanner = true } label: { Text("Scan QR code") }
                    .buttonStyle(EthaOutlinedButton())
            }
        }
        .padding(.top, 12)
    }

    // MARK: Connection

    private var isWorking: Bool { findingFastest || vpn.isBusy }

    private var statusCard: some View {
        EthaCard {
            VStack(spacing: 10) {
                Button(action: tapConnect) {
                    ZStack {
                        Circle().fill(vpn.isConnected ? Etha.live : Etha.brand)
                        if isWorking {
                            ProgressView().scaleEffect(1.6).tint(.white)
                        } else {
                            Image(systemName: "power").font(.system(size: 54, weight: .medium)).foregroundColor(.white)
                        }
                    }
                    .frame(width: 164, height: 164)
                    .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(findingFastest || vpn.status == .disconnecting)
                .accessibilityLabel(Text(vpn.isConnected ? "Disconnect" : "Connect"))
                .padding(.top, 4).padding(.bottom, 10)

                Text(stateText).font(.system(size: 28, weight: .bold)).foregroundColor(Etha.ink)
                Text(vpn.isConnected ? "Tap to disconnect" : "Tap to connect")
                    .font(.system(size: 16)).foregroundColor(Etha.muted)
                if vpn.isConnected, let p = profiles.selectedProfile {
                    Text(String(format: String(localized: "Server: %@"), p.name))
                        .font(.system(size: 16)).foregroundColor(Etha.muted).lineLimit(1).truncationMode(.middle)
                    if let exit = vpn.exitInfo {
                        Text(verbatim: exitLine(exit)).font(.system(size: 13)).foregroundColor(Etha.muted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                } else if !isWorking {
                    // Both stores want the ad announced before it interrupts anything.
                    Text("Free to use — a short ad plays once you connect")
                        .font(.system(size: 16)).foregroundColor(Etha.muted).multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                if let message = vpn.notice ?? vpn.lastError, !vpn.isConnected {
                    Text(message).font(.system(size: 14)).foregroundColor(.red.opacity(0.85))
                        .multilineTextAlignment(.center).padding(.top, 4)
                }
                serverRow.padding(.top, 18)
            }
        }
        .padding(.top, 12)
    }

    private var stateText: LocalizedStringKey {
        if findingFastest { return "Finding the best server…" }
        switch vpn.status {
        case .connecting, .reasserting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .connected: return "Connected"
        default: return "Not connected"
        }
    }

    // MARK: Server choice

    /// Everything but WARP competes in "Auto"; WARP is chosen by hand.
    private var contenders: [ServerProfile] { profiles.profiles.filter { $0.core != .warp } }

    private var serverLabel: String {
        if profiles.isAutomatic {
            let best = contenders.filter { ($0.latencyMs ?? -1) > 0 }.min { $0.latencyMs! < $1.latencyMs! }
            if let best { return String(format: String(localized: "Auto · %@"), best.name) }
            return String(localized: "Auto (fastest)")
        }
        return profiles.selectedProfile?.name ?? ""
    }

    private var serverRow: some View {
        HStack(spacing: 14) {
            Menu {
                Button { chooseAutomatic() } label: {
                    Label(String(localized: "Auto (fastest)"), systemImage: profiles.isAutomatic ? "checkmark" : "bolt")
                }
                ForEach(profiles.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.servers) { p in
                            Button { choose(p) } label: {
                                let chosen = !profiles.isAutomatic && p.id == profiles.selectedId
                                Label(menuTitle(p), systemImage: chosen ? "checkmark" : (p.flag == nil ? "server.rack" : "globe"))
                            }
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a server").font(.system(size: 12)).foregroundColor(Etha.muted)
                    HStack {
                        Text(verbatim: serverLabel).font(.system(size: 17)).foregroundColor(Etha.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundColor(Etha.muted)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Etha.outline.opacity(0.55), lineWidth: 1.2))
                .contentShape(Rectangle())
            }
            Button { Task { await testAgain() } } label: {
                if profiles.isPinging { ProgressView() } else { Text("Test again").font(.system(size: 16, weight: .medium)) }
            }
            .foregroundColor(Etha.brand)
            .disabled(profiles.isPinging)
        }
    }

    private func menuTitle(_ p: ServerProfile) -> String {
        var title = p.name
        if let flag = p.flag { title = "\(flag) " + title }
        switch p.latencyMs {
        case nil: title += " · " + String(localized: "not tested")
        case let ms? where ms < 0: title += " · " + String(localized: "failed")
        case let ms?: title += " · \(ms) ms"
        }
        return title
    }

    private func chooseAutomatic() {
        profiles.isAutomatic = true
        Task {
            if !profiles.latenciesAreFresh { await profiles.pingAll() }
            await moveToBestIfConnected()
        }
    }

    private func choose(_ p: ServerProfile) {
        profiles.choose(p)
        if vpn.isConnected { Task { await vpn.reconnect(profile: p) } }
    }

    private func testAgain() async {
        await profiles.pingAll()
        // Auto means the best line of the latest test: re-pick, and move over if connected.
        if profiles.isAutomatic { await moveToBestIfConnected() }
    }

    private func moveToBestIfConnected() async {
        let current = profiles.selectedId
        guard let best = profiles.selectFastest(), best.id != current, vpn.isConnected else { return }
        await vpn.reconnect(profile: best)
    }

    // MARK: Account

    /// The plan the chosen server belongs to, or the first one there is.
    private var account: SubscriptionInfo? {
        if let url = profiles.selectedProfile?.subscriptionURL, let sub = profiles.subscriptions.first(where: { $0.url == url }) {
            return sub
        }
        return profiles.subscriptions.first
    }

    private var accountCard: some View {
        EthaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: account?.title ?? account.flatMap { URL(string: $0.url)?.host } ?? String(localized: "My servers"))
                    .font(.system(size: 22, weight: .semibold)).foregroundColor(Etha.ink).lineLimit(1)
                HStack(alignment: .top, spacing: 12) {
                    tile(value: daysValue, label: daysLabel)
                    tile(value: dataValue, label: dataLabel)
                }
                if let announce = account?.announce, !announce.isEmpty {
                    Text(verbatim: announce).font(.system(size: 15)).foregroundColor(Etha.ink)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Etha.tile).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                // Renew is left out: the App Store takes payment for digital services itself.
                Button { openSupport() } label: { Text("Support") }
                    .buttonStyle(EthaOutlinedButton())
                    .padding(.top, 4)
                Button { Task { await refresh() } } label: {
                    if profiles.isImporting { ProgressView() } else { Text("Refresh").font(.system(size: 17, weight: .medium)) }
                }
                .foregroundColor(Etha.brand)
                .frame(maxWidth: .infinity)
                .disabled(profiles.isImporting)
                // A second (third…) link: its servers join the list, and Auto picks among them all.
                Button { showAddLink = true } label: { Text("+ Add another link").font(.system(size: 17, weight: .medium)) }
                    .foregroundColor(Etha.brand)
                    .frame(maxWidth: .infinity)
                    .disabled(profiles.isImporting)
            }
        }
    }

    private func tile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: value).font(.system(size: 28, weight: .semibold)).foregroundColor(Etha.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: label).font(.system(size: 15)).foregroundColor(Etha.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Etha.tile)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var daysValue: String {
        guard let expire = account?.expire else { return "–" }
        let days = Int(ceil(expire.timeIntervalSinceNow / 86_400))
        return days <= 0 ? "0" : "\(days)"
    }

    private var daysLabel: String {
        guard let expire = account?.expire else { return String(localized: "days left") }
        return expire < Date() ? String(localized: "Expired. Renew to keep connecting.") : String(localized: "days left")
    }

    private var dataValue: String {
        guard let sub = account, let total = sub.total else { return "–" }
        let used = ByteCountFormatter.string(fromByteCount: sub.used ?? 0, countStyle: .binary)
        return total == 0 ? used : used
    }

    private var dataLabel: String {
        guard let sub = account, let total = sub.total else { return String(localized: "Data: unknown until the next refresh") }
        if total == 0 { return String(localized: "Unlimited data") }
        return String(format: String(localized: "of %@ used"), ByteCountFormatter.string(fromByteCount: total, countStyle: .binary))
    }

    private func exitLine(_ exit: (ip: String, country: String?)) -> String {
        guard let code = exit.country, let flag = CountryLabel.flag(code) else { return exit.ip }
        return "\(flag) \(CountryLabel.name(code)) · \(exit.ip)"
    }

    // MARK: Actions

    private func tapConnect() {
        if vpn.isConnected || vpn.status == .connecting || vpn.status == .reasserting {
            vpn.disconnect()
            return
        }
        Task {
            findingFastest = profiles.isAutomatic && contenders.count > 1 && !profiles.latenciesAreFresh
            let target = await profiles.connectionTarget()
            findingFastest = false
            guard let target else { return }
            await vpn.toggle(profile: target)
        }
    }

    /// The provider's own support address when its subscription gives one, else SkyRay's.
    private func openSupport() {
        let raw = account?.supportURL ?? AppConstants.supportBotURL
        guard let url = URL(string: raw) else { return }
        UIApplication.shared.open(url)
    }

    private func refresh() async {
        if account != nil {
            await profiles.updateAllSubscriptions()
        }
        await testAgain()
    }

    private func pasteLink() {
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            show(String(localized: "No link found. In Telegram, tap your link — it opens here."))
            return
        }
        Task { await importLink(text) }
    }

    private var scanner: some View {
        NavigationView {
            QRScannerView { code in
                showScanner = false
                Task { await importLink(code) }
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { showScanner = false } }
            }
        }
    }

    /// Adds the link — a subscription or server links — and connects, as the Android build does.
    private func importLink(_ text: String) async {
        let before = profiles.profiles.count
        if ShareLinkParser.containsShareLink(text) {
            _ = await profiles.importText(text)
        } else if SubscriptionLinkResolver.resolve(text) != nil {
            await profiles.importSubscription(text)
        } else {
            show(String(localized: "No link found. In Telegram, tap your link — it opens here."))
            return
        }
        guard profiles.profiles.count > before else {
            show(profiles.message ?? String(localized: "Could not read this link"))
            return
        }
        show(String(localized: "Subscription added"))
        if !vpn.isConnected, !vpn.isBusy { tapConnect() }
    }

    private func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: Watchdog

    /// While connected in Auto mode and the app is open, a line that stops answering twice in a
    /// row is swapped for the next fastest — the Android build does this from its service; iOS
    /// gives the app no such place, so it runs while the app is in front.
    private func watchLine() async {
        guard vpn.isConnected else { return }
        var failures = 0
        while !Task.isCancelled, vpn.isConnected {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, vpn.isConnected, profiles.isAutomatic, !vpn.isBusy else { continue }
            if await lineAnswers() {
                failures = 0
                continue
            }
            failures += 1
            guard failures >= 2, let current = profiles.selectedProfile else { continue }
            failures = 0
            await profiles.pingAll()
            let next = profiles.profiles
                .filter { $0.core != .warp && $0.id != current.id && ($0.latencyMs ?? -1) > 0 }
                .min { $0.latencyMs! < $1.latencyMs! }
            guard let next else { continue }
            profiles.select(next)
            await vpn.reconnect(profile: next)
            show(String(format: String(localized: "Switched to %@"), next.name))
        }
    }

    private func lineAnswers() async -> Bool {
        guard let url = URL(string: AppConstants.probeURL) else { return true }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        return (try? await URLSession.shared.data(for: request)).map { ($0.1 as? HTTPURLResponse)?.statusCode ?? 0 < 500 } ?? false
    }
}

/// Shrinks slightly while held, the only feedback a round button needs.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

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
    @State private var showLinks = false
    @State private var confirmRemoveLink = false
    /// Automatic mode tests every server before connecting; that wait needs its own label.
    @State private var findingFastest = false
    @State private var toast: String?
    /// The connecting screen: up from the tap on Connect until the connection is ready to use.
    @State private var preparing = false
    @State private var progress: Double = 0
    @State private var progressCap: Double = 0
    @State private var preparingSeconds = 0

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
            if preparing { connectingScreen }
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
        .confirmationDialog(Text("Your links"), isPresented: $showLinks, titleVisibility: .visible) {
            ForEach(Array(zip(profiles.subscriptions, profiles.linkLabels)), id: \.0.url) { link, label in
                Button((link.url == profiles.activeLink?.url ? "✓ " : "") + label) { switchLink(to: link.url) }
            }
            Button(String(localized: "+ Add another link")) { after { showAddLink = true } }
            Button(String(localized: "Remove this link"), role: .destructive) { after { confirmRemoveLink = true } }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(String(localized: "Remove this link"), isPresented: $confirmRemoveLink) {
            Button(String(localized: "Delete"), role: .destructive) { removeActiveLink() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "%@ and its servers are removed from this phone. The link itself keeps working, so you can add it again any time."),
                        profiles.activeLink.map { profiles.label(of: $0) } ?? ""))
        }
        .task(id: vpn.isConnected) { await watchLine() }
        .task(id: preparing) { await runProgress() }
        .onChange(of: vpn.readyToUse) { _ in finishPreparing() }
        .onChange(of: vpn.status) { status in
            switch status {
            case .connecting, .reasserting: raise(to: 55)
            case .connected: raise(to: 95)
            case .disconnected, .invalid: if preparing, !findingFastest { closePreparing() }
            default: break
            }
        }
        .onChange(of: profiles.pendingLink) { _ in takePendingLink() }
        .onAppear {
            takePendingLink()
            switch DemoRouter.screen {
            case "settings": showSettings = true
            case "links": after { showLinks = true }
            case "add": after { showAddLink = true }
            case "connecting":
                // The connecting screen, held at a fixed point for the picture.
                progress = 64
                progressCap = 64
                preparing = true
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
                .accessibilityIdentifier("connect")
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

    /// The link in use competes in "Auto", as on Android; WARP is chosen by hand.
    private var contenders: [ServerProfile] { profiles.linkServers }

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
                #if DEBUG
                let _ = print("[log] [links] server menu: \(contenders.count) servers; \(profiles.linkDescription)")
                #endif
                Button { chooseAutomatic() } label: {
                    Label(String(localized: "Auto (fastest)"), systemImage: profiles.isAutomatic ? "checkmark" : "bolt")
                }
                ForEach(contenders) { p in
                    Button { choose(p) } label: {
                        let chosen = !profiles.isAutomatic && p.id == profiles.selectedId
                        Label(menuTitle(p), systemImage: chosen ? "checkmark" : (p.flag == nil ? "server.rack" : "globe"))
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
            // A Menu keeps its items until its label changes; after a link switch the label can stay
            // "Auto (fastest)", so a new identity per link makes it list that link's servers.
            .id(profiles.activeLink?.url ?? "")
            .accessibilityIdentifier("serverMenu")
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
            if !profiles.latenciesAreFresh { await profiles.pingAll(only: contenders, markFresh: true) }
            await moveToBestIfConnected()
        }
    }

    private func choose(_ p: ServerProfile) {
        profiles.choose(p)
        if vpn.isConnected { Task { await vpn.reconnect(profile: p) } }
    }

    private func testAgain() async {
        await profiles.pingAll(only: contenders, markFresh: true)
        // Auto means the best line of the latest test: re-pick, and move over if connected.
        if profiles.isAutomatic { await moveToBestIfConnected() }
    }

    private func moveToBestIfConnected() async {
        let current = profiles.selectedId
        guard let best = profiles.selectFastest(), best.id != current, vpn.isConnected else { return }
        await vpn.reconnect(profile: best)
    }

    // MARK: Account

    /// The link in use.
    private var account: SubscriptionInfo? { profiles.activeLink }

    private var accountCard: some View {
        EthaCard {
            VStack(alignment: .leading, spacing: 16) {
                // With several links the name opens the list of them: switch, add, remove.
                Button { if account != nil { showLinks = true } } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: accountTitle)
                            .font(.system(size: 22, weight: .semibold)).foregroundColor(Etha.ink).lineLimit(1)
                        if profiles.subscriptions.count > 1 {
                            Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundColor(Etha.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("linkName")
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
                // A second (third…) link; it becomes the one in use, and the name above switches back.
                Button { showAddLink = true } label: { Text("+ Add another link").font(.system(size: 17, weight: .medium)) }
                    .foregroundColor(Etha.brand)
                    .frame(maxWidth: .infinity)
                    .disabled(profiles.isImporting)
                // Also in "Your links"; here in plain sight.
                if account != nil {
                    Button { confirmRemoveLink = true } label: { Text("Remove this link").font(.system(size: 17, weight: .medium)) }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .disabled(profiles.isImporting)
                        .accessibilityIdentifier("removeLink")
                }
            }
        }
    }

    private var accountTitle: String {
        guard let link = account, let i = profiles.subscriptions.firstIndex(of: link) else {
            return String(localized: "My servers")
        }
        return profiles.linkLabels[i]
    }

    // MARK: Several links

    /// A link opened from Telegram: added exactly as if it had been pasted.
    private func takePendingLink() {
        guard let link = profiles.pendingLink else { return }
        profiles.pendingLink = nil
        Task { await importLink(link) }
    }

    /// A dialog cannot open while another is closing; the next one waits a moment.
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    /// Home moves to that link; while connected, the connection moves to its best line.
    private func switchLink(to url: String) {
        guard url != profiles.activeLink?.url else { return }
        profiles.useLink(url)
        if let link = profiles.activeLink { show(String(format: String(localized: "Using %@"), profiles.label(of: link))) }
        moveToLinkIfConnected()
    }

    private func moveToLinkIfConnected() {
        guard vpn.isConnected else { return }
        let current = profiles.selectedId
        Task {
            findingFastest = true
            let target = await profiles.connectionTarget()
            findingFastest = false
            if let target, target.id != current { await vpn.reconnect(profile: target) }
        }
    }

    /// The link in use and its servers leave the phone; the others stay.
    private func removeActiveLink() {
        guard let link = profiles.activeLink else { return }
        if vpn.isConnected, profiles.selectedProfile?.subscriptionURL == link.url { vpn.disconnect() }
        profiles.removeSubscription(link.url)
        show(String(localized: "Link removed"))
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

    /// Connect, or disconnect when connected. A tap while a connection is already on its way
    /// (this one, the automatic connect after adding a link, iOS's own reconnect) does nothing:
    /// it used to stop it, and the internet dropped a second after "Connected".
    private func tapConnect() {
        // Connected, or a connect this screen is not holding (iOS's own, a stuck one): a tap
        // stops it. A second tap during this app's own connect is held by the connecting screen.
        if vpn.isConnected || vpn.status == .reasserting || (vpn.status == .connecting && !preparing) {
            vpn.disconnect()
            return
        }
        guard !preparing, vpn.status != .disconnecting else { return }
        if !vpn.isDemo { startPreparing() }
        Task {
            findingFastest = profiles.isAutomatic && contenders.count > 1 && !profiles.latenciesAreFresh
            let target = await profiles.connectionTarget()
            findingFastest = false
            guard let target else {
                closePreparing()
                return
            }
            raise(to: 45)
            // connect, never toggle: whatever happened during the line test, this tap means on.
            if vpn.isConnected || vpn.isBusy { return }
            await vpn.connect(profile: target, userTapped: true)
            // A start the system refused outright (no permission) changes no status: the screen
            // must not wait for one. Otherwise it closes on readyToUse, or on a failed connect.
            if vpn.lastError != nil { closePreparing() }
        }
    }

    // MARK: Connecting screen

    /// Covers Home from the tap on Connect until the connection is ready to use: the best line
    /// is picked, the tunnel comes up, and the ad that comes first loads through it. The figure
    /// climbs toward the stage reached and never stops, so a slow step still shows movement.
    private var connectingScreen: some View {
        ZStack {
            Etha.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(verbatim: "\(Int(progress))%")
                    .font(.system(size: 44, weight: .bold)).foregroundColor(Etha.ink)
                    .monospacedDigit()
                ProgressView(value: progress, total: 100)
                    .tint(Etha.brand)
                    .scaleEffect(x: 1, y: 2.2, anchor: .center)
                    .padding(.horizontal, 8)
                Text("Connecting…").font(.system(size: 18, weight: .semibold)).foregroundColor(Etha.ink)
                    .padding(.top, 8)
                Text("Getting your connection ready. A short ad plays, then you're connected.")
                    .font(.system(size: 15)).foregroundColor(Etha.muted)
                    .multilineTextAlignment(.center)
                if preparingSeconds >= 15 {
                    Button(String(localized: "Cancel")) { cancelConnecting() }
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Etha.brand)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: 520)
        }
        .contentShape(Rectangle())
        .onTapGesture {}   // nothing underneath is tappable while it is up
        .transition(.opacity)
    }

    private func startPreparing() {
        preparingSeconds = 0
        progress = 0
        progressCap = 30
        preparing = true
    }

    private func raise(to cap: Double) {
        if preparing { progressCap = max(progressCap, cap) }
    }

    private func runProgress() async {
        guard preparing, DemoRouter.screen != "connecting" else { return }
        var elapsed = 0.0
        while preparing, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
            elapsed += 0.1
            preparingSeconds = Int(elapsed)
            progress += (progressCap - progress) * 0.05
            if elapsed > 90 { closePreparing() }   // never a screen that stays
        }
    }

    /// The screen closes for its own reason (cap, failed start, Cancel): the ad it was waiting
    /// for must not pop up over Home later.
    private func closePreparing() {
        preparing = false
        AdsManager.shared.cancelPending()
    }

    /// Cancel on the connecting screen: stop the connect and close.
    private func cancelConnecting() {
        vpn.disconnect()
        closePreparing()
    }

    /// Ready: 100%, a moment to see it, and the screen goes.
    private func finishPreparing() {
        guard preparing else { return }
        progressCap = 100
        progress = 100
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            preparing = false
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
        let linksBefore = Set(profiles.subscriptions.map(\.url))
        let hadLink = profiles.activeLink != nil
        // A subscription is judged by its own fetch, a link added again included: its old servers
        // alone would read "added" for a link the server no longer knows.
        var works = false
        var subscriptionURL: String?
        profiles.message = nil
        if ShareLinkParser.containsShareLink(text) {
            _ = await profiles.importText(text)
            works = profiles.profiles.count > before
        } else if let resolved = SubscriptionLinkResolver.resolve(text) {
            works = await profiles.importSubscription(text)
            subscriptionURL = resolved.url
        } else {
            show(String(localized: "No link found. In Telegram, tap your link — it opens here."))
            return
        }
        guard works else {
            show(profiles.message ?? String(localized: "This link could not be read. It may no longer be valid: ask support for a new one."))
            return
        }
        show(String(localized: "Subscription added"))
        // The link just added (or added again) is the one in use from now on, as on Android.
        let target = profiles.subscriptions.first(where: { !linksBefore.contains($0.url) })?.url
            ?? subscriptionURL.flatMap { profiles.storedLink(for: $0) }   // or its account under another address
        if let target, target != profiles.activeLink?.url {
            profiles.useLink(target)
            if hadLink { moveToLinkIfConnected() }
        }
        if !vpn.isConnected, !vpn.isBusy, !preparing { tapConnect() }
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
            await profiles.pingAll(only: contenders, markFresh: true)
            let next = contenders
                .filter { $0.id != current.id && ($0.latencyMs ?? -1) > 0 }
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

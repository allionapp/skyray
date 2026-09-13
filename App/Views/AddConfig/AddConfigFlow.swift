import SwiftUI

/// The guided "Add a config" flow: three ways in (clipboard, QR code, typing),
/// one check that tells single servers from subscriptions itself, and a result.
struct AddConfigFlow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ChooserView(onDone: { dismiss() })
                .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .accentColor(Sky.accent)
    }
}

// MARK: - 02 Chooser

struct ChooserView: View {
    let onDone: () -> Void
    @State private var clipboardHasText = false
    @State private var goPaste = false
    @State private var goScan = false
    @State private var goCheck = false
    @State private var goDemoAdded = false
    @State private var clipboardLink = ""
    @State private var clipboardEmpty = false
    @EnvironmentObject private var profiles: ProfilesViewModel

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BackButton(title: "Close") { onDone() }.padding(.bottom, 16)
                    Text("Add a config").font(Sky.heading(30)).foregroundColor(Sky.ink)
                    Text("Use the link or QR code your provider sent. Single servers and subscription links both work.")
                        .font(Sky.body(14)).foregroundColor(Sky.muted(0.65)).padding(.top, 10)
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20).leading()
                Rule()

                option(icon: "doc.on.clipboard", tint: Sky.accent, title: "Paste from clipboard",
                       body: "Copy the link first, then tap here",
                       badge: clipboardHasText ? String(localized: "TEXT ON CLIPBOARD") : nil, highlighted: clipboardHasText) { pasteFromClipboard() }
                if clipboardEmpty {
                    Text("There's no link on the clipboard. Copy it again, or type it in below.")
                        .font(Sky.body(13)).foregroundColor(Sky.accentDeep)
                        .padding(.horizontal, 24).padding(.bottom, 16).leading()
                }
                Rule(strong: false)
                option(icon: "qrcode.viewfinder", tint: Sky.ink, title: "Scan a QR code",
                       body: "Point the camera at the square code on your provider's page") { goScan = true }
                Rule(strong: false)
                option(icon: "keyboard", tint: Sky.ink, title: "Type the link",
                       body: "If you can't copy it, enter it by hand") { goPaste = true }
                Rule()
                Spacer()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundColor(Sky.muted(0.5)).padding(.top, 2)
                    Text("Only add links from a provider you trust. A config link tells the app where all your traffic should go.")
                        .font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
                }
                .padding(.top, 16).padding(.horizontal, 24).padding(.bottom, 24)
                .overlay(Rule().padding(.horizontal, 24), alignment: .top)

                NavigationLink(destination: PasteLinkView(onDone: onDone), isActive: $goPaste) { EmptyView() }.hidden()
                NavigationLink(destination: QRScanView(onDone: onDone), isActive: $goScan) { EmptyView() }.hidden()
                NavigationLink(destination: CheckingView(input: clipboardLink, customName: nil, onDone: onDone), isActive: $goCheck) { EmptyView() }.hidden()
                if let demo = profiles.profiles.first {
                    NavigationLink(destination: AddedView(profile: demo, latencyMs: demo.latencyMs, reachable: true, onDone: onDone).background(Sky.ground.ignoresSafeArea()).navigationBarHidden(true), isActive: $goDemoAdded) { EmptyView() }.hidden()
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationBarHidden(true)
        .onAppear {
            // hasStrings doesn't read the contents, so it raises no paste prompt.
            clipboardHasText = UIPasteboard.general.hasStrings || DemoRouter.screen != nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                switch DemoRouter.screen {
                case "paste": goPaste = true
                case "added": goDemoAdded = true
                default: break
                }
            }
        }
    }

    /// Reads the clipboard only on this tap, and goes straight to the check when
    /// it holds something the app can use, skipping the text box entirely.
    private func pasteFromClipboard() {
        let text = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if ShareLinkParser.containsShareLink(text) || SubscriptionLinkResolver.resolve(text) != nil {
            clipboardEmpty = false
            clipboardLink = text
            goCheck = true
        } else {
            clipboardEmpty = true
        }
    }

    private func option(icon: String, tint: Color, title: LocalizedStringKey, body: LocalizedStringKey,
                        badge: String? = nil, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundColor(tint).frame(width: 24).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Sky.heading(17)).foregroundColor(Sky.ink)
                    Text(body).font(Sky.body(13)).foregroundColor(Sky.muted(0.65)).fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
                            Text(badge).font(Sky.mono(10.5, medium: true))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Sky.accentTint).foregroundColor(Sky.accentTintInk)
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").font(.system(size: 13, weight: .heavy)).foregroundColor(Sky.muted(0.45)).padding(.top, 4)
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .background(highlighted ? Sky.surface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 03 Paste

struct PasteLinkView: View {
    let onDone: () -> Void
    @EnvironmentObject private var profiles: ProfilesViewModel
    @Environment(\.presentationMode) private var presentation
    @State private var text = ""
    @State private var goCheck = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        BackButton(title: "Back") { presentation.wrappedValue.dismiss() }
                        Spacer()
                    }
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
                    Rule()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Enter your link").font(Sky.heading(28)).foregroundColor(Sky.ink)
                        Text("A server link (vless://, vmess://, trojan://, ss://…) or a subscription address (https://…).")
                            .font(Sky.body(14)).foregroundColor(Sky.muted(0.65)).padding(.top, 10).padding(.bottom, 22)

                        BoxedField(label: "Config link", highlighted: true) {
                            TextEditor(text: $text)
                                .font(Sky.mono(12.5)).foregroundColor(Sky.ink)
                                .frame(minHeight: 84)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                                .focused($focused)
                        }
                        HStack(spacing: 10) {
                            Button { if let s = UIPasteboard.general.string { text = s } } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                                .buttonStyle(SecondaryButtonStyle(height: 40, fullWidth: false))
                            Button("Clear") { text = "" }
                                .buttonStyle(SecondaryButtonStyle(height: 40, fullWidth: false))
                                .disabled(text.isEmpty)
                        }
                        .padding(.top, 12)

                        Button {
                            focused = false
                            goCheck = true
                        } label: {
                            HStack { Text("Add"); Spacer(); Image(systemName: "arrow.forward").font(.system(size: 16, weight: .bold)) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.top, 22)
                    }
                    .padding(24)
                    NavigationLink(destination: CheckingView(input: text, customName: nil, onDone: onDone), isActive: $goCheck) { EmptyView() }.hidden()
                }
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
        // The clipboard is only read when the user taps Paste: reading it on
        // appear would raise the system paste prompt before they did anything.
        .onAppear {
            if DemoRouter.screen == "paste", text.isEmpty { text = DemoRouter.sampleLink }
            else { focused = true }
        }
    }
}

// MARK: - 04 Checking (narrated)

/// Runs the real steps: read the link, validate the config, reach the server, measure latency.
@MainActor
final class CheckRunner: ObservableObject {
    enum Step: Int, CaseIterable { case read, details, reach, speed }
    enum State { case pending, running, done, failed }

    @Published var states: [Step: State] = [.read: .pending, .details: .pending, .reach: .pending, .speed: .pending]
    @Published var result: Result?
    @Published var parsedInfo: (address: String, port: Int, kind: String)?

    enum Result { case added(ServerProfile, latencyMs: Int?, reachable: Bool), subscription(url: String, count: Int), unreadable(reason: String), cancelled }

    private var task: Task<Void, Never>?

    var progress: Double {
        let done = states.values.filter { $0 == .done }.count
        return Double(done) / Double(Step.allCases.count)
    }

    func start(input: String, customName: String?, profiles: ProfilesViewModel) {
        task = Task { await run(input: input, customName: customName, profiles: profiles) }
    }

    func cancel() { task?.cancel(); result = .cancelled }

    private func run(input: String, customName: String?, profiles: ProfilesViewModel) async {
        // Subscriptions take a different route: download, then report the count.
        if !ShareLinkParser.containsShareLink(input), SubscriptionLinkResolver.resolve(input) != nil {
            states[.read] = .running
            await profiles.importSubscription(input)
            let url = SubscriptionLinkResolver.resolve(input)?.url ?? input
            let count = profiles.profiles.filter { $0.subscriptionURL == url }.count
            states[.read] = count > 0 ? .done : .failed
            result = count > 0 ? .subscription(url: url, count: count) : .unreadable(reason: profiles.message ?? "")
            return
        }

        states[.read] = .running
        let outcome = await Task.detached { ShareLinkParser.parse(input) }.value
        guard var profile = outcome.profiles.first else {
            states[.read] = .failed
            result = .unreadable(reason: outcome.failures.first?.reason ?? String(localized: "No server links found."))
            return
        }
        if let customName, !customName.trimmingCharacters(in: .whitespaces).isEmpty { profile.name = customName }
        states[.read] = .done
        parsedInfo = (profile.address, profile.port, profile.kindLabel)
        try? await Task.sleep(nanoseconds: 350_000_000)

        states[.details] = .running
        let valid: Bool = await Task.detached { [profile] in
            do {
                if profile.core == .singbox {
                    try SingboxCore.testConfig(try SingboxConfigBuilder.runtimeConfig(outboundJSON: profile.outboundJSON))
                } else {
                    try XrayCore.testConfig(try XrayConfigBuilder.runtimeConfig(outboundJSON: profile.outboundJSON, hasGeoData: false))
                }
                return true
            } catch { return false }
        }.value
        guard valid else {
            states[.details] = .failed
            result = .unreadable(reason: String(localized: "The server details in this link are incomplete."))
            return
        }
        states[.details] = .done
        if Task.isCancelled { return }

        states[.reach] = .running
        let tcp = await TCPPing.measure(host: profile.address, port: profile.port)
        states[.reach] = tcp >= 0 ? .done : .failed
        if Task.isCancelled { return }

        var latency: Int? = nil
        if tcp >= 0 {
            states[.speed] = .running
            let ping: PingResult = await Task.detached { [profile] in
                if profile.core == .singbox { return SingboxCore.ping(outboundJSON: profile.outboundJSON) }
                guard let d = profile.outboundJSON.data(using: .utf8), let ob = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let r = try? XrayCore.ping(outbounds: [ob]).first else { return PingResult(success: false, delayMs: -1, error: "") }
                return r
            }.value
            latency = ping.success ? ping.delayMs : nil
            states[.speed] = ping.success ? .done : .failed
        }
        if Task.isCancelled { return }

        profile.latencyMs = latency ?? (tcp >= 0 ? tcp : -1)
        let added = profiles.add(profile)
        profiles.choose(added)
        result = .added(added, latencyMs: latency ?? (tcp >= 0 ? tcp : nil), reachable: tcp >= 0)
    }
}

struct CheckingView: View {
    let input: String
    let customName: String?
    let onDone: () -> Void
    @EnvironmentObject private var profiles: ProfilesViewModel
    @Environment(\.presentationMode) private var presentation
    @StateObject private var runner = CheckRunner()

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            switch runner.result {
            case .added(let profile, let ms, let reachable):
                AddedView(profile: profile, latencyMs: ms, reachable: reachable, onDone: onDone)
            case .subscription(let url, _):
                SubscriptionAddedView(url: url, onDone: onDone)
            case .unreadable(let reason):
                LinkErrorView(input: input, reason: reason, onEdit: { presentation.wrappedValue.dismiss() }, onDone: onDone)
            case .cancelled:
                Color.clear.onAppear { presentation.wrappedValue.dismiss() }
            case nil:
                checking
            }
        }
        .navigationBarHidden(true)
        .onAppear { if runner.result == nil { runner.start(input: input, customName: customName, profiles: profiles) } }
    }

    private var checking: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule().padding(.top, 20)
            VStack(alignment: .leading, spacing: 0) {
                Text("Checking your link").font(Sky.heading(28)).foregroundColor(Sky.ink)
                Text("This takes a few seconds. You can leave the app open.").font(Sky.body(14)).foregroundColor(Sky.muted(0.65)).padding(.top, 10)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(hex: 0xD7D3D3))
                        Rectangle().fill(Sky.accent).frame(width: geo.size.width * CGFloat(max(0.08, runner.progress)))
                            .animation(.easeInOut, value: runner.progress)
                    }
                }
                .frame(height: 6).padding(.top, 30)

                VStack(spacing: 0) {
                    stepRow("Link read correctly", .read)
                    stepRow("Server details complete", .details)
                    stepRow("Testing the connection…", .reach, doneTitle: "Server reached")
                    stepRow("Measuring speed", .speed, doneTitle: "Speed measured", last: true)
                }
                .padding(.top, 30)

                if let info = runner.parsedInfo {
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker(text: "Reading from the link")
                        VStack(alignment: .leading, spacing: 8) {
                            infoRow("Address", info.address)
                            infoRow("Port", "\(info.port)")
                            infoRow("Type", info.kind)
                        }
                    }
                    .padding(16).background(Sky.surface).padding(.top, 26).leading()
                }
            }
            .padding(24)
            Spacer()
            Button("Cancel") { runner.cancel() }.buttonStyle(SecondaryButtonStyle(height: 50)).padding(24)
        }
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundColor(Sky.muted(0.55)).frame(width: 72, alignment: .leading)
            Text(verbatim: value).foregroundColor(Sky.ink)
        }
        .font(Sky.mono(12.5))
    }

    private func stepRow(_ title: LocalizedStringKey, _ step: CheckRunner.Step, doneTitle: LocalizedStringKey? = nil, last: Bool = false) -> some View {
        let state = runner.states[step] ?? .pending
        return HStack(spacing: 14) {
            switch state {
            case .done: Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundColor(Sky.accent).frame(width: 18, height: 18)
            case .failed: Image(systemName: "xmark").font(.system(size: 15, weight: .black)).foregroundColor(Sky.accentDeep).frame(width: 18, height: 18)
            case .running: ProgressView().tint(Sky.accent).frame(width: 18, height: 18)
            case .pending: Rectangle().stroke(Sky.divider(), lineWidth: 2).frame(width: 18, height: 18)
            }
            Text(state == .done ? (doneTitle ?? title) : title).font(Sky.semibold(15)).foregroundColor(Sky.ink)
            Spacer()
        }
        .opacity(state == .pending ? 0.4 : 1)
        .padding(.vertical, 14)
        .overlay(Rule(strong: last), alignment: .bottom)
    }
}

// MARK: - 05 Added

struct AddedView: View {
    let profile: ServerProfile
    let latencyMs: Int?
    let reachable: Bool
    let onDone: () -> Void
    @EnvironmentObject private var vpn: VPNManager
    @EnvironmentObject private var profiles: ProfilesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Kicker(text: reachable ? "Config added" : "Config added · not reached yet", color: Sky.onField)
                        Spacer()
                        CloseOnField(action: onDone)
                    }
                    Text(profile.name).font(Sky.heading(42)).foregroundColor(Sky.onField).lineLimit(3).minimumScaleFactor(0.6).padding(.top, 14)
                    Text(verbatim: "\(profile.address):\(profile.port)" + (latencyMs.map { " · \($0) ms" } ?? ""))
                        .font(Sky.mono(12.5, medium: true)).foregroundColor(Sky.onField).padding(.top, 16)
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 26).leading()
                .background(reachable ? Sky.accent : Sky.ink)

                VStack(alignment: .leading, spacing: 0) {
                    Text(reachable ? "The server works. Turn it on now, or pick it any time from the server card on Home."
                                   : "The server was saved but did not answer just now. You can still try to connect, or check the link with your provider.")
                        .font(Sky.body(15)).foregroundColor(Sky.muted(0.75)).padding(.bottom, 22)
                    VStack(spacing: 10) {
                        Button {
                            Task { await vpn.reconnect(profile: profile); onDone() }
                        } label: { HStack { Text("Connect now"); Spacer(); Image(systemName: "power").font(.system(size: 16, weight: .bold)) } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
    }
}

/// What a subscription brought in: every server with its ping and real delay,
/// each with its own Connect, plus a shortcut to whichever tests fastest.
struct SubscriptionAddedView: View {
    let url: String
    let onDone: () -> Void
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    /// TCP handshake times; transient, only this screen shows them.
    @State private var tcp: [UUID: Int] = [:]
    @State private var testing = true
    @State private var connectingId: UUID?
    @State private var connectingFastest = false

    private var servers: [ServerProfile] {
        let list = profiles.profiles.filter { $0.subscriptionURL == url }
        // Reordering while results arrive would move rows under the finger.
        guard !testing else { return list }
        return list.sorted { rank($0) < rank($1) }
    }

    private func rank(_ p: ServerProfile) -> Int {
        guard let ms = p.latencyMs else { return Int.max }
        return ms < 0 ? Int.max - 1 : ms
    }

    private var title: String? { profiles.subscriptions.first { $0.url == url }?.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Kicker(text: "Subscription added", color: Sky.onField)
                    Spacer()
                    CloseOnField(action: onDone)
                }
                Text(String(format: String(localized: "%d servers"), servers.count)).font(Sky.heading(42)).foregroundColor(Sky.onField).padding(.top, 6)
                if let title { Text(title).font(Sky.mono(12.5, medium: true)).foregroundColor(Sky.onField).padding(.top, 10) }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 22).leading().background(Sky.accent)

            VStack(alignment: .leading, spacing: 10) {
                Button(action: connectFastest) {
                    HStack {
                        Text(connectingFastest ? "Finding the fastest server…" : "Connect to the fastest")
                        Spacer()
                        if connectingFastest { ProgressView().tint(Sky.onField) } else { Image(systemName: "bolt.fill").font(.system(size: 16, weight: .bold)) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(connectingFastest || connectingId != nil)
                HStack(spacing: 8) {
                    if testing {
                        ProgressView().scaleEffect(0.8)
                        Text(String(format: String(localized: "Testing %d of %d…"), profiles.pingProgress.done, profiles.pingProgress.total))
                    } else {
                        Text("Or pick a server yourself. Fastest first.")
                    }
                }
                .font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
                .padding(.top, 4)
            }
            .padding(24)
            Rule()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(servers) { server in
                        row(server)
                        Rule(strong: false)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
        .task { await runTests() }
    }

    private func row(_ p: ServerProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(p.name).font(Sky.semibold(15)).foregroundColor(Sky.ink).lineLimit(1).truncationMode(.middle)
                Text(verbatim: p.kindLabel).font(Sky.mono(10.5)).foregroundColor(Sky.muted(0.5)).lineLimit(1)
                HStack(spacing: 14) {
                    metric("Ping", tcp[p.id])
                    metric("Delay", testing && p.latencyMs == nil ? nil : (p.latencyMs ?? -1))
                }
            }
            Spacer(minLength: 8)
            Button {
                connectingId = p.id
                Task {
                    profiles.choose(p)
                    await vpn.reconnect(profile: p)
                    onDone()
                }
            } label: {
                if connectingId == p.id { ProgressView().tint(Sky.onField).frame(width: 64) } else { Text("Connect") }
            }
            .buttonStyle(PrimaryButtonStyle(height: 38, fullWidth: false))
            .disabled(connectingId != nil || connectingFastest)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    /// nil while the test is still running; -1 when the server didn't answer.
    private func metric(_ label: LocalizedStringKey, _ ms: Int?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(Sky.semibold(10.5)).foregroundColor(Sky.muted(0.5))
            if let ms {
                Circle().fill(color(ms)).frame(width: 6, height: 6)
                Text(verbatim: ms < 0 ? "—" : "\(ms) ms").font(Sky.mono(11.5, medium: true))
                    .foregroundColor(ms < 0 ? Sky.muted(0.45) : Sky.ink)
            } else {
                ProgressView().scaleEffect(0.55).frame(width: 14, height: 10)
            }
        }
    }

    private func color(_ ms: Int) -> Color {
        if ms < 0 { return Sky.accentDeep }
        if ms < 700 { return Color(hex: 0x1E9E5A) }
        if ms < 1500 { return Color(hex: 0xE0A100) }
        return Sky.accent
    }

    private func runTests() async {
        let list = profiles.profiles.filter { $0.subscriptionURL == url }
        for i in profiles.profiles.indices where profiles.profiles[i].subscriptionURL == url {
            var p = profiles.profiles[i]; p.latencyMs = nil; profiles.update(p)
        }
        async let delays: Void = profiles.pingAll(only: list)
        await withTaskGroup(of: (UUID, Int).self) { group in
            var next = 0
            func enqueue() {
                guard next < list.count else { return }
                let p = list[next]; next += 1
                group.addTask { (p.id, await TCPPing.measure(host: p.address, port: p.port)) }
            }
            for _ in 0..<8 { enqueue() }
            for await (id, ms) in group {
                tcp[id] = ms
                enqueue()
            }
        }
        await delays
        // A test started elsewhere (after-update setting) makes ours a no-op; its results still land here.
        while profiles.isPinging { try? await Task.sleep(nanoseconds: 200_000_000) }
        testing = false
    }

    private func connectFastest() {
        connectingFastest = true
        Task {
            while testing { try? await Task.sleep(nanoseconds: 200_000_000) }
            profiles.isAutomatic = true
            let fastest = servers.first { ($0.latencyMs ?? -1) > 0 }
            if let fastest { profiles.select(fastest) }
            if let target = fastest ?? profiles.selectedProfile { await vpn.reconnect(profile: target) }
            onDone()
        }
    }
}

/// Close button for the red result headers.
private struct CloseOnField: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .heavy)).foregroundColor(Sky.onField)
                .frame(width: 36, height: 36)
                .overlay(Rectangle().stroke(Sky.onField.opacity(0.6), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
    }
}

// MARK: - 06 Error

struct LinkErrorView: View {
    let input: String
    let reason: String
    let onEdit: () -> Void
    let onDone: () -> Void
    @State private var goScan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 18, weight: .bold))
                    Kicker(text: "Couldn't read this link", color: Sky.accentDeep)
                }
                .foregroundColor(Sky.accentDeep)
                Text("Something's missing from the link").font(Sky.heading(28)).foregroundColor(Sky.ink).padding(.top, 14)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 22).leading()
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("It looks like part of it got cut off when it was copied. Links usually end with a name after a #.")
                        .font(Sky.body(14)).foregroundColor(Sky.muted(0.7)).padding(.bottom, 18)
                    HStack(spacing: 0) {
                        Rectangle().fill(Sky.accent).frame(width: 4)
                        Text(verbatim: String(input.prefix(120)) + (input.count > 120 ? "…" : ""))
                            .font(Sky.mono(12)).foregroundColor(Sky.muted(0.8)).padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .background(Sky.surface)
                    if !reason.isEmpty {
                        Text(reason).font(Sky.mono(11)).foregroundColor(Sky.muted(0.5)).padding(.top, 8)
                    }
                    Kicker(text: "Try this").padding(.top, 24).padding(.bottom, 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Go back to where you copied it")
                        Text("2. Select the whole line, from start to end")
                        Text("3. Copy again and come back — we'll paste it for you")
                    }
                    .font(Sky.body(14)).foregroundColor(Sky.muted(0.75))
                    VStack(spacing: 10) {
                        Button("Edit the link") { onEdit() }.buttonStyle(PrimaryButtonStyle(fill: Sky.accent))
                        Button("Scan a QR code instead") { goScan = true }.buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.top, 26)
                    NavigationLink(destination: QRScanView(onDone: onDone), isActive: $goScan) { EmptyView() }.hidden()
                }
                .padding(24)
            }
            Rule()
            Text("Still stuck? Ask your provider for a QR code — it can't be cut off.")
                .font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6)).padding(24)
        }
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
    }
}

// MARK: - 07 QR scan

struct QRScanView: View {
    let onDone: () -> Void
    @Environment(\.presentationMode) private var presentation
    @State private var code: String?
    @State private var goCheck = false
    @State private var torch = false

    var body: some View {
        ZStack {
            Color(hex: 0x201E1D).ignoresSafeArea()
            QRScannerView(torchOn: torch) { value in
                guard code == nil else { return }
                code = value
                goCheck = true
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    BackButton(title: "Back") { presentation.wrappedValue.dismiss() }
                        .foregroundColor(Color(hex: 0xFF9783))
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.top, 16)
                Spacer()
                ZStack {
                    Rectangle().stroke(Sky.onField.opacity(0.25), lineWidth: 1)
                    ForEach(0..<4, id: \.self) { i in
                        Corner().stroke(Sky.accent, lineWidth: 4).frame(width: 38, height: 38)
                            .rotationEffect(.degrees(Double(i) * 90))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading][i])
                    }
                    Rectangle().fill(Sky.accent).frame(height: 2).offset(y: 6)
                }
                .frame(width: 236, height: 236)
                Text("Hold the square code inside the frame. It adds itself as soon as it's read.")
                    .font(Sky.body(15)).foregroundColor(Sky.onField.opacity(0.85)).frame(maxWidth: 270, alignment: .leading).padding(.top, 26)
                Spacer()
                Rectangle().fill(Sky.onField.opacity(0.35)).frame(height: 2)
                Button { torch.toggle() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill").foregroundColor(Sky.onField)
                            .frame(width: 44, height: 44).overlay(Rectangle().stroke(Sky.onField.opacity(0.3), lineWidth: 1))
                        Text("Flashlight").font(Sky.semibold(13)).foregroundColor(Sky.onField.opacity(0.8))
                        Spacer()
                    }
                    .padding(24)
                }
                .buttonStyle(.plain)
            }
            NavigationLink(destination: CheckingView(input: code ?? "", customName: nil, onDone: onDone), isActive: $goCheck) { EmptyView() }.hidden()
        }
        .navigationBarHidden(true)
    }

    private struct Corner: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return p
        }
    }
}

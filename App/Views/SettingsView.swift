import SwiftUI

/// The full settings, in the Modernist theme: one column, uppercase section kickers on strong
/// rules, square toggles, mono values. Reached from Settings once expert mode is on (seven taps
/// on the version in About), as the Android build keeps its full v2rayNG screens.
struct FullSettingsView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionToRemove: SubscriptionInfo?

    var body: some View {
        NavigationView {
            ZStack {
                Sky.ground.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            subscriptions
                            routing
                            connection
                            appearance
                            advanced
                            privacy
                        }
                        .padding(.bottom, 40)
                    }
                }
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .navigationBarHidden(true)
            .onChange(of: vpn.settings.connectOnDemand) { _ in Task { await vpn.applySettingsToConfiguration() } }
            .onChange(of: vpn.settings.killSwitch) { _ in Task { await vpn.applySettingsToConfiguration() } }
            .onChange(of: vpn.settings.keepAliveOnSleep) { _ in Task { await vpn.applySettingsToConfiguration() } }
            .alert(String(format: String(localized: "Remove subscription \"%@\" and its servers?"), subscriptionToRemove?.title ?? subscriptionToRemove?.url ?? ""),
                   isPresented: Binding(get: { subscriptionToRemove != nil }, set: { if !$0 { subscriptionToRemove = nil } })) {
                Button(String(localized: "Remove"), role: .destructive) {
                    if let sub = subscriptionToRemove { profiles.removeSubscription(sub.url) }
                    subscriptionToRemove = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { subscriptionToRemove = nil }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "SkyRay \(appVersion)").font(Sky.mono(11, medium: true)).foregroundColor(Sky.muted(0.5))
                Text("Settings").font(Sky.heading(34)).foregroundColor(Sky.ink)
            }
            Spacer()
            IconButton(systemName: "xmark", accessibility: "Close") { dismiss() }.padding(.top, 4)
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
        .overlay(Rule(), alignment: .bottom)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (\(build))"
    }

    // MARK: Routing

    private var routing: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Routing")
            RadioRow(title: "Proxy all, bypass LAN", detail: "Everything except your local network goes through the server.",
                     selected: vpn.settings.routingMode == .proxyAll) { vpn.settings.routingMode = .proxyAll }
            Rule(strong: false)
            RadioRow(title: "Bypass Iran and LAN", detail: "Iranian sites and your local network stay direct; the rest goes through the server.",
                     selected: vpn.settings.routingMode == .bypassIran) { vpn.settings.routingMode = .bypassIran }
            Rule(strong: false)
            RadioRow(title: "Global (everything)", detail: "Everything, including your local network, goes through the server.",
                     selected: vpn.settings.routingMode == .global) { vpn.settings.routingMode = .global }
            Rule()
            ToggleRow(title: "Block ads and trackers", detail: "A compact list of ad and tracker domains is dropped inside the tunnel.", isOn: $vpn.settings.blockAds)
            Rule()
            Footnote("Changes apply the next time you connect.")
        }
    }

    // MARK: Connection

    private var connection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Connection")
            ToggleRow(title: "Connect automatically when the app opens", isOn: $vpn.settings.autoConnectOnLaunch)
            if vpn.settings.autoConnectOnLaunch {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Auto-connect to")
                    Segmented(options: [("Last used server", AutoConnectChoice.lastUsed), ("Fastest server", .fastest)],
                              selection: $vpn.settings.autoConnectChoice)
                }
                .padding(.horizontal, 24).padding(.bottom, 18)
            }
            Rule(strong: false)
            ToggleRow(title: "Connect on demand (auto-reconnect)", detail: "iOS brings the tunnel back whenever it drops.", isOn: $vpn.settings.connectOnDemand)
            Rule(strong: false)
            ToggleRow(title: "Kill switch", detail: "Blocks all traffic while the tunnel is down.", isOn: $vpn.settings.killSwitch)
            Rule(strong: false)
            ToggleRow(title: "Stay connected while the screen is locked", isOn: $vpn.settings.keepAliveOnSleep)
            Rule()
        }
        .animation(.easeInOut(duration: 0.15), value: vpn.settings.autoConnectOnLaunch)
    }

    // MARK: Subscriptions

    private var subscriptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Your subscriptions", trailing: profiles.subscriptions.isEmpty ? nil : "\(profiles.subscriptions.count)")
            if profiles.subscriptions.isEmpty {
                Footnote("No subscriptions yet. Add one with the + on Home.")
            } else {
                ForEach(profiles.subscriptions) { sub in
                    subscriptionRow(sub)
                    Rule(strong: false)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Update automatically")
                    Segmented(options: [("Off", 0), ("1h", 1), ("6h", 6), ("12h", 12), ("Daily", 24)],
                              selection: $vpn.settings.subscriptionAutoUpdateHours)
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
            }
            Rule()
        }
    }

    private func subscriptionRow(_ sub: SubscriptionInfo) -> some View {
        let updating = profiles.updatingSubscriptionURL == sub.url
        let count = profiles.profiles.filter { $0.subscriptionURL == sub.url }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sub.title ?? sub.url).font(Sky.semibold(15)).foregroundColor(Sky.ink).lineLimit(1)
                    Text(verbatim: sub.url).font(Sky.mono(11)).foregroundColor(Sky.muted(0.5)).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button {
                    Task { await profiles.importSubscription(sub.url) }
                } label: {
                    if updating { ProgressView().scaleEffect(0.7).frame(width: 44) } else { Text("Update") }
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(profiles.isImporting)
                Button("Remove") { subscriptionToRemove = sub }.buttonStyle(ChipButtonStyle())
            }
            if let total = sub.total, total > 0, let used = sub.used {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Sky.ink.opacity(0.15))
                        Rectangle().fill(Sky.accent).frame(width: geo.size.width * CGFloat(min(1, Double(used) / Double(total))))
                    }
                }
                .frame(height: 6).padding(.top, 4)
                Text(String(format: String(localized: "%@ of %@ used"),
                            ByteCountFormatter.string(fromByteCount: used, countStyle: .binary),
                            ByteCountFormatter.string(fromByteCount: total, countStyle: .binary)))
                    .font(Sky.mono(11.5)).foregroundColor(Sky.muted(0.6))
            }
            Text(verbatim: subscriptionFacts(sub, count: count))
                .font(Sky.mono(11.5)).foregroundColor(sub.isExpired || sub.expiresSoon ? Sky.accentDeep : Sky.muted(0.55))
            if let announce = sub.announce, !announce.isEmpty {
                Text(announce).font(Sky.body(12.5)).foregroundColor(Sky.muted(0.7)).padding(.top, 2)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16).leading()
    }

    private func subscriptionFacts(_ sub: SubscriptionInfo, count: Int) -> String {
        var parts = [String(format: String(localized: "%d servers"), count)]
        if let expire = sub.expire {
            parts.append(String(format: String(localized: "Expires %@"), expire.formatted(date: .abbreviated, time: .omitted)))
        }
        parts.append(String(format: String(localized: "Updated %@"), sub.lastUpdated.formatted(.relative(presentation: .named))))
        return parts.joined(separator: " · ")
    }

    // MARK: Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "More")
            NavRow(title: "Advanced") { AdvancedSettingsView() }
            Rule(strong: false)
            NavRow(title: "Backup & share") { BackupView() }
            Rule()
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Appearance")
            VStack(alignment: .leading, spacing: 8) {
                Kicker(text: "Theme")
                Segmented(options: [("System", AppTheme.system), ("Light", .light), ("Dark", .dark)], selection: $vpn.settings.theme)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Rule()
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Privacy")
            Footnote("SkyRay has no analytics of its own. It talks to the servers you add, your subscription URLs, and the latency test URL. A short ad shows after you connect; ads are served by Google AdMob, which may use an advertising identifier — see the privacy policy for details.")
            Rule(strong: false)
            LinkRow(title: "Privacy policy", url: AppConstants.privacyPolicyURL)
            Rule(strong: false)
            LinkRow(title: "Support", url: AppConstants.supportURL)
            Rule(strong: false)
            LinkRow(title: "Terms of use", url: AppConstants.termsURL)
            Rule()
            Footnote("Built on Xray-core (MPL-2.0) via libXray and hev-socks5-tunnel (MIT). Geo data from Iran-v2ray-rules.")
        }
    }


}

/// Everything a typical user never needs to touch: custom rules, DNS,
/// anti-censorship tweaks, LAN sharing, core details and the tunnel log.
struct AdvancedSettingsView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.presentationMode) private var presentation
    @State private var log = ""
    @State private var dnsText = ""

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(back: "Settings", title: "Advanced",
                             subtitle: "Leave these as they are unless your provider asks you to change them.") {
                    applyDNS()
                    presentation.wrappedValue.dismiss()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        rules
                        dns
                        antiCensorship
                        latency
                        lan
                        core
                        tunnelLog
                    }
                    .padding(.bottom, 40)
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationBarHidden(true)
        .onAppear {
            log = ProfileStore.shared.readTunnelLog()
            dnsText = vpn.settings.dnsServers.joined(separator: ", ")
        }
        .onDisappear { applyDNS() }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Routing")
            NavRow(title: "Custom rules", detail: "\(vpn.settings.customRules.count)") { RulesView() }
            Rule()
        }
    }

    private var latency: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Speed tests")
            ToggleRow(title: "Test latencies when the app opens", isOn: $vpn.settings.pingOnOpen)
            Rule(strong: false)
            ToggleRow(title: "Test speed after updating subscriptions", isOn: $vpn.settings.pingAfterSubscriptionUpdate)
            Rule()
        }
    }

    // MARK: DNS

    private var dns: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "DNS")
            VStack(alignment: .leading, spacing: 12) {
                BoxedField(label: "Remote DNS") { monoField("https://1.1.1.1/dns-query", text: $vpn.settings.remoteDNS) }
                BoxedField(label: "Direct DNS (Iran)") { monoField("8.8.8.8", text: $vpn.settings.directDNS) }
                BoxedField(label: "Tunnel DNS servers") { monoField("1.1.1.1, 8.8.8.8", text: $dnsText, onCommit: applyDNS) }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            Rule()
            Footnote("Remote DNS may be DoH (https://…), DoT (tls://…) or a plain IP.")
        }
    }

    private func monoField(_ placeholder: String, text: Binding<String>, onCommit: @escaping () -> Void = {}) -> some View {
        TextField(placeholder, text: text, onCommit: onCommit)
            .font(Sky.mono(13)).foregroundColor(Sky.ink)
            .keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
    }

    // MARK: Anti-censorship

    private var antiCensorship: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Anti-censorship")
            ToggleRow(title: "Fragment TLS handshake", detail: "Splits the TLS ClientHello so SNI filters cannot read it.", isOn: $vpn.settings.fragmentEnabled)
            if vpn.settings.fragmentEnabled {
                HStack(alignment: .top, spacing: 10) {
                    BoxedField(label: "Packets") { monoField("tlshello", text: $vpn.settings.fragmentPackets) }
                    BoxedField(label: "Length") { monoField("100-200", text: $vpn.settings.fragmentLength) }
                    BoxedField(label: "Interval (ms)") { monoField("10-20", text: $vpn.settings.fragmentInterval) }
                }
                .padding(.horizontal, 24).padding(.bottom, 18)
            }
            Rule(strong: false)
            ToggleRow(title: "Mux (multiplex connections)", detail: "Carries several connections over one.", isOn: $vpn.settings.muxEnabled)
            Rule()
        }
        .animation(.easeInOut(duration: 0.15), value: vpn.settings.fragmentEnabled)
    }

    // MARK: LAN

    private var lan: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Share proxy on LAN")
            ToggleRow(title: "Allow connections from LAN", isOn: $vpn.settings.allowLAN)
            Rule()
            Footnote(verbatim: String(format: String(localized: "Other devices on your Wi-Fi can use this phone as a proxy: SOCKS5 on port %lld, HTTP on port %lld."),
                                      Int64(AppConstants.socksPort), Int64(vpn.settings.httpPort)))
        }
    }

    private var core: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Core")
            ValueRow(title: "Xray core", value: XrayCore.version())
            Rule(strong: false)
            ValueRow(title: "sing-box core", value: SingboxCore.version())
            Rule(strong: false)
            ValueRow(title: "Local SOCKS port", value: "\(AppConstants.socksPort)")
            Rule(strong: false)
            ValueRow(title: "Servers", value: "\(profiles.profiles.count)")
            if let mem = vpn.stats?.memoryBytes {
                Rule(strong: false)
                ValueRow(title: "Tunnel memory", value: ByteCountFormatter.string(fromByteCount: Int64(mem), countStyle: .memory))
            }
            Rule(strong: false)
            VStack(alignment: .leading, spacing: 8) {
                Kicker(text: "Log level")
                Segmented(options: [("none", "none"), ("error", "error"), ("warning", "warning"), ("info", "info"), ("debug", "debug")],
                          selection: $vpn.settings.logLevel)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Rule()
        }
    }

    // MARK: Log

    private var tunnelLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Tunnel log")
            VStack(alignment: .leading, spacing: 12) {
                if log.isEmpty {
                    Text("No log yet. Connect once to see the tunnel log.").font(Sky.body(13)).foregroundColor(Sky.muted(0.6))
                        .padding(14).leading()
                        .background(Sky.surface)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: log).font(Sky.mono(10.5)).foregroundColor(Sky.ink).textSelection(.enabled)
                            .padding(12).leading()
                    }
                    .frame(height: 220)
                    .background(Sky.surface)
                }
                HStack(spacing: 10) {
                    Button { log = ProfileStore.shared.readTunnelLog() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle(height: 40, fullWidth: false))
                    Button { UIPasteboard.general.string = ProfileStore.shared.readTunnelLog() } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(SecondaryButtonStyle(height: 40, fullWidth: false))
                        .disabled(log.isEmpty)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            Rule()
        }
    }

    private func applyDNS() {
        let servers = dnsText.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !servers.isEmpty { vpn.settings.dnsServers = servers }
    }
}

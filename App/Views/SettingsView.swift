import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss
    @State private var log = ""
    @State private var dnsText = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Routing")) {
                    Picker("Routing mode", selection: $vpn.settings.routingMode) {
                        Text("Proxy all, bypass LAN").tag(RoutingMode.proxyAll)
                        Text("Bypass Iran and LAN").tag(RoutingMode.bypassIran)
                        Text("Global (everything)").tag(RoutingMode.global)
                    }
                    Toggle("Block ads and trackers", isOn: $vpn.settings.blockAds)
                    NavigationLink(destination: RulesView()) {
                        HStack { Text("Custom rules"); Spacer(); Text("\(vpn.settings.customRules.count)").foregroundColor(.secondary) }
                    }
                    Text("Routing, DNS and fragment changes apply on the next connection.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section(header: Text("DNS")) {
                    HStack {
                        Text("Remote DNS")
                        Spacer()
                        TextField("https://1.1.1.1/dns-query", text: $vpn.settings.remoteDNS)
                            .multilineTextAlignment(.trailing).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Direct DNS (Iran)")
                        Spacer()
                        TextField("8.8.8.8", text: $vpn.settings.directDNS)
                            .multilineTextAlignment(.trailing).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Tunnel DNS servers")
                        Spacer()
                        TextField("1.1.1.1, 8.8.8.8", text: $dnsText, onCommit: applyDNS)
                            .multilineTextAlignment(.trailing).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .foregroundColor(.secondary)
                    }
                    Text("Remote DNS may be DoH (https://…), DoT (tls://…) or a plain IP.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section(header: Text("Anti-censorship"), footer: Text("Fragment splits the TLS ClientHello into pieces so SNI-based filtering cannot read it. Mux carries several connections over one.")) {
                    Toggle("Fragment TLS handshake", isOn: $vpn.settings.fragmentEnabled)
                    if vpn.settings.fragmentEnabled {
                        HStack { Text("Packets"); Spacer(); TextField("tlshello", text: $vpn.settings.fragmentPackets).multilineTextAlignment(.trailing).autocorrectionDisabled().textInputAutocapitalization(.never).foregroundColor(.secondary) }
                        HStack { Text("Length"); Spacer(); TextField("100-200", text: $vpn.settings.fragmentLength).multilineTextAlignment(.trailing).foregroundColor(.secondary) }
                        HStack { Text("Interval (ms)"); Spacer(); TextField("10-20", text: $vpn.settings.fragmentInterval).multilineTextAlignment(.trailing).foregroundColor(.secondary) }
                    }
                    Toggle("Mux (multiplex connections)", isOn: $vpn.settings.muxEnabled)
                }
                Section(header: Text("Connection"), footer: Text("Connect on demand asks iOS to re-establish the tunnel automatically whenever it drops. Kill switch blocks all traffic while the tunnel is down.")) {
                    Toggle("Connect automatically when the app opens", isOn: $vpn.settings.autoConnectOnLaunch)
                    if vpn.settings.autoConnectOnLaunch {
                        Picker("Auto-connect to", selection: $vpn.settings.autoConnectChoice) {
                            Text("Last used server").tag(AutoConnectChoice.lastUsed)
                            Text("Fastest server").tag(AutoConnectChoice.fastest)
                        }
                    }
                    Toggle("Connect on demand (auto-reconnect)", isOn: $vpn.settings.connectOnDemand)
                    Toggle("Kill switch", isOn: $vpn.settings.killSwitch)
                    Toggle("Stay connected while the screen is locked", isOn: $vpn.settings.keepAliveOnSleep)
                    Toggle("Test latencies when the app opens", isOn: $vpn.settings.pingOnOpen)
                    Toggle("Test speed after updating subscriptions", isOn: $vpn.settings.pingAfterSubscriptionUpdate)
                }
                Section(header: Text("Share proxy on LAN"), footer: Text("Other devices on your Wi-Fi can use this phone as a proxy: SOCKS5 on port \(AppConstants.socksPort), HTTP on port \(vpn.settings.httpPort).")) {
                    Toggle("Allow connections from LAN", isOn: $vpn.settings.allowLAN)
                }
                Section(header: Text("Subscriptions")) {
                    Picker("Auto-update", selection: $vpn.settings.subscriptionAutoUpdateHours) {
                        Text("Off").tag(0)
                        Text("Every hour").tag(1)
                        Text("Every 6 hours").tag(6)
                        Text("Every 12 hours").tag(12)
                        Text("Daily").tag(24)
                    }
                    Button {
                        Task { await profiles.updateAllSubscriptions() }
                    } label: { Label("Update all subscriptions now", systemImage: "arrow.clockwise") }
                    .disabled(profiles.subscriptions.isEmpty || profiles.isImporting)
                    ForEach(profiles.subscriptions) { sub in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.title ?? sub.url).font(.subheadline).lineLimit(1)
                            if let used = sub.used, let total = sub.total {
                                Text(String(format: String(localized: "%@ of %@ used"),
                                            ByteCountFormatter.string(fromByteCount: used, countStyle: .binary),
                                            ByteCountFormatter.string(fromByteCount: total, countStyle: .binary)))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            if let expire = sub.expire {
                                Text(String(format: String(localized: "Expires %@"), expire.formatted(date: .abbreviated, time: .omitted)))
                                    .font(.caption).foregroundColor(sub.isExpired || sub.expiresSoon ? .red : .secondary)
                            }
                            Text(String(format: String(localized: "Updated %@"), sub.lastUpdated.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                Section(header: Text("Data")) {
                    NavigationLink(destination: BackupView()) { Label("Backup & share", systemImage: "externaldrive") }
                }
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $vpn.settings.theme) {
                        Text("System").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                }
                Section(header: Text("Core")) {
                    row("Xray core", XrayCore.version())
                    row("sing-box core", SingboxCore.version())
                    row("Local SOCKS port", "\(AppConstants.socksPort)")
                    row("Servers", "\(profiles.profiles.count)")
                    if let mem = vpn.stats?.memoryBytes {
                        row("Tunnel memory", ByteCountFormatter.string(fromByteCount: Int64(mem), countStyle: .memory))
                    }
                    Picker("Log level", selection: $vpn.settings.logLevel) {
                        ForEach(["none", "error", "warning", "info", "debug"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section(header: Text("Tunnel log")) {
                    if log.isEmpty {
                        Text("No log yet. Connect once to see the tunnel log.").foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            Text(log).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    Button { log = ProfileStore.shared.readTunnelLog() } label: { Label("Refresh log", systemImage: "doc.text.magnifyingglass") }
                    Button { UIPasteboard.general.string = ProfileStore.shared.readTunnelLog() } label: { Label("Copy log", systemImage: "doc.on.doc") }
                }
                Section(header: Text("Privacy")) {
                    Text("SkyRay has no ads and no analytics. It only talks to the servers you add, your subscription URLs, and the latency test URL.")
                        .font(.footnote).foregroundColor(.secondary)
                    Link(destination: URL(string: AppConstants.privacyPolicyURL)!) { Label("Privacy policy", systemImage: "hand.raised") }
                    Link(destination: URL(string: AppConstants.supportURL)!) { Label("Support", systemImage: "questionmark.circle") }
                    Link(destination: URL(string: AppConstants.termsURL)!) { Label("Terms of use", systemImage: "doc.text") }
                    Text("Built on Xray-core (MPL-2.0) via libXray and hev-socks5-tunnel (MIT). Geo data from Iran-v2ray-rules.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { applyDNS(); dismiss() } } }
            .onAppear {
                log = ProfileStore.shared.readTunnelLog()
                dnsText = vpn.settings.dnsServers.joined(separator: ", ")
            }
            .onChange(of: vpn.settings.connectOnDemand) { _ in Task { await vpn.applySettingsToConfiguration() } }
            .onChange(of: vpn.settings.killSwitch) { _ in Task { await vpn.applySettingsToConfiguration() } }
            .onChange(of: vpn.settings.keepAliveOnSleep) { _ in Task { await vpn.applySettingsToConfiguration() } }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary) }
    }

    private func applyDNS() {
        let servers = dnsText.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !servers.isEmpty { vpn.settings.dnsServers = servers }
    }
}

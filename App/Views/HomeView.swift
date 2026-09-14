import SwiftUI

/// Home: one button and one choice. The big button turns the tunnel on and
/// off; the card under it says which server that will use and opens the picker.
struct HomeView: View {
    @EnvironmentObject private var vpn: VPNManager
    @EnvironmentObject private var profiles: ProfilesViewModel
    @State private var showAdd = false
    @State private var showServers = false
    @State private var showSettings = false
    /// Automatic mode tests every server before connecting; that wait needs its own label.
    @State private var findingFastest = false

    private var onField: Bool { vpn.isConnected }

    var body: some View {
        ZStack {
            (onField ? Sky.accent : Sky.ground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                powerButton
                statusText.padding(.top, 26)
                if vpn.isConnected { liveStats.padding(.top, 18) }
                if let error = vpn.lastError, !vpn.isConnected {
                    Text(error).font(Sky.body(13)).foregroundColor(Sky.accentDeep)
                        .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 14)
                }
                Spacer(minLength: 20)
                if !profiles.profiles.isEmpty { serverCard.padding(24) }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showAdd) { AddConfigFlow() }
        .sheet(isPresented: $showServers) { ServerPickerView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            switch DemoRouter.screen {
            case "servers": showServers = true
            case "chooser", "paste", "added": showAdd = true
            case "settings": showSettings = true
            default: break
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vpn.isConnected)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("SkyRay").font(Sky.heading(17)).foregroundColor(onField ? Sky.onField : Sky.ink)
                Spacer()
                headerIcon("plus", label: "Add a config") { showAdd = true }
                headerIcon("gearshape", label: "Settings") { showSettings = true }
            }
            .padding(.leading, 24).padding(.trailing, 12).padding(.top, 10).padding(.bottom, 6)
            Rule(onField: onField)
        }
    }

    private func headerIcon(_ name: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(onField ? Sky.onField.opacity(0.9) : Sky.ink.opacity(0.75))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(label))
    }

    // MARK: The button

    private var isWorking: Bool { findingFastest || vpn.isBusy }

    private var powerButton: some View {
        Button(action: tapPower) {
            ZStack {
                Circle().fill(onField ? Sky.onField : Sky.paper)
                Circle().stroke(onField ? Sky.onField.opacity(0.35) : Sky.ink.opacity(0.12), lineWidth: 10)
                    .padding(-10)
                if isWorking {
                    ProgressView().scaleEffect(1.6).tint(onField ? Sky.accent : Sky.primary)
                } else {
                    Image(systemName: profiles.profiles.isEmpty ? "plus" : "power")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundColor(onField ? Sky.accent : Sky.primary)
                }
            }
            .frame(width: 184, height: 184)
            .shadow(color: Color.black.opacity(onField ? 0.18 : 0.08), radius: 24, y: 10)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(findingFastest || vpn.status == .disconnecting)
        .accessibilityLabel(Text(vpn.isConnected ? "Disconnect" : "Connect"))
    }

    private var statusText: some View {
        VStack(spacing: 6) {
            Group {
                if findingFastest {
                    Text("Finding the fastest server…")
                } else if vpn.status == .connecting || vpn.status == .reasserting {
                    Text("Connecting…")
                } else if vpn.status == .disconnecting {
                    Text("Disconnecting…")
                } else if vpn.isConnected {
                    Text("Connected")
                } else if profiles.profiles.isEmpty {
                    Text("Add your link to start")
                } else {
                    Text("Tap to connect")
                }
            }
            .font(Sky.heading(22))
            .foregroundColor(onField ? Sky.onField : Sky.ink)
            if vpn.isConnected, let since = vpn.connectedSince {
                Text(since, style: .timer).font(Sky.mono(14, medium: true)).foregroundColor(Sky.onField.opacity(0.9))
            } else if profiles.profiles.isEmpty {
                Text("Your provider gives you a link or a QR code.")
                    .font(Sky.body(14)).foregroundColor(Sky.muted(0.6))
            }
        }
        .multilineTextAlignment(.center)
    }

    private var liveStats: some View {
        HStack(spacing: 28) {
            Label { Text(verbatim: speed(vpn.downloadSpeed)) } icon: { Image(systemName: "arrow.down") }
            Label { Text(verbatim: speed(vpn.uploadSpeed)) } icon: { Image(systemName: "arrow.up") }
        }
        .font(Sky.mono(13, medium: true))
        .foregroundColor(Sky.onField)
    }

    private func tapPower() {
        if vpn.isConnected || vpn.status == .connecting || vpn.status == .reasserting {
            vpn.disconnect()
            return
        }
        guard !profiles.profiles.isEmpty else { showAdd = true; return }
        Task {
            findingFastest = profiles.isAutomatic && profiles.profiles.count > 1 && !profiles.latenciesAreFresh
            let target = await profiles.connectionTarget()
            findingFastest = false
            await vpn.toggle(profile: target)
        }
    }

    // MARK: Server card

    private var serverCard: some View {
        Button { showServers = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: showsAutomatic ? "bolt.fill" : "server.rack")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(onField ? Sky.onField : Sky.primary)
                        .frame(width: 40, height: 40)
                        .background((onField ? Sky.onField : Sky.primary).opacity(0.14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cardTitle).font(Sky.semibold(16)).lineLimit(1).truncationMode(.middle)
                            .foregroundColor(onField ? Sky.onField : Sky.ink)
                        Text(verbatim: cardDetail).font(Sky.mono(11.5)).lineLimit(1)
                            .foregroundColor(onField ? Sky.onField.opacity(0.8) : Sky.muted(0.55))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(onField ? Sky.onField.opacity(0.8) : Sky.muted(0.5))
                }
                if let sub = currentSubscription, sub.total != nil || sub.expire != nil {
                    quota(sub).padding(.top, 14)
                }
            }
            .padding(16)
            .background(onField ? Sky.onField.opacity(0.12) : Sky.paper)
            .overlay(Rectangle().stroke(onField ? Sky.onField.opacity(0.4) : Sky.divider(false), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// With a single server there is nothing to choose between.
    private var showsAutomatic: Bool { profiles.isAutomatic && !vpn.isConnected && profiles.profiles.count > 1 }

    private var cardTitle: String {
        if showsAutomatic { return String(localized: "Automatic · fastest") }
        return profiles.selectedProfile?.name ?? ""
    }

    private var cardDetail: String {
        if showsAutomatic {
            return String(format: String(localized: "Picks the best of %d servers"), profiles.profiles.count)
        }
        guard let p = profiles.selectedProfile else { return "" }
        var parts = [p.protocolName.uppercased()]
        if let ms = p.latencyMs { parts.append(ms < 0 ? "—" : "\(ms) ms") }
        return parts.joined(separator: " · ")
    }

    private var currentSubscription: SubscriptionInfo? {
        let url = profiles.selectedProfile?.subscriptionURL ?? profiles.profiles.first?.subscriptionURL
        guard let url else { return nil }
        return profiles.subscriptions.first { $0.url == url }
    }

    private func quota(_ sub: SubscriptionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let total = sub.total, total > 0, let used = sub.used {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill((onField ? Sky.onField : Sky.ink).opacity(0.15))
                        Rectangle().fill(onField ? Sky.onField : Sky.accent)
                            .frame(width: geo.size.width * CGFloat(min(1, Double(used) / Double(total))))
                    }
                }
                .frame(height: 4)
            }
            Text(verbatim: quotaLine(sub)).font(Sky.mono(11)).lineLimit(1)
                .foregroundColor(onField ? Sky.onField.opacity(0.85)
                                 : (sub.isExpired || sub.expiresSoon ? Sky.accentDeep : Sky.muted(0.6)))
        }
    }

    private func quotaLine(_ sub: SubscriptionInfo) -> String {
        var parts: [String] = []
        if let total = sub.total, total > 0, let left = sub.remaining {
            parts.append(String(format: String(localized: "%@ left"), ByteCountFormatter.string(fromByteCount: left, countStyle: .binary)))
        }
        if let expire = sub.expire {
            let date = expire.formatted(date: .abbreviated, time: .omitted)
            let format = sub.isExpired ? String(localized: "Expired %@") : String(localized: "Expires %@")
            parts.append(String(format: format, date))
        }
        return parts.joined(separator: " · ")
    }

    private func speed(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_048_576
        if mb >= 1 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f KB/s", bytesPerSecond / 1024)
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

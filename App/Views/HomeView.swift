import SwiftUI

/// Home: one decision per screen — which server, and on or off.
/// Three states from the design: no config yet, off with a server chosen,
/// and connected (the red field carries the state).
struct HomeView: View {
    @EnvironmentObject private var vpn: VPNManager
    @EnvironmentObject private var profiles: ProfilesViewModel
    @State private var showAdd = false
    @State private var showServers = false
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                (vpn.isConnected ? Sky.accent : Sky.ground).ignoresSafeArea()
                content
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                NavigationLink(destination: ServerListView(), isActive: $showServers) { EmptyView() }.hidden()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAdd) { AddConfigFlow() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear {
                switch DemoRouter.screen {
                case "servers": showServers = true
                case "chooser", "paste", "added": showAdd = true
                case "settings": showSettings = true
                default: break
                }
            }
        }
        .navigationViewStyle(.stack)
        .animation(.easeInOut(duration: 0.25), value: vpn.isConnected)
    }

    @ViewBuilder private var content: some View {
        if vpn.isConnected {
            connectedState
        } else if profiles.profiles.isEmpty {
            emptyState
        } else {
            offState
        }
    }

    // MARK: Header (brand + settings)

    private func header(onField: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("SkyRay").font(Sky.heading(17)).foregroundColor(onField ? Sky.onField : Sky.ink)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(onField ? Sky.onField.opacity(0.85) : Sky.muted(0.6))
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .accessibilityLabel(Text("Settings"))
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 6)
            Rule(onField: onField)
        }
    }

    // MARK: 2a — no config yet

    private var emptyState: some View {
        VStack(spacing: 0) {
            header(onField: false)
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Rectangle().stroke(Sky.ink.opacity(0.25), lineWidth: 2)
                    .frame(width: 132, height: 132)
                    .overlay(Image(systemName: "power").font(.system(size: 42, weight: .light)).foregroundColor(Sky.ink.opacity(0.3)))
                    .padding(.bottom, 28)
                Text("No server yet").font(Sky.heading(32)).foregroundColor(Sky.ink)
                Text("Add the link or QR code your provider gave you. It takes about a minute.")
                    .font(Sky.body(15)).foregroundColor(Sky.muted(0.65)).padding(.top, 12).frame(maxWidth: 300, alignment: .leading)
                Spacer()
            }
            .padding(.horizontal, 24).leading()
            Rule()
            VStack(spacing: 10) {
                Button { showAdd = true } label: { Label("Add a config", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(24)
        }
    }

    // MARK: 2b — off, server chosen

    private var offState: some View {
        VStack(spacing: 0) {
            header(onField: false)
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "Not connected")
                Text("Off").font(Sky.heading(44)).foregroundColor(Sky.ink).padding(.top, 14)
                Text("Your traffic is going out normally, without the server.")
                    .font(Sky.body(15)).foregroundColor(Sky.muted(0.65)).padding(.top, 14).frame(maxWidth: 300, alignment: .leading)
                if let error = vpn.lastError {
                    Text(error).font(Sky.body(13)).foregroundColor(Sky.accentDeep).padding(.top, 12)
                }
            }
            .padding(.horizontal, 24).padding(.top, 34).leading()
            Rule().padding(.top, 34)
            selectedRow
            Rule()
            if let sub = currentSubscription { quotaRow(sub) }
            Spacer()
            VStack(spacing: 10) {
                Button {
                    Task { await vpn.toggle(profile: profiles.selectedProfile) }
                } label: {
                    HStack { Text("Connect"); Spacer(); if vpn.isBusy { ProgressView().tint(Sky.onField) } else { Image(systemName: "power").font(.system(size: 18, weight: .bold)) } }
                }
                .buttonStyle(PrimaryButtonStyle(height: 64))
                .disabled(vpn.isBusy)
                Button { showAdd = true } label: { Label("Add a config", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle(height: 50))
            }
            .padding(24)
        }
    }

    private var selectedRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(Sky.ink).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Selected server").font(Sky.semibold(10)).tracking(1).textCase(.uppercase).foregroundColor(Sky.muted(0.5)).padding(.bottom, 2)
                Text(profiles.selectedProfile?.name ?? "").font(Sky.semibold(16)).foregroundColor(Sky.ink).lineLimit(1)
                Text(verbatim: addressLine(profiles.selectedProfile)).font(Sky.mono(11.5)).foregroundColor(Sky.muted(0.55)).lineLimit(1)
            }
            Spacer()
            Button("Change") { showServers = true }.buttonStyle(ChipButtonStyle())
        }
        .padding(.vertical, 18).padding(.horizontal, 24)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addressLine(_ p: ServerProfile?) -> String {
        guard let p else { return "" }
        var s = "\(p.address):\(p.port)"
        if let ms = p.latencyMs { s += ms < 0 ? " · —" : " · \(ms) ms" }
        return s
    }

    private func quotaRow(_ sub: SubscriptionInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let total = sub.total, let used = sub.used {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Sky.ink.opacity(0.15))
                        Rectangle().fill(Sky.accent).frame(width: geo.size.width * CGFloat(min(1, Double(used) / Double(max(total, 1)))))
                    }
                }
                .frame(height: 6)
                Text(String(format: String(localized: "%@ of %@ used"),
                            ByteCountFormatter.string(fromByteCount: used, countStyle: .binary),
                            ByteCountFormatter.string(fromByteCount: total, countStyle: .binary)))
                    .font(Sky.mono(11.5)).foregroundColor(Sky.muted(0.6))
            }
            if let expire = sub.expire {
                Text(String(format: String(localized: "Expires %@"), expire.formatted(date: .abbreviated, time: .omitted)))
                    .font(Sky.mono(11.5)).foregroundColor(sub.isExpired || sub.expiresSoon ? Sky.accentDeep : Sky.muted(0.6))
            }
            if let announce = sub.announce, !announce.isEmpty {
                Text(announce).font(Sky.body(12.5)).foregroundColor(Sky.muted(0.7)).padding(.top, 4)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16).leading()
    }

    private var currentSubscription: SubscriptionInfo? {
        guard let url = profiles.selectedProfile?.subscriptionURL else { return nil }
        return profiles.subscriptions.first { $0.url == url }
    }

    // MARK: 2c — connected, red carries the state

    private var connectedState: some View {
        VStack(spacing: 0) {
            header(onField: true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Rectangle().fill(Sky.onField).frame(width: 9, height: 9)
                    Text("Connected").font(Sky.semibold(11)).tracking(1.3).textCase(.uppercase)
                    if let since = vpn.connectedSince {
                        Text("·").font(Sky.semibold(11))
                        Text(since, style: .timer).font(Sky.mono(11, medium: true))
                    }
                }
                .foregroundColor(Sky.onField)
                Text(profiles.selectedProfile?.name ?? "").font(Sky.heading(44)).foregroundColor(Sky.onField)
                    .lineLimit(2).minimumScaleFactor(0.6).padding(.top, 14)
                Text(verbatim: addressLine(profiles.selectedProfile)).font(Sky.mono(12.5, medium: true)).foregroundColor(Sky.onField).padding(.top, 16)
            }
            .padding(.horizontal, 24).padding(.top, 34).leading()
            Rule(onField: true).padding(.top, 30)
            statsGrid
            sparkline
            Spacer()
            Button { vpn.disconnect() } label: {
                HStack { Text("Disconnect"); Spacer(); Image(systemName: "xmark").font(.system(size: 18, weight: .bold)) }
            }
            .buttonStyle(PrimaryButtonStyle(height: 64, fill: Sky.onField, foreground: Sky.fieldInk))
            .padding(24)
        }
    }

    private var statsGrid: some View {
        let s = vpn.stats
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                stat("Down", speed(vpn.downloadSpeed)); Rectangle().fill(Sky.onField.opacity(0.55)).frame(width: 2)
                stat("Up", speed(vpn.uploadSpeed))
            }
            Rule(onField: true)
            HStack(spacing: 0) {
                stat("Ping", pingText); Rectangle().fill(Sky.onField.opacity(0.55)).frame(width: 2)
                stat("Used", (ByteCountFormatter.string(fromByteCount: Int64((s?.rxBytes ?? 0) + (s?.txBytes ?? 0)), countStyle: .binary), ""))
            }
            Rule(onField: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pingText: (String, String) {
        if let ms = profiles.selectedProfile?.latencyMs, ms >= 0 { return ("\(ms)", " ms") }
        return ("—", "")
    }

    private func speed(_ bytesPerSecond: Double) -> (String, String) {
        let mb = bytesPerSecond / 1_048_576
        if mb >= 1 { return (String(format: "%.1f", mb), " MB/s") }
        return (String(format: "%.0f", bytesPerSecond / 1024), " KB/s")
    }

    private func stat(_ label: LocalizedStringKey, _ value: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(Sky.semibold(10)).tracking(1).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value.0).font(Sky.mono(20, medium: true))
                Text(value.1).font(Sky.mono(12, medium: true))
            }
        }
        .foregroundColor(Sky.onField)
        .padding(.vertical, 18).padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Throughput history as bars; the most recent samples are solid.
    private var sparkline: some View {
        let samples = vpn.speedHistory
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(samples.enumerated()), id: \.offset) { i, v in
                Rectangle()
                    .fill(Sky.onField.opacity(i >= samples.count - 3 ? 1 : 0.45))
                    .frame(height: max(2, 54 * CGFloat(v)))
            }
        }
        .frame(height: 54, alignment: .bottom)
        .padding(.horizontal, 24).padding(.top, 20)
        .leading()
    }
}

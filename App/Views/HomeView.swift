import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vpn: VPNManager
    @EnvironmentObject private var profiles: ProfilesViewModel
    @State private var showAdd = false
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let sub = currentSubscription, let announce = sub.announce, !announce.isEmpty {
                    AnnounceBanner(text: announce)
                }
                Spacer()
                connectButton
                Text(vpn.status.label)
                    .font(.title3.weight(.medium))
                    .foregroundColor(vpn.isConnected ? .green : .secondary)
                if vpn.isConnected { statsView }
                if let error = vpn.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
                if let sub = currentSubscription { SubscriptionQuotaView(info: sub) }
                NavigationLink(destination: ServerListView()) { serverCard }
                    .buttonStyle(.plain)
            }
            .padding()
            // Keep the layout phone-like on iPad instead of stretching across 13 inches.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .navigationTitle("SkyRay")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Settings"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Add server"))
                }
            }
            .sheet(isPresented: $showAdd) { AddServerView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .navigationViewStyle(.stack)
    }

    private var currentSubscription: SubscriptionInfo? {
        guard let url = profiles.selectedProfile?.subscriptionURL else { return nil }
        return profiles.subscriptions.first { $0.url == url }
    }

    private var connectButton: some View {
        Button {
            Task { await vpn.toggle(profile: profiles.selectedProfile) }
        } label: {
            ZStack {
                Circle()
                    .fill(vpn.isConnected ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 190, height: 190)
                Circle()
                    .strokeBorder(vpn.isConnected ? Color.green : Color.accentColor, lineWidth: 6)
                    .frame(width: 190, height: 190)
                if vpn.isBusy {
                    ProgressView().scaleEffect(1.6)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(vpn.isConnected ? Color.green : Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(vpn.isBusy)
        .accessibilityLabel(vpn.isConnected ? Text("Disconnect") : Text("Connect"))
    }

    private var statsView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 20) {
                if let since = vpn.connectedSince {
                    Label { Text(since, style: .timer) } icon: { Image(systemName: "clock") }
                }
                if let stats = vpn.stats {
                    Label(ByteCountFormatter.string(fromByteCount: Int64(stats.txBytes), countStyle: .binary), systemImage: "arrow.up")
                    Label(ByteCountFormatter.string(fromByteCount: Int64(stats.rxBytes), countStyle: .binary), systemImage: "arrow.down")
                }
            }
            HStack(spacing: 20) {
                Text("↑ \(speed(vpn.uploadSpeed))")
                Text("↓ \(speed(vpn.downloadSpeed))")
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundColor(.secondary)
    }

    private func speed(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    private var serverCard: some View {
        HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    if let p = profiles.selectedProfile {
                        Text(p.name).font(.headline).lineLimit(1)
                        Text(p.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    } else {
                        Text("No server").font(.headline)
                        Text("Tap + to add a server").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let ms = profiles.selectedProfile?.latencyMs { LatencyBadge(ms: ms) }
                Image(systemName: "chevron.forward").foregroundColor(Color.secondary.opacity(0.5))
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

struct AnnounceBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "megaphone").foregroundColor(.orange)
            Text(text).font(.footnote).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LatencyBadge: View {
    let ms: Int
    var body: some View {
        Text(ms < 0 ? String(localized: "timeout") : "\(ms) ms")
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundColor(color)
    }
    private var color: Color {
        if ms < 0 { return .red }
        if ms < 300 { return .green }
        if ms < 800 { return .orange }
        return .red
    }
}

/// Remaining traffic, expiry and provider links from the subscription headers.
struct SubscriptionQuotaView: View {
    let info: SubscriptionInfo
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill").foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                if let total = info.total, let used = info.used {
                    ProgressView(value: min(1, Double(used) / Double(max(total, 1))))
                    Text(String(format: String(localized: "%@ of %@ used"),
                                ByteCountFormatter.string(fromByteCount: used, countStyle: .binary),
                                ByteCountFormatter.string(fromByteCount: total, countStyle: .binary)))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(info.title ?? String(localized: "Subscription")).font(.caption).foregroundColor(.secondary)
                }
                if let expire = info.expire {
                    Text(String(format: String(localized: "Expires %@"), expire.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption2).foregroundColor(info.isExpired || info.expiresSoon ? .red : .secondary)
                }
            }
            Spacer()
            if let s = info.supportURL, let url = URL(string: s) {
                Button { openURL(url) } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel(Text("Support"))
            }
            if let w = info.webPageURL, let url = URL(string: w) {
                Button { openURL(url) } label: { Image(systemName: "globe") }
                    .accessibilityLabel(Text("Website"))
            }
        }
        .padding(.horizontal, 4)
    }
}

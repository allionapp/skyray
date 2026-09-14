import SwiftUI

/// The server picker, opened from the card on Home. "Automatic" sits on top;
/// below it the servers are grouped by the link they came from, with their
/// latency. One tap chooses and closes; everything else is behind a long press.
struct ServerPickerView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var profileToDelete: ServerProfile?
    @State private var profileToEdit: ServerProfile?
    @State private var confirmDeleteUnreachable = false

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if profiles.isPinging { pingProgress }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if profiles.profiles.count > 20 { searchField }
                        if search.isEmpty {
                            automaticRow
                            Rule()
                        }
                        ForEach(filteredGroups, id: \.url) { group in
                            groupHeader(group.title, count: group.servers.count, url: group.url)
                            ForEach(group.servers) { profile in
                                row(profile)
                                Rule(strong: false)
                            }
                        }
                        Text("Long-press a server to see its details or delete it.")
                            .font(Sky.body(12.5)).foregroundColor(Sky.muted(0.5))
                            .padding(24)
                    }
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .sheet(item: $profileToEdit) { ProfileDetailView(profile: $0) }
        .alert(String(format: String(localized: "Delete \"%@\"?"), profileToDelete?.name ?? ""),
               isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } })) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let p = profileToDelete { profiles.delete(p) }
                profileToDelete = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { profileToDelete = nil }
        }
        .alert(String(localized: "Delete all servers that timed out?"), isPresented: $confirmDeleteUnreachable) {
            Button(String(localized: "Delete"), role: .destructive) { profiles.deleteUnreachable() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .onAppear {
            // Latency is what the choice is based on, so have it ready without
            // asking. While connected the test would run through the tunnel and
            // mislead, so it waits for an explicit tap then.
            if !vpn.isConnected, !profiles.latenciesAreFresh { Task { await profiles.pingAll() } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Servers").font(Sky.heading(28)).foregroundColor(Sky.ink)
            Spacer()
            Menu {
                Button { Task { await profiles.pingAll() } } label: { Label("Test again", systemImage: "bolt.horizontal") }
                    .disabled(profiles.isPinging)
                Button { Task { await profiles.updateAllSubscriptions() } } label: { Label("Update subscriptions", systemImage: "arrow.clockwise") }
                    .disabled(profiles.subscriptions.isEmpty || profiles.isImporting)
                Button(role: .destructive) { confirmDeleteUnreachable = true } label: { Label("Delete unreachable", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .heavy)).foregroundColor(Sky.ink)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel(Text("More"))
            IconButton(systemName: "xmark", accessibility: "Close") { dismiss() }
        }
        .padding(.leading, 24).padding(.trailing, 16).padding(.top, 18).padding(.bottom, 12)
        .overlay(Rule(), alignment: .bottom)
    }

    private var pingProgress: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Sky.primary)
            Text(String(format: String(localized: "Testing %d of %d…"), profiles.pingProgress.done, profiles.pingProgress.total))
                .font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .overlay(Rule(strong: false), alignment: .bottom)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Sky.muted(0.45))
            TextField("Search servers", text: $search)
                .font(Sky.body(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Sky.surface)
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var filteredGroups: [(title: String, url: String?, servers: [ServerProfile])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return profiles.groups }
        return profiles.groups.compactMap { group in
            let hits = group.servers.filter { $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q) }
            return hits.isEmpty ? nil : (group.title, group.url, hits)
        }
    }

    // MARK: Rows

    private var automaticRow: some View {
        Button {
            profiles.isAutomatic = true
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill").font(.system(size: 17, weight: .semibold)).foregroundColor(Sky.primary)
                    .frame(width: 40, height: 40).background(Sky.primary.opacity(0.14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Automatic · fastest").font(Sky.heading(16)).foregroundColor(Sky.ink)
                    Text(bestLine).font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6)).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let best = fastest { latency(best.latencyMs) }
                checkmark(profiles.isAutomatic)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(profiles.isAutomatic ? Sky.surface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fastest: ServerProfile? {
        profiles.profiles.filter { ($0.latencyMs ?? -1) > 0 }.min { $0.latencyMs! < $1.latencyMs! }
    }

    private var bestLine: String {
        if let best = fastest { // Isolated so a Latin name keeps its order inside Persian text.
            return String(format: String(localized: "Right now: %@"), "\u{2066}\(best.name)\u{2069}") }
        return String(localized: "Tests the servers and connects to the quickest")
    }

    private func groupHeader(_ title: String, count: Int, url: String?) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: title).font(Sky.semibold(11)).tracking(1.1).textCase(.uppercase)
                .foregroundColor(Sky.muted(0.55)).lineLimit(1)
            Text(verbatim: "\(count)").font(Sky.mono(11, medium: true)).foregroundColor(Sky.muted(0.4))
            Spacer()
            if let url, profiles.updatingSubscriptionURL == url {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
        .overlay(Rule(strong: false), alignment: .bottom)
    }

    private func row(_ profile: ServerProfile) -> some View {
        let selected = !profiles.isAutomatic && profile.id == profiles.selectedId
        return Button {
            profiles.choose(profile)
            if vpn.isConnected { Task { await vpn.reconnect(profile: profile) } }
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Rectangle().fill(selected ? Sky.accent : Color.clear).frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(selected ? Sky.heading(15) : Sky.semibold(15)).foregroundColor(Sky.ink).lineLimit(1)
                        // Provider names share a long prefix; the tail is what tells them apart.
                        .truncationMode(.middle)
                    Text(verbatim: profile.kindLabel).font(Sky.mono(11)).foregroundColor(Sky.muted(0.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                latency(profile.latencyMs)
                checkmark(selected)
            }
            .padding(.vertical, 13).padding(.leading, 20).padding(.trailing, 24)
            .background(selected ? Sky.surface : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            Button { profileToEdit = profile } label: { Label("Details", systemImage: "info.circle") }
            if let link = profile.shareLink {
                Button { UIPasteboard.general.string = link } label: { Label("Copy link", systemImage: "doc.on.doc") }
            }
            Button(role: .destructive) { profileToDelete = profile } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func checkmark(_ on: Bool) -> some View {
        Image(systemName: "checkmark").font(.system(size: 14, weight: .black))
            .foregroundColor(Sky.accent).opacity(on ? 1 : 0).frame(width: 18)
    }

    @ViewBuilder private func latency(_ ms: Int?) -> some View {
        if let ms {
            HStack(spacing: 5) {
                Circle().fill(latencyColor(ms)).frame(width: 7, height: 7)
                Text(verbatim: ms < 0 ? "—" : "\(ms) ms").font(Sky.mono(12, medium: true))
                    .foregroundColor(ms < 0 ? Sky.muted(0.45) : Sky.ink)
            }
        } else if profiles.isPinging {
            ProgressView().scaleEffect(0.7)
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 0 { return Sky.accentDeep }
        if ms < 700 { return Color(hex: 0x1E9E5A) }
        if ms < 1500 { return Color(hex: 0xE0A100) }
        return Sky.accent
    }
}

extension ServerProfile {
    /// "VLESS · XHTTP · TLS": what a person can tell servers apart by when
    /// their names only differ in the tail.
    var kindLabel: String {
        var parts = [protocolName.uppercased()]
        if let d = outboundJSON.data(using: .utf8), let ob = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let stream = ob["streamSettings"] as? [String: Any] {
                if let n = stream["network"] as? String { parts.append(n == "ws" ? "WebSocket" : n == "raw" || n == "tcp" ? "TCP" : n.uppercased()) }
                if let s = stream["security"] as? String, s != "none" { parts.append(s == "tls" ? "TLS" : s.capitalized) }
            } else if let tls = ob["tls"] as? [String: Any], tls["enabled"] as? Bool == true { parts.append("TLS") }
        }
        return parts.joined(separator: " · ")
    }
}

/// Kept for the detail sheet, which still shows the coloured badge.
struct LatencyBadge: View {
    let ms: Int
    var body: some View {
        Text(ms < 0 ? String(localized: "timeout") : "\(ms) ms")
            .font(Sky.mono(11, medium: true))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(ms < 0 ? Sky.accentTint : Sky.surface)
            .foregroundColor(ms < 0 ? Sky.accentTintInk : Sky.ink)
    }
}

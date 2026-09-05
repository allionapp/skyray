import SwiftUI

struct ServerListView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @State private var showAdd = false
    @State private var confirmDeleteUnreachable = false
    @State private var confirmDeleteAll = false
    @State private var profileToDelete: ServerProfile?
    @State private var profileToEdit: ServerProfile?
    @State private var search = ""

    private var filtered: [ServerProfile] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return profiles.profiles }
        return profiles.profiles.filter { $0.name.lowercased().contains(q) || $0.address.lowercased().contains(q) || $0.protocolName.lowercased().contains(q) }
    }

    var body: some View {
        List {
            if profiles.profiles.isEmpty {
                EmptyStateView(title: String(localized: "No servers yet"),
                               message: String(localized: "Paste a vmess://, vless://, trojan://, ss://, ssh:// or tuic:// link, a subscription URL, or scan a QR code."))
            }
            if profiles.isPinging {
                HStack {
                    ProgressView()
                    Text(String(format: String(localized: "Testing %d of %d…"), profiles.pingProgress.done, profiles.pingProgress.total))
                        .font(.footnote).foregroundColor(.secondary)
                    Spacer()
                    Button(String(localized: "Cancel")) { profiles.cancelPing() }.font(.footnote)
                }
            }
            ForEach(filtered) { profile in
                Button {
                    profiles.select(profile)
                    if vpn.isConnected { Task { await vpn.reconnect(profile: profile) } }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(profile.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let ms = profile.latencyMs { LatencyBadge(ms: ms) }
                        Image(systemName: profile.id == profiles.selectedId ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(profile.id == profiles.selectedId ? Color.accentColor : Color.secondary.opacity(0.4))
                        Button { profileToEdit = profile } label: {
                            Image(systemName: "info.circle").foregroundColor(.accentColor).padding(.leading, 4)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Details"))
                        Button { profileToDelete = profile } label: {
                            Image(systemName: "trash").foregroundColor(.red).padding(.leading, 4)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Delete"))
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { profiles.delete(profile) } label: { Label("Delete", systemImage: "trash") }
                    Button { profileToEdit = profile } label: { Label("Details", systemImage: "info.circle") }.tint(.blue)
                }
                .swipeActions(edge: .leading) {
                    Button { Task { await profiles.tcpPing(profile) } } label: { Label("TCP ping", systemImage: "waveform.path.ecg") }.tint(.orange)
                }
                .contextMenu {
                    Button { profileToEdit = profile } label: { Label("Details", systemImage: "info.circle") }
                    if let link = profile.shareLink {
                        Button { UIPasteboard.general.string = link } label: { Label("Copy link", systemImage: "doc.on.doc") }
                    }
                    Button { Task { await profiles.tcpPing(profile) } } label: { Label("TCP ping", systemImage: "waveform.path.ecg") }
                    Button(role: .destructive) { profiles.delete(profile) } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .onMove { from, to in if search.isEmpty { profiles.move(from: from, to: to) } }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .searchable(text: $search, prompt: Text("Search servers"))
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Button { Task { await profiles.pingAll() } } label: { Label("Test all latencies", systemImage: "bolt.horizontal") }
                            .disabled(profiles.isPinging || profiles.profiles.isEmpty)
                        Button { profiles.sortByLatency() } label: { Label("Sort by latency", systemImage: "arrow.up.arrow.down") }
                        Button { profiles.selectFastest() } label: { Label("Select fastest", systemImage: "hare") }
                        Button { Task { await profiles.updateAllSubscriptions() } } label: { Label("Update subscriptions", systemImage: "arrow.clockwise") }
                            .disabled(profiles.subscriptions.isEmpty)
                        EditButton()
                        Button(role: .destructive) { confirmDeleteUnreachable = true } label: { Label("Delete unreachable", systemImage: "trash") }
                        Button(role: .destructive) { confirmDeleteAll = true } label: { Label("Delete all servers", systemImage: "trash.fill") }
                            .disabled(profiles.profiles.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddServerView() }
        .sheet(item: $profileToEdit) { ProfileDetailView(profile: $0) }
        .alert(String(localized: "Delete all servers that timed out?"), isPresented: $confirmDeleteUnreachable) {
            Button(String(localized: "Delete"), role: .destructive) { profiles.deleteUnreachable() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(String(localized: "Delete all servers and subscriptions?"), isPresented: $confirmDeleteAll) {
            Button(String(localized: "Delete all"), role: .destructive) { profiles.deleteAll() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(String(format: String(localized: "Delete \"%@\"?"), profileToDelete?.name ?? ""),
               isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } })) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let p = profileToDelete { profiles.delete(p) }
                profileToDelete = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { profileToDelete = nil }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "network").font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }
}

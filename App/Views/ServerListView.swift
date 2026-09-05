import SwiftUI

/// Servers: a flat list with a 4px state bar, mono host lines and latency on the right.
struct ServerListView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.presentationMode) private var presentation
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
        ZStack {
            Sky.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if profiles.isPinging { pingProgress }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if profiles.profiles.isEmpty { emptyHint }
                        ForEach(filtered) { profile in
                            row(profile)
                            Rule(strong: false)
                        }
                    }
                }
                Rule()
                Button { showAdd = true } label: { Label("Add a config", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(24)
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showAdd) { AddConfigFlow() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BackButton(title: "Home") { presentation.wrappedValue.dismiss() }
                Spacer()
                HStack(spacing: 8) {
                    Rectangle().fill(vpn.isConnected ? Sky.accent : Color(hex: 0x9B9797)).frame(width: 8, height: 8)
                    Text(vpn.isConnected ? "ON" : "OFF").font(Sky.mono(11, medium: true)).foregroundColor(Sky.muted(0.6))
                }
                menu.padding(.leading, 12)
            }
            .padding(.bottom, 14)
            Text("Servers").font(Sky.heading(34)).foregroundColor(Sky.ink)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Sky.muted(0.45))
                TextField("Search servers", text: $search)
                    .font(Sky.body(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Sky.surface)
            .padding(.top, 14)
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
        .overlay(Rule(), alignment: .bottom)
    }

    private var menu: some View {
        Menu {
            Button { Task { await profiles.pingAll() } } label: { Label("Test all latencies", systemImage: "bolt.horizontal") }
                .disabled(profiles.isPinging || profiles.profiles.isEmpty)
            Button { profiles.sortByLatency() } label: { Label("Sort by latency", systemImage: "arrow.up.arrow.down") }
            Button { profiles.selectFastest() } label: { Label("Select fastest", systemImage: "hare") }
            Button { Task { await profiles.updateAllSubscriptions() } } label: { Label("Update subscriptions", systemImage: "arrow.clockwise") }
                .disabled(profiles.subscriptions.isEmpty)
            Button(role: .destructive) { confirmDeleteUnreachable = true } label: { Label("Delete unreachable", systemImage: "trash") }
            Button(role: .destructive) { confirmDeleteAll = true } label: { Label("Delete all servers", systemImage: "trash.fill") }
                .disabled(profiles.profiles.isEmpty)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .heavy)).foregroundColor(Sky.ink)
                .frame(width: 36, height: 36).overlay(Rectangle().stroke(Sky.divider(), lineWidth: 1))
        }
    }

    private var pingProgress: some View {
        HStack {
            ProgressView().tint(Sky.accent)
            Text(String(format: String(localized: "Testing %d of %d…"), profiles.pingProgress.done, profiles.pingProgress.total))
                .font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
            Spacer()
            Button(String(localized: "Cancel")) { profiles.cancelPing() }.buttonStyle(ChipButtonStyle())
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .overlay(Rule(strong: false), alignment: .bottom)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: "Add another")
            Text("Your provider gives you a link or a QR code. Paste it here and the app fills in the rest.")
                .font(Sky.body(14)).foregroundColor(Sky.muted(0.7)).frame(maxWidth: 300, alignment: .leading)
        }
        .padding(.horizontal, 24).padding(.vertical, 26).leading()
    }

    private func row(_ profile: ServerProfile) -> some View {
        let selected = profile.id == profiles.selectedId
        return Button {
            profiles.select(profile)
            if vpn.isConnected { Task { await vpn.reconnect(profile: profile) } }
        } label: {
            HStack(spacing: 14) {
                Rectangle().fill(selected ? Sky.accent : Sky.ink.opacity(0.18)).frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(selected ? Sky.heading(16) : Sky.semibold(16)).foregroundColor(Sky.ink).lineLimit(1)
                    Text(verbatim: "\(profile.address):\(profile.port)" + (profile.core == .singbox ? " · sing-box" : ""))
                        .font(Sky.mono(11.5)).foregroundColor(Sky.muted(0.55)).lineLimit(1)
                }
                Spacer(minLength: 8)
                latency(profile.latencyMs)
                Button { profileToEdit = profile } label: {
                    Image(systemName: "info.circle").font(.system(size: 16)).foregroundColor(Sky.muted(0.45)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Details"))
            }
            .padding(.vertical, 16).padding(.leading, 24).padding(.trailing, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { profiles.delete(profile) } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { profileToEdit = profile } label: { Label("Details", systemImage: "info.circle") }
            if let link = profile.shareLink {
                Button { UIPasteboard.general.string = link } label: { Label("Copy link", systemImage: "doc.on.doc") }
            }
            Button { Task { await profiles.tcpPing(profile) } } label: { Label("TCP ping", systemImage: "waveform.path.ecg") }
            Button(role: .destructive) { profileToDelete = profile } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func latency(_ ms: Int?) -> some View {
        Group {
            if let ms {
                Text(ms < 0 ? "—" : "\(ms) ms").font(Sky.mono(12, medium: true))
                    .foregroundColor(ms < 0 ? Sky.accentDeep : (ms < 300 ? Sky.ink : Sky.muted(0.55)))
            } else {
                Text("").font(Sky.mono(12))
            }
        }
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

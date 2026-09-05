import SwiftUI

struct AddServerView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Int, CaseIterable, Identifiable {
        case link, subscription, qr
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .link: return "Link / JSON"
            case .subscription: return "Subscription"
            case .qr: return "QR Code"
            }
        }
    }

    @State private var mode: Mode = .link
    @State private var text = ""
    @State private var subscriptionURL = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .link: linkEditor
                case .subscription: subscriptionEditor
                case .qr: QRScannerView { code in
                        text = code
                        mode = .link
                        Task { await importText() }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if profiles.isImporting {
                    HStack { ProgressView(); Text("Importing…").font(.footnote).foregroundColor(.secondary) }
                } else if let message = profiles.message {
                    Text(message).font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Add server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { profiles.message = nil }
        }
        .navigationViewStyle(.stack)
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste one link per line, a full Xray JSON config, or Clash YAML.")
                .font(.footnote).foregroundColor(.secondary)
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 160)
                .padding(6)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button { if let s = UIPasteboard.general.string { text = s } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button { Task { await importText() } } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profiles.isImporting)
            }
        }
    }

    private var subscriptionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A subscription URL returns a list of servers (plain, base64 or Clash YAML).")
                .font(.footnote).foregroundColor(.secondary)
            TextField("https://… or hiddify://import/…", text: $subscriptionURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button { if let s = UIPasteboard.general.string { subscriptionURL = s } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    Task { await profiles.importSubscription(subscriptionURL) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(profiles.isImporting || subscriptionURL.isEmpty)
            }
            if !profiles.subscriptions.isEmpty {
                Divider()
                Text("Saved subscriptions").font(.subheadline.weight(.semibold))
                ForEach(profiles.subscriptions) { sub in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.title ?? sub.url).font(.caption).lineLimit(1)
                            if let remaining = sub.remaining {
                                Text(String(format: String(localized: "%@ left"), ByteCountFormatter.string(fromByteCount: remaining, countStyle: .binary)))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button { Task { await profiles.importSubscription(sub.url) } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) { profiles.removeSubscription(sub.url) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func importText() async {
        // A pasted launcher link (hiddify://import/…, v2box://…) is a subscription, not a server.
        if !ShareLinkParser.containsShareLink(text), SubscriptionLinkResolver.resolve(text) != nil {
            subscriptionURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
            mode = .subscription
            await profiles.importSubscription(subscriptionURL)
            return
        }
        let added = await profiles.importText(text)
        if added > 0 { text = "" }
    }
}

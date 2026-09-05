import SwiftUI
import CoreImage.CIFilterBuiltins

/// Edit a server's name / raw outbound JSON and share it as a link or QR code.
struct ProfileDetailView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss
    @State var profile: ServerProfile
    @State private var json: String = ""
    @State private var error: String?
    @State private var showShare = false
    @State private var confirmDelete = false
    @State private var copied = false

    init(profile: ServerProfile) {
        _profile = State(initialValue: profile)
        UITextView.appearance().backgroundColor = .clear
    }

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        title
                        facts
                        if let link = shareLink { share(link) }
                        advanced
                        actions
                    }
                    .padding(.bottom, 40)
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .onAppear { json = prettyJSON(profile.outboundJSON) }
        .sheet(isPresented: $showShare) { if let link = shareLink { ShareSheet(items: [link]) } }
        .alert(String(format: String(localized: "Delete \"%@\"?"), profile.name), isPresented: $confirmDelete) {
            Button(String(localized: "Delete"), role: .destructive) { profiles.delete(profile); dismiss() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
    }

    // MARK: Header / title

    private var header: some View {
        HStack {
            BackButton(title: "Close") { dismiss() }
            Spacer()
            Button("Save") { save() }.buttonStyle(PrimaryButtonStyle(height: 36, fullWidth: false))
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
        .overlay(Rule(), alignment: .bottom)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(vpn.isConnected && profiles.selectedProfile?.id == profile.id ? Sky.accent : Sky.ink).frame(width: 8, height: 8)
                Kicker(text: LocalizedStringKey(profile.protocolName.uppercased() + (profile.core == .singbox ? " · SING-BOX" : "")))
            }
            .padding(.bottom, 14)
            BoxedField(label: "Name") {
                TextField("Name", text: $profile.name).font(Sky.heading(20)).foregroundColor(Sky.ink)
            }
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20).leading()
        .overlay(Rule(), alignment: .bottom)
    }

    // MARK: Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 0) {
            ValueRow(title: "Address", value: "\(profile.address):\(profile.port)")
            Rule(strong: false)
            HStack {
                Text("Latency").font(Sky.body(15)).foregroundColor(Sky.ink)
                Spacer()
                if profiles.isPinging {
                    ProgressView().tint(Sky.accent)
                } else if let ms = profile.latencyMs {
                    LatencyBadge(ms: ms)
                } else {
                    Text("—").font(Sky.mono(13)).foregroundColor(Sky.muted(0.5))
                }
                Button("TCP ping") {
                    Task {
                        await profiles.tcpPing(profile)
                        if let p = profiles.profiles.first(where: { $0.id == profile.id }) { profile.latencyMs = p.latencyMs }
                    }
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(profiles.isPinging)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            Rule()
        }
    }

    // MARK: Share

    private func share(_ link: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Share")
            VStack(alignment: .leading, spacing: 16) {
                QRCodeView(text: link)
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Sky.divider(), lineWidth: 2))
                Text(verbatim: link).font(Sky.mono(11)).foregroundColor(Sky.muted(0.55)).lineLimit(2).truncationMode(.middle)
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = link
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: { Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(SecondaryButtonStyle(height: 40, fullWidth: false))
                    Button { showShare = true } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle(height: 40, fullWidth: false))
                }
            }
            .padding(24)
            Rule()
        }
    }

    // MARK: Advanced JSON

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Outbound JSON (advanced)")
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $json)
                    .font(Sky.mono(11.5)).foregroundColor(Sky.ink)
                    .frame(minHeight: 220)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(8)
                    .background(Sky.paper)
                    .overlay(Rectangle().stroke(error == nil ? Sky.divider() : Sky.accent, lineWidth: 2))
                if let error {
                    Text(verbatim: error).font(Sky.body(12.5)).foregroundColor(Sky.accentDeep)
                } else {
                    Text("Edit carefully: this is the Xray outbound used inside the tunnel.").font(Sky.body(12.5)).foregroundColor(Sky.muted(0.6))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            Rule()
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { Task { await vpn.reconnect(profile: profile, force: true); dismiss() } } label: {
                HStack { Text("Connect to this server"); Spacer(); Image(systemName: "power").font(.system(size: 16, weight: .bold)) }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54))
            Button { confirmDelete = true } label: {
                HStack { Text("Remove this server"); Spacer(); Image(systemName: "trash").font(.system(size: 15, weight: .bold)) }
            }
            .buttonStyle(SecondaryButtonStyle(height: 50, tint: Sky.accentDeep))
        }
        .padding(24)
    }

    // MARK: Logic

    private var shareLink: String? {
        if let link = profile.shareLink { return link }
        if profile.core == .singbox { return nil }
        let wrapped = "{\"outbounds\":[\(profile.outboundJSON)]}"
        if let data = try? XrayCore.invoke("convertXrayJsonToShareLinks", payload: ["xrayJson": wrapped]) as? [String: Any],
           let links = data["links"] as? String, !links.isEmpty {
            return links.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func save() {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = String(localized: "Invalid JSON.")
            return
        }
        do {
            var updated: ServerProfile
            if profile.core == .singbox {
                updated = profile
                let compact = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                updated.outboundJSON = String(decoding: compact, as: UTF8.self)
                updated.address = (object["server"] as? String) ?? profile.address
                updated.port = (object["server_port"] as? Int) ?? profile.port
                try SingboxCore.testConfig(try SingboxConfigBuilder.runtimeConfig(outboundJSON: updated.outboundJSON))
            } else {
                updated = try ShareLinkParser.makeProfile(from: object, fallbackName: profile.name)
                updated.id = profile.id
                updated.name = profile.name
                updated.subscriptionURL = profile.subscriptionURL
                updated.latencyMs = profile.latencyMs
                try XrayCore.testConfig(try XrayConfigBuilder.runtimeConfig(outboundJSON: updated.outboundJSON, hasGeoData: false))
            }
            updated.shareLink = updated.outboundJSON == profile.outboundJSON ? profile.shareLink : nil
            profiles.update(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func prettyJSON(_ s: String) -> String {
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d),
              let p = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) else { return s }
        return String(decoding: p, as: UTF8.self)
    }
}

struct QRCodeView: View {
    let text: String
    var body: some View {
        if let image = Self.image(for: text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Text("QR code too large").foregroundColor(.secondary)
        }
    }
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name")) {
                    TextField("Name", text: $profile.name)
                }
                Section(header: Text("Server")) {
                    HStack { Text("Protocol"); Spacer(); Text(profile.protocolName.uppercased()).foregroundColor(.secondary) }
                    HStack { Text("Address"); Spacer(); Text(verbatim: "\(profile.address):\(profile.port)").foregroundColor(.secondary) }
                    if let ms = profile.latencyMs { HStack { Text("Latency"); Spacer(); LatencyBadge(ms: ms) } }
                    Button { Task { await profiles.tcpPing(profile); if let p = profiles.profiles.first(where: { $0.id == profile.id }) { profile = p } } } label: {
                        Label("TCP ping", systemImage: "waveform.path.ecg")
                    }
                }
                if let link = shareLink {
                    Section(header: Text("Share")) {
                        QRCodeView(text: link).frame(maxWidth: .infinity).frame(height: 220)
                        Button { UIPasteboard.general.string = link } label: { Label("Copy link", systemImage: "doc.on.doc") }
                        Button { showShare = true } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                    }
                }
                Section(header: Text("Outbound JSON (advanced)"), footer: Text(error ?? String(localized: "Edit carefully: this is the Xray outbound used inside the tunnel."))) {
                    TextEditor(text: $json)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button { Task { await vpn.reconnect(profile: profile); dismiss() } } label: { Label("Connect to this server", systemImage: "power") }
                    Button(role: .destructive) { profiles.delete(profile); dismiss() } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { json = prettyJSON(profile.outboundJSON) }
            .sheet(isPresented: $showShare) { if let link = shareLink { ShareSheet(items: [link]) } }
        }
        .navigationViewStyle(.stack)
    }

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

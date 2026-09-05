import SwiftUI
import UniformTypeIdentifiers

/// Export / import all servers, subscriptions and settings as a JSON file,
/// or copy every server as share links.
struct BackupView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @State private var exportDocument: BackupDocument?
    @State private var showImporter = false
    @State private var showLinksShare = false

    var body: some View {
        List {
            Section(header: Text("Backup"), footer: Text("The backup file contains your server credentials. Keep it private.")) {
                Button {
                    if let data = profiles.exportBackup(settings: vpn.settings) { exportDocument = BackupDocument(data: data) }
                } label: { Label("Export backup file", systemImage: "square.and.arrow.up") }
                Button { showImporter = true } label: { Label("Restore from backup file", systemImage: "square.and.arrow.down") }
            }
            Section(header: Text("Share links")) {
                Button { UIPasteboard.general.string = profiles.exportLinks() } label: { Label("Copy all servers as links", systemImage: "doc.on.doc") }
                Button { showLinksShare = true } label: { Label("Share all links…", systemImage: "square.and.arrow.up") }
            }
            if let message = profiles.message {
                Section { Text(message).font(.footnote).foregroundColor(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup & share")
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .json, defaultFilename: "SkyRay-backup") { _ in exportDocument = nil }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            if let restored = profiles.importBackup(data) { vpn.settings = restored }
            else { Task { await profiles.importText(String(decoding: data, as: UTF8.self)) } }
        }
        .sheet(isPresented: $showLinksShare) { ShareSheet(items: [profiles.exportLinks()]) }
        .onAppear { profiles.message = nil }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

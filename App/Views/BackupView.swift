import SwiftUI
import UniformTypeIdentifiers

/// Export / import all servers, subscriptions and settings as a JSON file,
/// or copy every server as share links.
struct BackupView: View {
    @EnvironmentObject private var profiles: ProfilesViewModel
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.presentationMode) private var presentation
    @State private var exportDocument: BackupDocument?
    @State private var showImporter = false
    @State private var showLinksShare = false

    var body: some View {
        ZStack {
            Sky.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(back: "Settings", title: "Backup & share",
                                 subtitle: "Everything you've set up — servers, subscriptions and settings — in one file you keep.") {
                        presentation.wrappedValue.dismiss()
                    }
                    SectionHeader(title: "Backup file")
                    VStack(spacing: 10) {
                        Button {
                            if let data = profiles.exportBackup(settings: vpn.settings) { exportDocument = BackupDocument(data: data) }
                        } label: { HStack { Text("Export backup file"); Spacer(); Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)) } }
                            .buttonStyle(PrimaryButtonStyle(height: 50))
                            .disabled(profiles.profiles.isEmpty && profiles.subscriptions.isEmpty)
                        Button { showImporter = true } label: { HStack { Text("Restore from backup file"); Spacer(); Image(systemName: "square.and.arrow.down").font(.system(size: 15, weight: .bold)) } }
                            .buttonStyle(SecondaryButtonStyle(height: 50))
                    }
                    .padding(24)
                    Rule()
                    Footnote("The backup file contains your server credentials. Keep it private.")

                    SectionHeader(title: "Share links", trailing: profiles.profiles.isEmpty ? nil : "\(profiles.profiles.count)")
                    VStack(spacing: 10) {
                        Button { UIPasteboard.general.string = profiles.exportLinks() } label: { HStack { Text("Copy all servers as links"); Spacer(); Image(systemName: "doc.on.doc").font(.system(size: 15, weight: .bold)) } }
                            .buttonStyle(SecondaryButtonStyle(height: 50))
                        Button { showLinksShare = true } label: { HStack { Text("Share all links…"); Spacer(); Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)) } }
                            .buttonStyle(SecondaryButtonStyle(height: 50))
                    }
                    .padding(24)
                    .disabled(profiles.profiles.isEmpty)
                    Rule()
                    if let message = profiles.message {
                        Footnote(verbatim: message)
                    }
                }
                .padding(.bottom, 40)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
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

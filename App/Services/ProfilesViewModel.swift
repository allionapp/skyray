import Foundation
import Combine

@MainActor
final class ProfilesViewModel: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published var selectedId: UUID? {
        didSet {
            store.selectedProfileId = selectedId
            if let p = selectedProfile { store.writeActiveProfile(p) }
        }
    }
    @Published private(set) var isPinging = false
    @Published private(set) var pingProgress: (done: Int, total: Int) = (0, 0)
    @Published private(set) var isImporting = false
    @Published var message: String?
    @Published private(set) var subscriptions: [SubscriptionInfo] = []

    private let store = ProfileStore.shared
    private var pingTask: Task<Void, Never>?

    init() {
        profiles = store.loadProfiles()
        subscriptions = store.loadSubscriptions()
        selectedId = store.selectedProfileId ?? profiles.first?.id
        if let p = selectedProfile { store.writeActiveProfile(p) }
    }

    var selectedProfile: ServerProfile? {
        profiles.first { $0.id == selectedId } ?? profiles.first
    }

    func select(_ profile: ServerProfile) { selectedId = profile.id }

    func update(_ profile: ServerProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[i] = profile
        if profile.id == selectedId { store.writeActiveProfile(profile) }
        persist()
    }

    func delete(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        fixSelectionAndPersist()
    }

    func delete(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        fixSelectionAndPersist()
    }

    func deleteAll() {
        profiles.removeAll()
        subscriptions.removeAll()
        store.saveSubscriptions(subscriptions)
        fixSelectionAndPersist()
    }

    func deleteUnreachable() {
        profiles.removeAll { $0.latencyMs == -1 }
        fixSelectionAndPersist()
    }

    func move(from: IndexSet, to: Int) {
        profiles.move(fromOffsets: from, toOffset: to)
        persist()
    }

    private func fixSelectionAndPersist() {
        if let id = selectedId, !profiles.contains(where: { $0.id == id }) { selectedId = profiles.first?.id }
        if profiles.isEmpty { selectedId = nil }
        persist()
    }

    // MARK: - Import

    /// Imports share links / JSON / Clash YAML. Parsing runs off the main thread
    /// so a subscription with thousands of servers cannot freeze the UI.
    @discardableResult
    func importText(_ text: String, subscriptionURL: String? = nil) async -> Int {
        isImporting = true
        defer { isImporting = false }
        let outcome = await Task.detached(priority: .userInitiated) {
            ShareLinkParser.parse(text, subscriptionURL: subscriptionURL)
        }.value
        let existing = Set(profiles.map { $0.outboundJSON })
        let fresh = outcome.profiles.filter { !existing.contains($0.outboundJSON) }
        let duplicates = outcome.profiles.count - fresh.count
        profiles.append(contentsOf: fresh)
        if selectedId == nil { selectedId = profiles.first?.id }
        persist()

        if outcome.profiles.isEmpty {
            if let first = outcome.failures.first {
                message = String(format: String(localized: "Could not parse the link: %@"), first.reason)
            } else {
                message = String(localized: "No server links found.")
            }
        } else {
            var parts = [String(format: String(localized: "Imported %d server(s)."), fresh.count)]
            if duplicates > 0 { parts.append(String(format: String(localized: "%d duplicate(s) skipped."), duplicates)) }
            if !outcome.failures.isEmpty { parts.append(String(format: String(localized: "%d invalid skipped."), outcome.failures.count)) }
            message = parts.joined(separator: " ")
        }
        return fresh.count
    }

    /// Downloads a subscription. Accepts plain http(s) URLs and the launcher deep
    /// links panels give out for other apps (hiddify://import/…, v2box://…, clash://…).
    /// Servers answering with a redirect to such a deep link are unwrapped too.
    func importSubscription(_ urlString: String) async {
        guard let resolved = SubscriptionLinkResolver.resolve(urlString) else {
            message = String(localized: "Enter a valid http(s) subscription URL.")
            writeImportLog("invalid subscription input: \(urlString.prefix(60))")
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let (data, http, finalURL) = try await SubscriptionFetcher.fetch(resolved.url)
            guard (200..<300).contains(http.statusCode) else {
                message = String(format: String(localized: "Subscription server returned HTTP %d."), http.statusCode)
                writeImportLog("subscription HTTP \(http.statusCode) for \(finalURL)")
                return
            }
            let key = resolved.url
            let body = String(decoding: data, as: UTF8.self)
            let old = profiles.filter { $0.subscriptionURL == key }
            let oldLatency = Dictionary(old.map { ($0.outboundJSON, $0.latencyMs) }, uniquingKeysWith: { a, _ in a })
            let previousSelection = selectedProfile
            profiles.removeAll { $0.subscriptionURL == key }
            let added = await importText(body, subscriptionURL: key)
            if added == 0 && !old.isEmpty {
                // Keep the previous servers rather than leaving the user with nothing.
                profiles.append(contentsOf: old)
                persist()
            } else {
                // Carry over latencies and keep the same server selected after a refresh.
                for i in profiles.indices where profiles[i].subscriptionURL == key {
                    if let ms = oldLatency[profiles[i].outboundJSON] { profiles[i].latencyMs = ms }
                }
                if let prev = previousSelection, prev.subscriptionURL == key,
                   let same = profiles.first(where: { $0.outboundJSON == prev.outboundJSON }) {
                    selectedId = same.id
                }
                persist()
            }
            updateSubscriptionInfo(url: key, headers: http.allHeaderFields, fallbackTitle: resolved.title)
            writeImportLog("subscription ok: added=\(added) total=\(profiles.count) final=\(finalURL)")
        } catch {
            message = String(format: String(localized: "Download failed: %@"), error.localizedDescription)
            writeImportLog("subscription failed: \(error.localizedDescription)")
        }
    }

    /// Debug aid: readable from the Mac with devicectl (Documents/import.log).
    private func writeImportLog(_ line: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("import.log")
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd(); handle.write(Data(entry.utf8)); try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }

    private func updateSubscriptionInfo(url: String, headers: [AnyHashable: Any], fallbackTitle: String? = nil) {
        var info = subscriptions.first { $0.url == url } ?? SubscriptionInfo(url: url, lastUpdated: Date())
        info.lastUpdated = Date()
        if info.title == nil { info.title = fallbackTitle }
        let lower = Dictionary(headers.compactMap { key, value -> (String, String)? in
            guard let k = key as? String, let v = value as? String else { return nil }
            return (k.lowercased(), v)
        }, uniquingKeysWith: { a, _ in a })
        if let userinfo = lower["subscription-userinfo"] {
            var values: [String: Int64] = [:]
            for part in userinfo.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2, let n = Int64(kv[1]) { values[kv[0].lowercased()] = n }
            }
            info.upload = values["upload"]
            info.download = values["download"]
            info.total = values["total"]
            info.expire = values["expire"].map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
        if let title = lower["profile-title"] { info.title = decodeHeader(title) }
        if let interval = lower["profile-update-interval"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
            info.updateIntervalHours = interval
        }
        info.webPageURL = lower["profile-web-page-url"].map { $0.trimmingCharacters(in: .whitespaces) }
        info.supportURL = lower["support-url"].map { $0.trimmingCharacters(in: .whitespaces) }
        info.announce = lower["announce"].map { decodeHeader($0) }
        subscriptions.removeAll { $0.url == url }
        subscriptions.append(info)
        store.saveSubscriptions(subscriptions)
    }

    private func decodeHeader(_ value: String) -> String {
        if value.hasPrefix("base64:"), let decoded = ShareLinkParser.decodeBase64(String(value.dropFirst(7))) { return decoded }
        return value
    }

    func updateAllSubscriptions() async {
        for sub in subscriptions { await importSubscription(sub.url) }
    }

    /// Refreshes subscriptions whose own interval (or the app-wide interval) has elapsed.
    func updateStaleSubscriptions(defaultHours: Int) async {
        for sub in subscriptions {
            let hours = sub.updateIntervalHours ?? defaultHours
            guard hours > 0 else { continue }
            if Date().timeIntervalSince(sub.lastUpdated) > Double(hours) * 3600 {
                await importSubscription(sub.url)
            }
        }
    }

    func removeSubscription(_ url: String) {
        subscriptions.removeAll { $0.url == url }
        store.saveSubscriptions(subscriptions)
        profiles.removeAll { $0.subscriptionURL == url }
        fixSelectionAndPersist()
    }

    // MARK: - Latency

    /// Pings in batches of five with limited concurrency so hundreds of servers
    /// finish in reasonable time without spawning hundreds of Xray instances.
    func pingAll() async {
        guard !isPinging, !profiles.isEmpty else { return }
        isPinging = true
        pingProgress = (0, profiles.count)
        let snapshot = profiles
        // sing-box profiles are pinged one at a time (each is its own tiny instance);
        // Xray profiles go through libXray's batch API, five per call.
        let xrayProfiles = snapshot.filter { $0.core == .xray }
        var chunks = stride(from: 0, to: xrayProfiles.count, by: AppConstants.pingBatchSize).map {
            Array(xrayProfiles[$0..<min($0 + AppConstants.pingBatchSize, xrayProfiles.count)])
        }
        chunks += snapshot.filter { $0.core == .singbox }.map { [$0] }
        pingTask = Task { [weak self] in
            await withTaskGroup(of: [(UUID, Int)].self) { group in
                var next = 0
                func enqueue() {
                    guard next < chunks.count, !Task.isCancelled else { return }
                    let chunk = chunks[next]; next += 1
                    group.addTask(priority: .userInitiated) {
                        if chunk.count == 1, chunk[0].core == .singbox {
                            let r = SingboxCore.ping(outboundJSON: chunk[0].outboundJSON)
                            return [(chunk[0].id, r.success ? r.delayMs : -1)]
                        }
                        let outbounds = chunk.compactMap { p -> [String: Any]? in
                            guard let d = p.outboundJSON.data(using: .utf8) else { return nil }
                            return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                        }
                        let results = (try? XrayCore.ping(outbounds: outbounds)) ?? []
                        return chunk.enumerated().map { i, p in
                            let r = i < results.count ? results[i] : nil
                            return (p.id, (r?.success ?? false) ? (r?.delayMs ?? -1) : -1)
                        }
                    }
                }
                for _ in 0..<AppConstants.pingConcurrentBatches { enqueue() }
                for await batch in group {
                    await MainActor.run {
                        guard let self else { return }
                        for (id, ms) in batch {
                            if let i = self.profiles.firstIndex(where: { $0.id == id }) { self.profiles[i].latencyMs = ms }
                        }
                        self.pingProgress = (self.pingProgress.done + batch.count, self.pingProgress.total)
                    }
                    enqueue()
                }
            }
        }
        await pingTask?.value
        pingTask = nil
        isPinging = false
        persist()
    }

    /// Plain TCP connect time to the server, usable while the VPN is off or on.
    func tcpPing(_ profile: ServerProfile) async {
        let ms = await TCPPing.measure(host: profile.address, port: profile.port)
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i].latencyMs = ms
            persist()
        }
    }

    func cancelPing() {
        pingTask?.cancel()
    }

    func sortByLatency() {
        profiles.sort { a, b in
            let x = a.latencyMs.map { $0 < 0 ? Int.max - 1 : $0 } ?? Int.max
            let y = b.latencyMs.map { $0 < 0 ? Int.max - 1 : $0 } ?? Int.max
            return x < y
        }
        persist()
    }

    @discardableResult
    func selectFastest() -> ServerProfile? {
        if let best = profiles.filter({ ($0.latencyMs ?? -1) > 0 }).min(by: { $0.latencyMs! < $1.latencyMs! }) {
            select(best)
            return best
        }
        return nil
    }

    // MARK: - Export / backup

    /// All servers as share links (one per line) for sharing or backup.
    func exportLinks() -> String {
        profiles.compactMap { profile in
            if let link = profile.shareLink { return link }
            if profile.core == .singbox { return nil }
            let json = "{\"outbounds\":[\(profile.outboundJSON)]}"
            if let data = try? XrayCore.invoke("convertXrayJsonToShareLinks", payload: ["xrayJson": json]) as? [String: Any],
               let links = data["links"] as? String, !links.isEmpty {
                return links.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }.joined(separator: "\n")
    }

    struct Backup: Codable {
        var version = 1
        var profiles: [ServerProfile]
        var subscriptions: [SubscriptionInfo]
        var settings: AppSettings
        var selectedId: UUID?
    }

    func exportBackup(settings: AppSettings) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Backup(profiles: profiles, subscriptions: subscriptions, settings: settings, selectedId: selectedId))
    }

    func importBackup(_ data: Data) -> AppSettings? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(Backup.self, from: data) else {
            message = String(localized: "This file is not a SkyRay backup.")
            return nil
        }
        let existing = Set(profiles.map { $0.outboundJSON })
        profiles.append(contentsOf: backup.profiles.filter { !existing.contains($0.outboundJSON) })
        for sub in backup.subscriptions where !subscriptions.contains(where: { $0.url == sub.url }) { subscriptions.append(sub) }
        store.saveSubscriptions(subscriptions)
        if let id = backup.selectedId, profiles.contains(where: { $0.id == id }) { selectedId = id } else if selectedId == nil { selectedId = profiles.first?.id }
        persist()
        message = String(format: String(localized: "Restored %d server(s)."), backup.profiles.count)
        return backup.settings
    }

    private var demo = false
    func persist() { if !demo { store.saveProfiles(profiles) } }

    /// Demo data for marketing screenshots: realistic names, never written to disk.
    func loadDemoData() {
        demo = true
        func make(_ name: String, _ proto: String, _ host: String, _ port: Int, _ ms: Int, core: CoreKind = .xray) -> ServerProfile {
            var p = ServerProfile(name: name, protocolName: proto, address: host, port: port, outboundJSON: "{}", core: core)
            p.latencyMs = ms
            p.shareLink = "\(proto == "shadowsocks" ? "ss" : proto)://demo-user@\(host):\(port)?security=reality&sni=\(host)&fp=chrome#\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
            p.subscriptionURL = "https://demo.skyray.app/sub"
            return p
        }
        profiles = [
            make("Frankfurt · Reality", "vless", "de1.skyray.app", 443, 84),
            make("Amsterdam · XHTTP", "vless", "nl1.skyray.app", 8443, 96),
            make("Helsinki · WebSocket", "vmess", "fi1.skyray.app", 443, 121),
            make("London · Trojan", "trojan", "uk1.skyray.app", 443, 133),
            make("Paris · Hysteria2", "hysteria2", "fr1.skyray.app", 443, 148),
            make("Warsaw · Shadowsocks", "shadowsocks", "pl1.skyray.app", 8388, 162),
            make("Zurich · TUIC", "tuic", "ch1.skyray.app", 443, 171, core: .singbox),
            make("Stockholm · SSH", "ssh", "se1.skyray.app", 22, 204, core: .singbox),
            make("New York · Reality", "vless", "us1.skyray.app", 443, 236),
            make("Tokyo · WebSocket", "vless", "jp1.skyray.app", 443, 318),
        ]
        selectedId = profiles.first?.id
        subscriptions = [SubscriptionInfo(url: "https://demo.skyray.app/sub", title: "SkyRay Premium",
                                          upload: 6_400_000_000, download: 58_900_000_000, total: 200_000_000_000,
                                          expire: Date().addingTimeInterval(23 * 24 * 3600), lastUpdated: Date(),
                                          updateIntervalHours: 12, webPageURL: "https://skyray.app", supportURL: "https://t.me/skyray")]
    }
}

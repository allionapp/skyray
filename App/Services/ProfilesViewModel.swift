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
    /// The subscription being downloaded right now, so only its row says so.
    @Published private(set) var updatingSubscriptionURL: String?
    /// Connect to whichever server tests fastest instead of a fixed choice.
    @Published var isAutomatic: Bool {
        didSet { store.automaticSelection = isAutomatic }
    }
    /// The link Home works with, when there are several (as on Android): its servers are the
    /// ones listed, tested and picked from. nil = the first subscription.
    @Published private(set) var activeLinkURL: String? {
        didSet { UserDefaults.standard.set(activeLinkURL, forKey: Self.activeLinkKey) }
    }
    private static let activeLinkKey = "SkyRayActiveLink"
    /// A link opened from outside (the bot's install link), for Home to add exactly as if it
    /// had been pasted: it becomes the link in use and connects, as on Android.
    @Published var pendingLink: String?
    private var lastPingAll: Date?

    private let store = ProfileStore.shared
    private var pingTask: Task<Void, Never>?

    init() {
        isAutomatic = ProfileStore.shared.automaticSelection
        activeLinkURL = UserDefaults.standard.string(forKey: Self.activeLinkKey)
        profiles = store.loadProfiles()
        subscriptions = store.loadSubscriptions()
        selectedId = store.selectedProfileId ?? profiles.first?.id
        if let p = selectedProfile { store.writeActiveProfile(p) }
    }

    var selectedProfile: ServerProfile? {
        profiles.first { $0.id == selectedId } ?? profiles.first
    }

    func select(_ profile: ServerProfile) { selectedId = profile.id }

    /// The free Cloudflare WARP entry, added once and kept like any other server.
    @discardableResult
    func addWarp(name: String) -> ServerProfile {
        if let existing = profiles.first(where: { $0.core == .warp }) { return existing }
        let profile = ServerProfile(name: name, protocolName: "warp", address: "cloudflare",
                                    port: 443, outboundJSON: "{}", core: .warp)
        profiles.append(profile)
        persist()
        return profile
    }

    var hasWarp: Bool { profiles.contains { $0.core == .warp } }

    /// Stands in for a subscription URL so WARP gets its own group.
    static let warpGroup = "warp://free"

    /// A server the user picked by hand, which ends automatic selection.
    func choose(_ profile: ServerProfile) {
        isAutomatic = false
        select(profile)
    }

    // MARK: - The link in use

    /// The link Home shows: the one chosen, else the first subscription.
    var activeLink: SubscriptionInfo? {
        subscriptions.first { $0.url == activeLinkURL } ?? subscriptions.first
    }

    /// The servers Home lists, tests and picks from: the link in use, or every server when
    /// there is no link (servers added by hand). WARP is never among them.
    var linkServers: [ServerProfile] {
        let all = profiles.filter { $0.core != .warp }
        guard let url = activeLink?.url else { return all }
        let own = all.filter { $0.subscriptionURL == url }
        return own.isEmpty ? all : own
    }

    /// Home switches to this link; its best line is picked afresh.
    func useLink(_ url: String) {
        activeLinkURL = url
        isAutomatic = true
        lastPingAll = nil
        store.appendTunnelLine("[links] using \(activeLink.map { label(of: $0) } ?? "?"): \(linkDescription)")
    }

    /// For the log: how many servers the link in use has, and how they were matched.
    var linkDescription: String {
        let all = profiles.filter { $0.core != .warp }
        let url = activeLink?.url
        let own = all.filter { $0.subscriptionURL == url }.count
        let keys = Set(all.map { $0.subscriptionURL.map { URL(string: $0)?.lastPathComponent.prefix(4) ?? "?" } ?? "hand" })
        let names = linkServers.prefix(3).map(\.name).joined(separator: " | ")
        return "\(own) own of \(all.count) servers, \(subscriptions.count) links, server keys \(keys.sorted()), first: \(names)"
    }

    /// What a link is called in the list: its title, else its host.
    func label(of link: SubscriptionInfo) -> String {
        if let title = link.title, !title.isEmpty { return title }
        return URL(string: link.url)?.host ?? link.url
    }

    /// Every link's label; two links with the same name get a number, so they can be told apart.
    var linkLabels: [String] {
        let names = subscriptions.map { label(of: $0) }
        var seen: [String: Int] = [:]
        return names.map { name in
            guard names.filter({ $0 == name }).count > 1 else { return name }
            seen[name, default: 0] += 1
            return "\(name) \(seen[name]!)"
        }
    }

    /// Latencies go stale as networks change; older than this they are retested.
    var latenciesAreFresh: Bool {
        lastPingAll.map { Date().timeIntervalSince($0) < 10 * 60 } ?? false
    }

    /// The server to connect to. In automatic mode that is the fastest one,
    /// retesting first unless a test ran in the last few minutes.
    func connectionTarget() async -> ServerProfile? {
        // WARP is a deliberate choice, not something automatic mode overrides.
        if selectedProfile?.core == .warp { return selectedProfile }
        let scope = linkServers
        let selectedInScope = scope.contains { $0.id == selectedId }
        // A server chosen by hand stays, as long as it belongs to the link in use.
        if !isAutomatic, selectedInScope { return selectedProfile }
        guard scope.count > 1 else {
            if let only = scope.first { select(only) }
            return scope.first ?? selectedProfile
        }
        if !latenciesAreFresh { await pingAll(only: scope, markFresh: true) }
        return selectFastest() ?? (selectedInScope ? selectedProfile : scope.first)
    }

    /// Servers grouped by the subscription they came from; hand-added ones last.
    var groups: [(title: String, url: String?, servers: [ServerProfile])] {
        var order: [String?] = []
        var buckets: [String?: [ServerProfile]] = [:]
        for p in profiles {
            let key = p.core == .warp ? Self.warpGroup : p.subscriptionURL
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(p)
        }
        // WARP first, then the subscriptions, then whatever was added by hand.
        let sorted = order.filter { $0 == Self.warpGroup } + order.filter { $0 != nil && $0 != Self.warpGroup } + order.filter { $0 == nil }
        return sorted.map { url in
            let title: String
            if url == Self.warpGroup {
                title = String(localized: "Free")
            } else if let url {
                title = subscriptions.first { $0.url == url }?.title ?? URL(string: url)?.host ?? url
            } else {
                title = String(localized: "Added by hand")
            }
            return (title, url, buckets[url] ?? [])
        }
    }

    /// Adds one profile (deduplicated by outbound) and returns the stored copy.
    @discardableResult
    func add(_ profile: ServerProfile) -> ServerProfile {
        if let existing = profiles.first(where: { $0.outboundJSON == profile.outboundJSON }) {
            var merged = existing
            merged.name = profile.name
            merged.latencyMs = profile.latencyMs ?? existing.latencyMs
            merged.exitIP = profile.exitIP ?? existing.exitIP
            merged.country = profile.country ?? existing.country
            update(merged)
            return merged
        }
        profiles.append(profile)
        persist()
        return profile
    }

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
        activeLinkURL = nil
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
        pruneEmptySubscriptions()
        persist()
    }

    /// A subscription whose servers have all been deleted still listed its quota
    /// in Settings while having nothing left to connect to.
    private func pruneEmptySubscriptions() {
        let live = Set(profiles.compactMap(\.subscriptionURL))
        let kept = subscriptions.filter { live.contains($0.url) }
        guard kept.count != subscriptions.count else { return }
        subscriptions = kept
        store.saveSubscriptions(subscriptions)
    }

    // MARK: - Import

    /// Imports share links / JSON / Clash YAML. Parsing runs off the main thread
    /// so a subscription with thousands of servers cannot freeze the UI.
    @discardableResult
    func importText(_ text: String, subscriptionURL: String? = nil) async -> Int {
        isImporting = true
        defer { isImporting = false }
        return apply(await Self.parse(text, subscriptionURL: subscriptionURL))
    }

    private static func parse(_ text: String, subscriptionURL: String?) async -> ShareLinkParser.Outcome {
        await Task.detached(priority: .userInitiated) {
            ShareLinkParser.parse(text, subscriptionURL: subscriptionURL)
        }.value
    }

    /// Adds parsed servers (deduplicated by outbound) and says how it went. Nothing in here awaits.
    private func apply(_ outcome: ShareLinkParser.Outcome) -> Int {
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
    /// Fetches the subscription and replaces its servers. Returns whether the fetch worked: the
    /// servers stored from before are no proof, since a link the server no longer knows would
    /// otherwise look fine. `refreshOnly` is a refresh of a link already here (the background
    /// update, a refresh button): it never moves a link, and drops its result when the link moved
    /// to another address or was removed while it fetched.
    @discardableResult
    func importSubscription(_ urlString: String, refreshOnly: Bool = false, preferStored: Bool = true, keepAt: String? = nil) async -> Bool {
        guard let resolved = SubscriptionLinkResolver.resolve(urlString) else {
            message = String(localized: "Enter a valid http(s) subscription URL.")
            writeImportLog("invalid subscription input: \(urlString.prefix(60))")
            return false
        }
        // An older address of an account stored under a newer one (an old message in Telegram): the
        // newer one is tried first, so the account does not go back to a filtered host. If that one
        // does not answer with servers, the address given is tried after all.
        let preferred = refreshOnly || !preferStored ? nil : newerStoredLink(for: resolved.url)
        // `keepAt`: the filtered first host only lends its answer; the account stays stored under the newer one.
        let key = keepAt ?? preferred ?? resolved.url
        isImporting = true
        updatingSubscriptionURL = key
        defer { isImporting = false; updatingSubscriptionURL = nil }
        do {
            let (data, http, finalURL) = try await SubscriptionFetcher.fetch(keepAt == nil ? key : resolved.url)
            guard (200..<300).contains(http.statusCode) else {
                if preferred != nil { return await retryGiven(urlString, instead: preferred) }
                // The server answered but does not know the link (404 and the like): plain words.
                message = (400..<500).contains(http.statusCode)
                    ? String(localized: "This link could not be read. It may no longer be valid: ask support for a new one.")
                    : String(format: String(localized: "Subscription server returned HTTP %d."), http.statusCode)
                writeImportLog("subscription HTTP \(http.statusCode) for \(finalURL)")
                return false
            }
            let outcome = await Self.parse(String(decoding: data, as: UTF8.self), subscriptionURL: key)
            if preferred != nil, outcome.profiles.isEmpty { return await retryGiven(urlString, instead: preferred) }
            // From here on nothing awaits, so no other import or refresh can come in between the
            // changes below (a refresh of the old address used to move a moved link back).
            if refreshOnly, !subscriptions.contains(where: { $0.url == key }) {
                writeImportLog("refresh dropped: the link moved or was removed meanwhile")
                return false
            }
            // A link moves only to an address that brought servers.
            if !refreshOnly, !outcome.profiles.isEmpty { moveSameAccount(to: key) }
            let old = profiles.filter { $0.subscriptionURL == key }
            let oldByOutbound = Dictionary(old.map { ($0.outboundJSON, $0) }, uniquingKeysWith: { a, _ in a })
            let previousSelection = selectedProfile
            profiles.removeAll { $0.subscriptionURL == key }
            let added = apply(outcome)
            if added == 0 && !old.isEmpty {
                // Keep the previous servers rather than leaving the user with nothing.
                profiles.append(contentsOf: old)
                persist()
            } else {
                // Carry over what the probes found and keep the same server selected after a refresh.
                for i in profiles.indices where profiles[i].subscriptionURL == key {
                    if let prev = oldByOutbound[profiles[i].outboundJSON] {
                        profiles[i].latencyMs = prev.latencyMs
                        profiles[i].exitIP = prev.exitIP
                        profiles[i].country = prev.country
                    }
                }
                if let prev = previousSelection, prev.subscriptionURL == key,
                   let same = profiles.first(where: { $0.outboundJSON == prev.outboundJSON }) {
                    selectedId = same.id
                }
                persist()
            }
            updateSubscriptionInfo(url: key, headers: http.allHeaderFields, fallbackTitle: resolved.title)
            writeImportLog("subscription ok: added=\(added) total=\(profiles.count) final=\(finalURL)")
            if ProfileStore.shared.loadSettings().pingAfterSubscriptionUpdate, added > 0 {
                Task { await pingAll(); sortByLatency() }
            }
            return added > 0
        } catch {
            if preferred != nil { return await retryGiven(urlString, instead: preferred) }
            message = String(format: String(localized: "Download failed: %@"), error.localizedDescription)
            writeImportLog("subscription failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The newer stored address did not answer with servers: the address given is tried after all.
    /// The account moves there, except onto the first host, which is filtered in Iran: that one only
    /// lends its answer, and the account stays stored under the newer address.
    private func retryGiven(_ urlString: String, instead preferred: String?) async -> Bool {
        let given = SubscriptionLinkResolver.resolve(urlString)?.url ?? urlString
        let lendOnly = SubscriptionLinkResolver.hostRank(of: given) == 0
        return await importSubscription(urlString, preferStored: false, keepAt: lendOnly ? preferred : nil)
    }

    /// The same account on another of the service's hosts (the bot hands out a newer address once
    /// the old one is filtered): its servers, quota and place as the link in use move to `url`
    /// instead of a second copy of the account appearing. Every copy folds into one: builds before
    /// 1.1.6 (21) kept a second, empty entry when the same account came from another host. Called
    /// only once `url` has answered, so a link never moves to an address that does not work.
    private func moveSameAccount(to url: String) {
        guard let account = SubscriptionLinkResolver.serviceAccount(of: url) else { return }
        let others = Set(subscriptions.map(\.url).filter { $0 != url && SubscriptionLinkResolver.serviceAccount(of: $0) == account })
        guard !others.isEmpty else { return }
        if !subscriptions.contains(where: { $0.url == url }), let i = subscriptions.firstIndex(where: { others.contains($0.url) }) {
            subscriptions[i].url = url   // the first copy keeps its place in the list, under the new address
        }
        subscriptions.removeAll { others.contains($0.url) }
        for i in profiles.indices where profiles[i].subscriptionURL.map(others.contains) == true { profiles[i].subscriptionURL = url }
        if let active = activeLinkURL, others.contains(active) { activeLinkURL = url }
        store.saveSubscriptions(subscriptions)
        persist()
        writeImportLog("the same account moved from \(others.compactMap { URL(string: $0)?.host }.sorted()) to \(URL(string: url)?.host ?? "?")")
    }

    /// The link an account is stored under already when `url` names an older address of it (later
    /// service hosts are newer; the first is filtered in Iran): that one is tried first. nil otherwise.
    private func newerStoredLink(for url: String) -> String? {
        guard let account = SubscriptionLinkResolver.serviceAccount(of: url) else { return nil }
        let rank = SubscriptionLinkResolver.hostRank(of: url)
        return subscriptions.map(\.url)
            .filter { SubscriptionLinkResolver.serviceAccount(of: $0) == account && SubscriptionLinkResolver.hostRank(of: $0) > rank }
            .max { SubscriptionLinkResolver.hostRank(of: $0) < SubscriptionLinkResolver.hostRank(of: $1) }
    }

    /// The stored link for `url`: the same one, or the same account under another of the service's hosts.
    func storedLink(for url: String) -> String? {
        if subscriptions.contains(where: { $0.url == url }) { return url }
        guard let account = SubscriptionLinkResolver.serviceAccount(of: url) else { return nil }
        return subscriptions.first { SubscriptionLinkResolver.serviceAccount(of: $0.url) == account }?.url
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
        for sub in subscriptions { await importSubscription(sub.url, refreshOnly: true) }
    }

    /// Refreshes subscriptions whose own interval (or the app-wide interval) has elapsed.
    func updateStaleSubscriptions(defaultHours: Int) async {
        for sub in subscriptions {
            let hours = sub.updateIntervalHours ?? defaultHours
            guard hours > 0 else { continue }
            if Date().timeIntervalSince(sub.lastUpdated) > Double(hours) * 3600 {
                await importSubscription(sub.url, refreshOnly: true)
            }
        }
    }

    func removeSubscription(_ url: String) {
        subscriptions.removeAll { $0.url == url }
        store.saveSubscriptions(subscriptions)
        profiles.removeAll { $0.subscriptionURL == url }
        if activeLinkURL == url { activeLinkURL = nil; isAutomatic = true; lastPingAll = nil }
        fixSelectionAndPersist()
    }

    // MARK: - Latency

    /// Probes every server, five per core instance and three instances at a
    /// time, so hundreds of servers finish in reasonable time. Each probe
    /// records the delay and where the traffic comes out.
    /// `subset` limits the test to those servers, e.g. the ones a subscription just brought in.
    /// `markFresh` counts a test of the link in use as the full test for "latencies are fresh".
    func pingAll(only subset: [ServerProfile]? = nil, markFresh: Bool = false) async {
        // WARP has no outbound of its own, so neither core can test it.
        let snapshot = (subset ?? profiles).filter { $0.core != .warp }
        guard !isPinging, !snapshot.isEmpty else { return }
        isPinging = true
        pingProgress = (0, snapshot.count)
        let chunks = stride(from: 0, to: snapshot.count, by: AppConstants.pingBatchSize).map {
            Array(snapshot[$0..<min($0 + AppConstants.pingBatchSize, snapshot.count)])
        }
        pingTask = Task { [weak self] in
            await withTaskGroup(of: [(UUID, ProbeResult)].self) { group in
                var next = 0
                func enqueue() {
                    guard next < chunks.count, !Task.isCancelled else { return }
                    let chunk = chunks[next]; next += 1
                    group.addTask(priority: .userInitiated) {
                        let results = CoreProbe.probe(chunk)
                        return zip(chunk, results).map { ($0.id, $1) }
                    }
                }
                for _ in 0..<AppConstants.pingConcurrentBatches { enqueue() }
                for await batch in group {
                    await MainActor.run {
                        guard let self else { return }
                        for (id, result) in batch { self.record(result, for: id) }
                        self.pingProgress = (self.pingProgress.done + batch.count, self.pingProgress.total)
                    }
                    enqueue()
                }
            }
        }
        await pingTask?.value
        if subset == nil || markFresh, pingTask?.isCancelled == false { lastPingAll = Date() }
        pingTask = nil
        isPinging = false
        persist()
    }

    /// Writes a probe's findings onto the server. A failed probe keeps the
    /// last known exit: the server is down now, not somewhere else.
    func record(_ result: ProbeResult, for id: UUID) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].latencyMs = result.success ? result.delayMs : -1
        if result.success {
            profiles[i].exitIP = result.exitIP ?? profiles[i].exitIP
            profiles[i].country = result.country ?? profiles[i].country
        }
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
        // "Auto" is the fastest line of the link in use.
        if let best = linkServers.filter({ ($0.latencyMs ?? -1) > 0 }).min(by: { $0.latencyMs! < $1.latencyMs! }) {
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
            p.subscriptionURL = "https://demo.example.net/sub"
            return p
        }
        profiles = [
            make("Frankfurt · Reality", "vless", "de1.example.net", 443, 84),
            make("Amsterdam · XHTTP", "vless", "nl1.example.net", 8443, 96),
            make("Helsinki · WebSocket", "vmess", "fi1.example.net", 443, 121),
            make("London · Trojan", "trojan", "uk1.example.net", 443, 133),
            make("Paris · Hysteria2", "hysteria2", "fr1.example.net", 443, 148),
            make("Warsaw · Shadowsocks", "shadowsocks", "pl1.example.net", 8388, 162),
            make("Zurich · TUIC", "tuic", "ch1.example.net", 443, 171, core: .singbox),
            make("Stockholm · SSH", "ssh", "se1.example.net", 22, 204, core: .singbox),
            make("New York · Reality", "vless", "us1.example.net", 443, 236),
            make("Tokyo · WebSocket", "vless", "jp1.example.net", 443, 318),
        ]
        selectedId = profiles.first?.id
        isAutomatic = true   // "Auto", as most users run it
        subscriptions = [SubscriptionInfo(url: "https://demo.example.net/sub", title: "Home",
                                          upload: 6_400_000_000, download: 58_900_000_000, total: 200_000_000_000,
                                          expire: Date().addingTimeInterval(23 * 24 * 3600), lastUpdated: Date(),
                                          updateIntervalHours: 12, webPageURL: nil, supportURL: nil),
                         SubscriptionInfo(url: "https://demo.example.net/family", title: "Family",
                                          upload: 900_000_000, download: 12_300_000_000, total: 0,
                                          expire: Date().addingTimeInterval(61 * 24 * 3600), lastUpdated: Date(),
                                          updateIntervalHours: 12, webPageURL: nil, supportURL: nil),
                         SubscriptionInfo(url: "https://demo.example.net/travel", title: "Travel",
                                          upload: 200_000_000, download: 3_100_000_000, total: 50_000_000_000,
                                          expire: Date().addingTimeInterval(9 * 24 * 3600), lastUpdated: Date(),
                                          updateIntervalHours: 12, webPageURL: nil, supportURL: nil)]
        if DemoRouter.screen == "empty" {
            profiles = []
            subscriptions = []
            selectedId = nil
        }
    }
}

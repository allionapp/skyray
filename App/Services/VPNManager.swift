import Foundation
import NetworkExtension
import Combine

struct TunnelStats: Decodable {
    var txBytes: Int
    var rxBytes: Int
    var xrayRunning: Bool
    var memoryBytes: Int?
}

/// Owns the NETunnelProviderManager and mirrors its status for SwiftUI.
@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published var lastError: String?
    /// Why the tunnel stopped itself, when it wasn't an error: the ad was skipped.
    @Published var notice: String?
    @Published private(set) var stats: TunnelStats?
    @Published private(set) var connectedSince: Date?
    /// Where the tunnel's traffic comes out, fetched through the tunnel itself
    /// once it is up: the proof that traffic really flows, and through where.
    @Published private(set) var exitInfo: (ip: String, country: String?)?
    private var exitTask: Task<Void, Never>?
    /// Current throughput in bytes/second, derived from consecutive stats samples.
    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var downloadSpeed: Double = 0
    /// Last 12 download-speed samples normalised to 0...1 for the home sparkline.
    @Published private(set) var speedHistory: [Double] = Array(repeating: 0.02, count: 12)
    private var rawHistory: [Double] = []
    @Published var settings: AppSettings {
        didSet { ProfileStore.shared.saveSettings(settings) }
    }

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var statsTimer: Timer?
    private var isActive = true
    private var lastSample: (date: Date, tx: Int, rx: Int)?

    /// Marketing/demo mode (-DemoMode YES): shows a connected state without a tunnel.
    private(set) var isDemo = false

    func enableDemo() {
        isDemo = true
        status = .connected
        connectedSince = Date().addingTimeInterval(-47 * 60)
        stats = TunnelStats(txBytes: 184_320_000, rxBytes: 1_402_000_000, xrayRunning: true, memoryBytes: 18 * 1024 * 1024)
        uploadSpeed = 1_250_000
        downloadSpeed = 9_800_000
        speedHistory = [0.22, 0.38, 0.31, 0.64, 0.52, 0.45, 0.7, 0.58, 0.83, 0.88, 0.71, 0.44]
        lastError = nil
        if settings.customRules.isEmpty {
            settings.customRules = [
                RoutingRule(pattern: "geosite:category-ir", action: .direct),
                RoutingRule(pattern: "domain:youtube.com", action: .proxy),
                RoutingRule(pattern: "keyword:doubleclick", action: .block, enabled: false),
            ]
        }
    }

    init() {
        settings = ProfileStore.shared.loadSettings()
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] note in
            guard let self, let connection = note.object as? NEVPNConnection else { return }
            Task { @MainActor in self.apply(status: connection.status) }
        }
        Task { await load() }
    }

    var isBusy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }
    var isConnected: Bool { status == .connected }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConstants.tunnelBundleId
            }) ?? managers.first
            apply(status: manager?.connection.status ?? .disconnected)
        } catch {
            lastError = error.localizedDescription
            apply(status: .invalid)
        }
    }

    func connect(profile: ServerProfile) async {
        lastError = nil
        notice = nil
        ProfileStore.shared.writeActiveProfile(profile)
        do {
            let manager = try await prepareManager(for: profile)
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = friendlyMessage(error)
            mirrorTunnelLog()
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    /// Switches server while connected: the tunnel restarts with the new profile.
    func reconnect(profile: ServerProfile, force: Bool = false) async {
        if force || isConnected || status == .connecting || status == .reasserting {
            disconnect()
            var waited = 0
            while status != .disconnected && status != .invalid && waited < 60 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                waited += 1
            }
            debugNote = "reconnect waited \(waited * 250) ms, status now \(status.label)"
        }
        await connect(profile: profile)
    }

    func toggle(profile: ServerProfile?) async {
        if isDemo { return }
        if isConnected || status == .connecting {
            disconnect()
        } else if let profile {
            await connect(profile: profile)
        } else {
            lastError = String(localized: "Add and select a server first.")
        }
    }

    /// Applies settings that live on the VPN configuration (on-demand, kill switch).
    func applySettingsToConfiguration() async {
        guard let manager, let profile = ProfileStore.shared.readActiveProfile() else { return }
        _ = try? await prepareManager(for: profile, existing: manager)
    }

    private func prepareManager(for profile: ServerProfile, existing: NETunnelProviderManager? = nil) async throws -> NETunnelProviderManager {
        let manager = existing ?? self.manager ?? NETunnelProviderManager()
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppConstants.tunnelBundleId
        proto.serverAddress = profile.address.isEmpty ? "SkyRay" : profile.address
        proto.providerConfiguration = ["profileId": profile.id.uuidString]
        // Never tear the tunnel down just because the screen locks.
        proto.disconnectOnSleep = !settings.keepAliveOnSleep
        // Kill switch: with includeAllNetworks nothing leaves the device outside the tunnel.
        proto.includeAllNetworks = settings.killSwitch
        proto.excludeLocalNetworks = settings.killSwitch && settings.routingMode != .global
        manager.protocolConfiguration = proto
        manager.localizedDescription = AppConstants.vpnDisplayName
        manager.isEnabled = true
        manager.isOnDemandEnabled = settings.connectOnDemand
        manager.onDemandRules = settings.connectOnDemand ? [NEOnDemandRuleConnect()] : nil
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager
        return manager
    }

    private func apply(status newStatus: NEVPNStatus) {
        if isDemo { return }
        status = newStatus
        mirrorTunnelLog()
        if newStatus == .connected {
            let isFreshConnect = connectedSince == nil
            if connectedSince == nil { connectedSince = manager?.connection.connectedDate ?? Date() }
            startStatsTimer()
            if isFreshConnect {
                fetchExitInfo()
                // Make the ad SDK report the exit node, not the real device: set
                // the locale/time zone to the exit's (neutral until the probe
                // resolves it, refined in fetchExitInfo), then start the SDK now
                // — over the tunnel — rather than at launch on the real network.
                AdSignalOverride.apply(country: exitInfo?.country)
                AdsManager.shared.tunnelUp = true
                AdsManager.shared.start()
                AdsManager.shared.showAfterConnect { [weak self] in
                    // The ad was closed early: the free connection ends with it.
                    self?.debugNote = "ad closed before the reward; disconnecting"
                    self?.notice = String(localized: "The connection needs the short ad watched through to the end. Tap connect and let it finish.")
                    self?.disconnect()
                }
            }
        } else {
            // Put the device's real locale/time zone back the moment the tunnel
            // is no longer carrying the traffic. No-op if never applied.
            AdSignalOverride.restore()
            AdsManager.shared.tunnelUp = false
            connectedSince = nil
            exitTask?.cancel()
            exitTask = nil
            exitInfo = nil
            stats = nil
            lastSample = nil
            rawHistory = []
            speedHistory = Array(repeating: 0.02, count: 12)
            uploadSpeed = 0
            downloadSpeed = 0
            statsTimer?.invalidate()
            statsTimer = nil
        }
    }

    /// Asks Cloudflare, through the tunnel, where this connection comes out.
    /// The app's own traffic rides the tunnel on iOS, so a plain request is
    /// the honest measurement. Retried a few times: the tunnel reports
    /// connected a moment before the first bytes can flow.
    private func fetchExitInfo() {
        exitTask?.cancel()
        exitTask = Task { [weak self] in
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.waitsForConnectivity = false
            let session = URLSession(configuration: config)
            guard let url = URL(string: AppConstants.probeURL) else { return }
            for attempt in 0..<4 {
                if Task.isCancelled { return }
                if let (data, _) = try? await session.data(from: url) {
                    var ip: String?, country: String?
                    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                        let parts = line.split(separator: "=", maxSplits: 1)
                        guard parts.count == 2 else { continue }
                        if parts[0] == "ip" { ip = String(parts[1]) }
                        if parts[0] == "loc" { country = String(parts[1]) }
                    }
                    if let ip {
                        await MainActor.run {
                            self?.exitInfo = (ip, country)
                            // Refine the ad-signal override to the exact exit
                            // country, but only while still connected — the probe
                            // can resolve just after a disconnect.
                            if self?.status == .connected { AdSignalOverride.apply(country: country) }
                        }
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(1 + attempt) * 1_000_000_000)
            }
        }
    }

    /// Called from the scene phase: polling stats while backgrounded only burns battery.
    func setActive(_ active: Bool) {
        isActive = active
        if active, isConnected { startStatsTimer() } else { statsTimer?.invalidate(); statsTimer = nil }
    }

    private func startStatsTimer() {
        guard isActive else { return }
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshStats() }
        }
        Task { await refreshStats() }
    }

    func refreshStats() async {
        guard let session = manager?.connection as? NETunnelProviderSession, status == .connected else { return }
        do {
            let data: Data? = try await withCheckedThrowingContinuation { continuation in
                do {
                    try session.sendProviderMessage(Data("stats".utf8)) { continuation.resume(returning: $0) }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            if let data, let s = try? JSONDecoder().decode(TunnelStats.self, from: data) {
                if let last = lastSample {
                    let dt = max(0.5, Date().timeIntervalSince(last.date))
                    uploadSpeed = max(0, Double(s.txBytes - last.tx) / dt)
                    downloadSpeed = max(0, Double(s.rxBytes - last.rx) / dt)
                    rawHistory.append(downloadSpeed + uploadSpeed)
                    if rawHistory.count > 12 { rawHistory.removeFirst(rawHistory.count - 12) }
                    let peak = max(rawHistory.max() ?? 1, 1)
                    var normalised = rawHistory.map { max(0.02, $0 / peak) }
                    while normalised.count < 12 { normalised.insert(0.02, at: 0) }
                    speedHistory = normalised
                }
                lastSample = (Date(), s.txBytes, s.rxBytes)
                stats = s
            }
        } catch {
            // Stats are best-effort.
        }
    }

    /// Fetches a small page through the tunnel and records the result in the
    /// mirrored log, so an end-to-end check can be read off the device.
    func runSelfTest() async {
        var lines: [String] = ["[selftest] status: \(status.label)"]
        let session = URLSession(configuration: .ephemeral)
        for urlString in ["https://www.google.com/generate_204", "https://api.ipify.org?format=text"] {
            guard let url = URL(string: urlString) else { continue }
            let started = Date()
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await session.data(for: request)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("[selftest] \(urlString) -> HTTP \(code) in \(ms) ms \(body.isEmpty ? "" : "body=\(body)")")
            } catch {
                lines.append("[selftest] \(urlString) -> error: \(error.localizedDescription)")
            }
        }
        await refreshStats()
        selfTestReport = lines.joined(separator: "\n")
        mirrorTunnelLog()
    }

    private var selfTestReport: String?
    var debugNote: String?

    /// Copies the extension's log from the App Group into Documents/tunnel.log
    /// (the app container is reachable with `devicectl device copy from`).
    func mirrorTunnelLog() {
        let log = ProfileStore.shared.readTunnelLog()
        guard !log.isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        var text = log
        if let error = lastError { text += "[app] lastError: \(error)\n" }
        text += "[app] status: \(status.label)\n"
        text += "[app] settings: routing=\(settings.routingMode.rawValue) ads=\(settings.blockAds) fragment=\(settings.fragmentEnabled) rules=\(settings.customRules.count) lan=\(settings.allowLAN)\n"
        if let note = debugNote { text += "[app] debug: \(note)\n" }
        if let stats { text += "[app] stats: tx=\(stats.txBytes) rx=\(stats.rxBytes) xrayRunning=\(stats.xrayRunning) memory=\((stats.memoryBytes ?? 0) / 1024 / 1024)MB\n" }
        if let selfTestReport { text += selfTestReport + "\n" }
        try? text.write(to: docs.appendingPathComponent("tunnel.log"), atomically: true, encoding: .utf8)
    }

    private func friendlyMessage(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NEVPNErrorDomain || ns.domain == "NEConfigurationErrorDomain" {
            #if targetEnvironment(simulator)
            return String(localized: "VPN tunnels are not supported in the iOS Simulator. Run on a real device.")
            #endif
            if ns.code == NEVPNError.configurationReadWriteFailed.rawValue {
                return String(localized: "VPN permission was not granted. Tap Connect again and choose Allow.")
            }
        }
        return error.localizedDescription
    }
}

extension NEVPNStatus {
    var label: String {
        switch self {
        case .invalid: return String(localized: "Not configured")
        case .disconnected: return String(localized: "Disconnected")
        case .connecting: return String(localized: "Connecting…")
        case .connected: return String(localized: "Connected")
        case .reasserting: return String(localized: "Reconnecting…")
        case .disconnecting: return String(localized: "Disconnecting…")
        @unknown default: return String(localized: "Unknown")
        }
    }
}

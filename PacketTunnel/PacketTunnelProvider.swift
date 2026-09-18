import Foundation
import NetworkExtension

enum TunnelError: LocalizedError {
    case noProfile
    case noTunFD
    case hevExited(Int32)
    case xrayDied

    var errorDescription: String? {
        switch self {
        case .noProfile: return "No server selected"
        case .noTunFD: return "Could not find the tunnel file descriptor"
        case .hevExited(let code): return "Packet tunnel exited with code \(code)"
        case .xrayDied: return "Xray core stopped unexpectedly"
        }
    }
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let hev = HevTunnel()
    private var stopping = false
    private var watchdog: DispatchSourceTimer?
    private var settings = AppSettings()
    private var activeCore: CoreKind = .xray
    private let watchdogQueue = DispatchQueue(label: "tunnel.watchdog")

    override func startTunnel(options: [String: NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        TunnelLog.clear()
        settings = ProfileStore.shared.loadSettings()
        TunnelLog.write("Starting tunnel, Xray \(XrayCore.version()), memory \(String(format: "%.1f", MemoryMonitor.footprintMB())) MB, routing \(settings.routingMode.rawValue)")

        // Read only the active profile, never the whole server list: parsing a
        // subscription with thousands of servers here would exhaust the memory cap.
        guard let profile = ProfileStore.shared.readActiveProfile() else {
            TunnelLog.write("No active profile written by the app")
            completionHandler(TunnelError.noProfile)
            return
        }
        TunnelLog.write("Profile: \(profile.name) (\(profile.subtitle))")

        // Trimmed geoip/geosite (Iran, ads, private) ship inside the extension bundle.
        let hasGeoData = Bundle.main.url(forResource: "geosite", withExtension: "dat") != nil
        if hasGeoData {
            setenv("XRAY_LOCATION_ASSET", Bundle.main.bundlePath, 1)
        }
        activeCore = profile.core
        // WARP runs its own core and proxy; the others are built here.
        let socksPort = profile.core == .warp ? AppConstants.warpSocksPort : AppConstants.socksPort
        do {
            switch profile.core {
            case .warp:
                let directory = ProfileStore.shared.containerURL.appendingPathComponent("warp", isDirectory: true)
                let transport = try WarpCore.start(port: socksPort, configDirectory: directory)
                TunnelLog.write("WARP \(WarpCore.version) ready over \(transport) on 127.0.0.1:\(socksPort)")
            case .xray:
                let config = try XrayConfigBuilder.runtimeConfig(outboundJSON: profile.outboundJSON, settings: settings, hasGeoData: hasGeoData)
                try XrayCore.run(config)
                TunnelLog.write("Xray core started on \(settings.allowLAN ? "0.0.0.0" : "127.0.0.1"):\(AppConstants.socksPort) geo=\(hasGeoData) ads=\(settings.blockAds) fragment=\(settings.fragmentEnabled) rules=\(settings.customRules.count)")
            case .singbox:
                let config = try SingboxConfigBuilder.runtimeConfig(outboundJSON: profile.outboundJSON, settings: settings)
                try SingboxCore.run(config)
                TunnelLog.write("sing-box \(SingboxCore.version()) started on \(settings.allowLAN ? "0.0.0.0" : "127.0.0.1"):\(AppConstants.socksPort) ads=\(settings.blockAds) rules=\(settings.customRules.count)")
            }
        } catch {
            TunnelLog.write("\(profile.core.rawValue) failed to start: \(error.localizedDescription)")
            completionHandler(error)
            return
        }

        setTunnelNetworkSettings(makeNetworkSettings()) { [weak self] error in
            guard let self else { return }
            if let error {
                TunnelLog.write("Network settings rejected: \(error.localizedDescription)")
                self.stopCore()
                completionHandler(error)
                return
            }
            guard let fd = TunnelFD.find(in: self) else {
                TunnelLog.write("utun file descriptor not found")
                self.stopCore()
                completionHandler(TunnelError.noTunFD)
                return
            }
            TunnelLog.write("utun fd = \(fd), starting hev-socks5-tunnel")
            self.hev.start(tunFD: fd, socksPort: socksPort) { [weak self] code in
                guard let self, !self.stopping else { return }
                TunnelLog.write("hev-socks5-tunnel exited unexpectedly (\(code))")
                self.cancelTunnelWithError(TunnelError.hevExited(code))
            }
            self.startWatchdog()
            TunnelLog.write("Tunnel is up, memory \(String(format: "%.1f", MemoryMonitor.footprintMB())) MB")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopping = true
        TunnelLog.write("Stopping tunnel (reason \(reason.rawValue))")
        watchdog?.cancel()
        watchdog = nil
        hev.stop()
        stopCore()
        completionHandler()
    }

    private func coreRunning() -> Bool {
        switch activeCore {
        // WARP reports through its own job; the proxy port answering is the
        // signal the watchdog needs, and hev already fails loudly without it.
        case .warp: return true
        case .xray: return XrayCore.isRunning()
        case .singbox: return SingboxCore.isRunning()
        }
    }

    private func stopCore() {
        do {
            switch activeCore {
            case .warp: WarpCore.stop()
            case .xray: try XrayCore.stop()
            case .singbox: try SingboxCore.stop()
            }
        } catch {
            TunnelLog.write("Core stop error: \(error.localizedDescription)")
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        TunnelLog.write("Device sleeping; tunnel stays up")
        completionHandler()
    }

    override func wake() {
        TunnelLog.write("Device woke; core running=\(coreRunning()), memory \(String(format: "%.1f", MemoryMonitor.footprintMB())) MB")
        if !coreRunning() && !stopping {
            cancelTunnelWithError(TunnelError.xrayDied)
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        let command = String(decoding: messageData, as: UTF8.self)
        switch command {
        case "stats":
            let s = hev.stats()
            let dict: [String: Any] = ["txBytes": s.txBytes, "rxBytes": s.rxBytes,
                                       "txPackets": s.txPackets, "rxPackets": s.rxPackets,
                                       "xrayRunning": coreRunning(),
                                       "memoryBytes": MemoryMonitor.footprintBytes()]
            completionHandler?(try? JSONSerialization.data(withJSONObject: dict))
        default:
            completionHandler?(nil)
        }
    }

    /// Detects a dead core instead of silently leaving the device without
    /// connectivity, and logs memory so near-limit conditions are diagnosable.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        var ticks = 0
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopping else { return }
            ticks += 1
            let bytes = MemoryMonitor.footprintBytes()
            if bytes > AppConstants.extensionMemoryWarningBytes {
                TunnelLog.write("Memory high: \(bytes / 1024 / 1024) MB (limit ~50 MB)")
            } else if ticks % 4 == 0 {
                TunnelLog.write("Health: core=\(self.coreRunning()) memory=\(bytes / 1024 / 1024) MB")
            }
            if !self.coreRunning() {
                TunnelLog.write("Core is no longer running; cancelling tunnel")
                self.cancelTunnelWithError(TunnelError.xrayDied)
            }
        }
        timer.resume()
        watchdog = timer
    }

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        networkSettings.mtu = NSNumber(value: HevTunnel.mtu)

        let ipv4 = NEIPv4Settings(addresses: [HevTunnel.tunnelAddress], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        if settings.routingMode != .global {
            ipv4.excludedRoutes = [
                NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
                NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
            ]
        }
        networkSettings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: [HevTunnel.tunnelAddressV6], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        networkSettings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: settings.dnsServers.isEmpty ? ["1.1.1.1", "8.8.8.8"] : settings.dnsServers)
        dns.matchDomains = [""]
        networkSettings.dnsSettings = dns
        return networkSettings
    }
}

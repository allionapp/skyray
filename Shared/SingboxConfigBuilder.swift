import Foundation

/// Builds a full sing-box configuration mirroring what XrayConfigBuilder does:
/// a local SOCKS inbound for hev-socks5-tunnel, the user's outbound, DNS and routing.
enum SingboxConfigBuilder {
    /// sing-box 1.12+ DNS server object from a user-facing address:
    /// https://host/path (DoH), tls://host (DoT), or a plain IP (UDP).
    static func dnsServer(tag: String, address: String, detour: String) -> [String: Any] {
        var server: [String: Any] = ["tag": tag, "detour": detour]
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("https://"), let url = URL(string: trimmed), let host = url.host {
            server["type"] = "https"
            server["server"] = host
            if let port = url.port { server["server_port"] = port }
            if !url.path.isEmpty, url.path != "/dns-query" { server["path"] = url.path }
        } else if trimmed.lowercased().hasPrefix("tls://") {
            server["type"] = "tls"
            let hostPort = String(trimmed.dropFirst(6))
            let parts = hostPort.split(separator: ":")
            server["server"] = String(parts.first ?? "1.1.1.1")
            if parts.count == 2, let port = Int(parts[1]) { server["server_port"] = port }
        } else if trimmed.lowercased().hasPrefix("quic://") {
            server["type"] = "quic"
            server["server"] = String(trimmed.dropFirst(7))
        } else {
            server["type"] = "udp"
            server["server"] = trimmed.isEmpty ? "8.8.8.8" : trimmed
        }
        return server
    }

    static func runtimeConfig(outboundJSON: String,
                              settings: AppSettings = AppSettings(),
                              socksPort: Int = AppConstants.socksPort) throws -> String {
        guard let data = outboundJSON.data(using: .utf8),
              var proxy = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw XrayCoreError.invoke("Invalid outbound JSON") }
        proxy["tag"] = "proxy"
        if settings.fragmentEnabled, var tls = proxy["tls"] as? [String: Any], tls["enabled"] as? Bool == true {
            tls["fragment"] = true
            proxy["tls"] = tls
        }

        var rules: [[String: Any]] = []
        if settings.routingMode != .global {
            rules.append(["ip_is_private": true, "outbound": "direct"])
        }
        if settings.blockAds {
            rules.append(["domain_suffix": ["doubleclick.net", "googlesyndication.com", "googleadservices.com",
                                            "adnxs.com", "yektanet.com", "tapsell.ir", "adro.co", "mediaad.org",
                                            "sabavision.com", "daartads.com", "adivery.com"],
                          "outbound": "block"])
        }
        for rule in settings.customRules where rule.enabled && !rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespaces)
            var r: [String: Any] = ["outbound": rule.action.rawValue]
            if rule.isIP {
                guard !pattern.lowercased().hasPrefix("geoip:") else { continue }
                r["ip_cidr"] = [pattern.contains("/") ? pattern : (pattern.contains(":") ? pattern + "/128" : pattern + "/32")]
            } else if pattern.lowercased().hasPrefix("full:") {
                r["domain"] = [String(pattern.dropFirst(5))]
            } else if pattern.lowercased().hasPrefix("domain:") {
                r["domain_suffix"] = [String(pattern.dropFirst(7))]
            } else if pattern.lowercased().hasPrefix("keyword:") {
                r["domain_keyword"] = [String(pattern.dropFirst(8))]
            } else if pattern.lowercased().hasPrefix("regexp:") {
                r["domain_regex"] = [String(pattern.dropFirst(7))]
            } else if pattern.lowercased().hasPrefix("geosite:") {
                continue // geosite lists are Xray-only
            } else {
                r["domain_suffix"] = [pattern]
            }
            rules.append(r)
        }
        if settings.routingMode == .bypassIran {
            rules.append(["domain_suffix": [".ir"], "outbound": "direct"])
        }

        var dnsServers: [[String: Any]] = []
        if settings.routingMode == .bypassIran {
            dnsServers.append(dnsServer(tag: "dns-direct", address: settings.directDNS, detour: "direct"))
        }
        dnsServers.append(dnsServer(tag: "dns-remote", address: settings.remoteDNS, detour: "proxy"))
        var dnsRules: [[String: Any]] = []
        if settings.routingMode == .bypassIran {
            dnsRules.append(["domain_suffix": [".ir"], "server": "dns-direct"])
        }

        var inbounds: [[String: Any]] = [[
            "type": "socks", "tag": "socks-in",
            "listen": settings.allowLAN ? "0.0.0.0" : "127.0.0.1",
            "listen_port": socksPort,
        ]]
        if settings.allowLAN {
            inbounds.append(["type": "http", "tag": "http-in", "listen": "0.0.0.0", "listen_port": settings.httpPort])
        }

        let config: [String: Any] = [
            "log": ["level": settings.logLevel == "warning" ? "warn" : (settings.logLevel == "none" ? "panic" : settings.logLevel), "timestamp": false],
            "dns": ["servers": dnsServers, "rules": dnsRules, "final": "dns-remote", "strategy": "prefer_ipv4"],
            "inbounds": inbounds,
            "outbounds": [
                proxy,
                ["type": "direct", "tag": "direct"],
                ["type": "block", "tag": "block"],
            ],
            "route": [
                "rules": [["action": "sniff"], ["protocol": "dns", "action": "hijack-dns"]] + rules,
                "final": "proxy",
                "auto_detect_interface": false,
            ],
        ]
        let json = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: json, as: UTF8.self)
    }
}

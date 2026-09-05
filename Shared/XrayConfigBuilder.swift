import Foundation

/// Builds the full Xray runtime configuration used inside the tunnel:
/// inbounds (SOCKS + HTTP), the user's outbound, DNS, policy and routing.
enum XrayConfigBuilder {
    static let privateRanges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8",
                                "169.254.0.0/16", "100.64.0.0/10", "fc00::/7", "fe80::/10", "::1/128"]

    static func runtimeConfig(outboundJSON: String,
                              settings: AppSettings = AppSettings(),
                              socksPort: Int = AppConstants.socksPort,
                              hasGeoData: Bool = true) throws -> String {
        guard let data = outboundJSON.data(using: .utf8),
              var proxy = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw XrayCoreError.invoke("Invalid outbound JSON") }
        proxy["tag"] = "proxy"
        if settings.muxEnabled {
            proxy["mux"] = ["enabled": true, "concurrency": 8]
        } else {
            proxy.removeValue(forKey: "mux")
        }

        var outbounds: [[String: Any]] = []
        if settings.fragmentEnabled {
            // Route the proxy's own TCP dial through a freedom outbound that
            // fragments the TLS ClientHello (defeats SNI filtering on some networks).
            var stream = proxy["streamSettings"] as? [String: Any] ?? [:]
            var sockopt = stream["sockopt"] as? [String: Any] ?? [:]
            sockopt["dialerProxy"] = "fragment"
            stream["sockopt"] = sockopt
            proxy["streamSettings"] = stream
            outbounds.append([
                "tag": "fragment",
                "protocol": "freedom",
                "settings": [
                    "domainStrategy": "UseIP",
                    "fragment": ["packets": settings.fragmentPackets,
                                 "length": settings.fragmentLength,
                                 "interval": settings.fragmentInterval],
                ],
                "streamSettings": ["sockopt": ["tcpNoDelay": true]],
            ])
        }
        outbounds.insert(proxy, at: 0)
        outbounds.append(["tag": "direct", "protocol": "freedom", "settings": ["domainStrategy": "UseIP"]])
        outbounds.append(["tag": "block", "protocol": "blackhole"])

        // Routing rules, first match wins.
        var rules: [[String: Any]] = []
        if settings.routingMode != .global {
            rules.append(["type": "field", "ip": hasGeoData ? ["geoip:private"] + privateRanges : privateRanges, "outboundTag": "direct"])
        }
        if settings.blockAds {
            // Compact list: the big ad networks (geosite:category-ads, ~700 domains)
            // plus the main Iranian ad networks. The full 38k-domain list costs
            // ~10 MB inside the 50 MB extension budget, so it is deliberately not used.
            var ads = ["domain:doubleclick.net", "domain:googlesyndication.com", "domain:googleadservices.com",
                       "domain:adservice.google.com", "domain:adnxs.com", "domain:yektanet.com", "domain:tapsell.ir",
                       "domain:adro.co", "domain:mediaad.org", "domain:sabavision.com", "domain:daartads.com",
                       "domain:adivery.com", "domain:magnetadservices.com", "domain:e-planning.net"]
            if hasGeoData { ads.insert("geosite:category-ads", at: 0) }
            rules.append(["type": "field", "domain": ads, "outboundTag": "block"])
        }
        var domainRules: [RuleAction: [String]] = [:]
        var ipRules: [RuleAction: [String]] = [:]
        for rule in settings.customRules where rule.enabled && !rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespaces)
            if rule.isIP { ipRules[rule.action, default: []].append(pattern) } else { domainRules[rule.action, default: []].append(pattern) }
        }
        for action in RuleAction.allCases {
            if let domains = domainRules[action] { rules.append(["type": "field", "domain": domains, "outboundTag": action.rawValue]) }
            if let ips = ipRules[action] { rules.append(["type": "field", "ip": ips, "outboundTag": action.rawValue]) }
        }
        if settings.routingMode == .bypassIran {
            if hasGeoData {
                rules.append(["type": "field", "domain": ["geosite:category-ir", "domain:ir"], "outboundTag": "direct"])
                rules.append(["type": "field", "ip": ["geoip:ir"], "outboundTag": "direct"])
            } else {
                rules.append(["type": "field", "domain": ["domain:ir"], "outboundTag": "direct"])
            }
        }

        // DNS: remote (DoH) for everything, a direct resolver for Iranian domains.
        var dnsServers: [Any] = []
        if settings.routingMode == .bypassIran {
            var direct: [String: Any] = ["address": settings.directDNS, "skipFallback": true]
            direct["domains"] = hasGeoData ? ["geosite:category-ir", "domain:ir"] : ["domain:ir"]
            dnsServers.append(direct)
        }
        dnsServers.append(settings.remoteDNS)
        dnsServers.append("8.8.8.8")

        var inbounds: [[String: Any]] = [[
            "tag": "socks-in",
            "listen": settings.allowLAN ? "0.0.0.0" : "127.0.0.1",
            "port": socksPort,
            "protocol": "socks",
            "settings": ["auth": "noauth", "udp": true],
            "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": false],
        ]]
        if settings.allowLAN {
            inbounds.append([
                "tag": "http-in",
                "listen": "0.0.0.0",
                "port": settings.httpPort,
                "protocol": "http",
                "sniffing": ["enabled": true, "destOverride": ["http", "tls"]],
            ])
        }

        let config: [String: Any] = [
            "log": ["loglevel": settings.logLevel, "access": "none"],
            "dns": ["servers": dnsServers, "queryStrategy": "UseIP"],
            // Explicit, non-aggressive timeouts (Xray defaults). Some clients ship
            // connIdle 15 / uplinkOnly 1, which drops long idle connections.
            "policy": ["levels": ["0": ["connIdle": 300, "handshake": 4, "uplinkOnly": 2, "downlinkOnly": 5]]],
            "inbounds": inbounds,
            "outbounds": outbounds,
            // "linear" matcher trades CPU for memory; the default hybrid matcher
            // builds large automata for the 40k+ Iranian domains and would push the
            // extension towards the 50 MB limit.
            "routing": ["domainStrategy": "IPIfNonMatch", "domainMatcher": "linear", "rules": rules],
        ]
        let json = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: json, as: UTF8.self)
    }
}

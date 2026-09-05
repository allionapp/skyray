import Foundation

enum RoutingMode: String, Codable, CaseIterable, Identifiable {
    /// Everything except LAN/loopback goes through the proxy.
    case proxyAll
    /// Iranian domains/IPs (geosite:category-ir, geoip:ir) and LAN go direct.
    case bypassIran
    /// Absolutely everything through the proxy, including LAN.
    case global

    var id: String { rawValue }
}

enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case proxy, direct, block
    var id: String { rawValue }
}

/// A user-defined routing rule. `pattern` is an Xray domain or IP matcher such as
/// `domain:example.com`, `full:api.example.com`, `keyword:youtube`, `geosite:cn`,
/// `1.2.3.0/24`, `geoip:cn`.
struct RoutingRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var pattern: String
    var action: RuleAction = .direct
    var enabled: Bool = true

    var isIP: Bool {
        let p = pattern.lowercased()
        if p.hasPrefix("geoip:") { return true }
        let head = p.split(separator: "/").first.map(String.init) ?? p
        return head.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil || head.contains(":")
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

enum AutoConnectChoice: String, Codable, CaseIterable, Identifiable {
    case lastUsed, fastest
    var id: String { rawValue }
}

/// User settings shared with the tunnel extension via the App Group.
struct AppSettings: Codable, Equatable {
    var routingMode: RoutingMode = .proxyAll
    var blockAds: Bool = false
    var customRules: [RoutingRule] = []

    /// Ask iOS to bring the tunnel back automatically whenever it drops.
    var connectOnDemand: Bool = false
    /// Block all traffic when the tunnel is down (NE includeAllNetworks).
    var killSwitch: Bool = false
    /// Never disconnect just because the device goes to sleep.
    var keepAliveOnSleep: Bool = true
    /// Connect automatically when the app is opened.
    var autoConnectOnLaunch: Bool = false
    var autoConnectChoice: AutoConnectChoice = .lastUsed

    /// DNS used for proxied traffic (DoH recommended) and for direct/Iranian traffic.
    var remoteDNS: String = "https://1.1.1.1/dns-query"
    var directDNS: String = "8.8.8.8"
    /// DNS servers handed to iOS for the tunnel interface (plain IPs only).
    var dnsServers: [String] = ["1.1.1.1", "8.8.8.8"]

    /// Xray log level inside the extension: none, error, warning, info, debug.
    var logLevel: String = "warning"
    /// Xray mux for the proxy outbound; off by default (some servers reject it).
    var muxEnabled: Bool = false

    /// TLS ClientHello fragmentation (helps against SNI-based blocking in Iran).
    var fragmentEnabled: Bool = false
    var fragmentPackets: String = "tlshello"
    var fragmentLength: String = "100-200"
    var fragmentInterval: String = "10-20"

    /// Share the local SOCKS/HTTP proxy with other devices on the LAN.
    var allowLAN: Bool = false
    var httpPort: Int = 10809

    /// Subscriptions: refresh automatically when older than this many hours (0 = off).
    var subscriptionAutoUpdateHours: Int = 12
    /// Ping all servers automatically when the app opens.
    var pingOnOpen: Bool = false
    /// After a subscription refresh, test all servers and put the fastest first.
    var pingAfterSubscriptionUpdate: Bool = false

    var theme: AppTheme = .system
}

/// Subscription metadata from response headers (Happ/Hiddify/V2Box conventions).
struct SubscriptionInfo: Codable, Equatable, Identifiable {
    var url: String
    var title: String?
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expire: Date?
    var lastUpdated: Date
    /// `profile-update-interval` header, in hours.
    var updateIntervalHours: Int?
    /// `profile-web-page-url` header: the provider's website / panel.
    var webPageURL: String?
    /// `support-url` header: Telegram or website for support.
    var supportURL: String?
    /// `announce` header: a short message from the provider.
    var announce: String?

    var id: String { url }

    var used: Int64? {
        guard upload != nil || download != nil else { return nil }
        return (upload ?? 0) + (download ?? 0)
    }
    var remaining: Int64? {
        guard let total, let used else { return nil }
        return max(0, total - used)
    }
    var isExpired: Bool { expire.map { $0 < Date() } ?? false }
    var expiresSoon: Bool {
        guard let expire else { return false }
        return expire > Date() && expire.timeIntervalSinceNow < 3 * 24 * 3600
    }
}

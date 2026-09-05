import Foundation

enum CoreKind: String, Codable {
    /// Xray-core: VLESS, VMess, Trojan, Shadowsocks, SOCKS, Hysteria2, WireGuard.
    case xray
    /// sing-box: SSH, TUIC.
    case singbox
}

/// One proxy server. `outboundJSON` is a single outbound object for the core
/// named by `core` (an Xray outbound, or a sing-box outbound), serialized as JSON.
struct ServerProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var protocolName: String
    var address: String
    var port: Int
    var shareLink: String?
    var outboundJSON: String
    var latencyMs: Int?
    var subscriptionURL: String?
    var createdAt: Date = Date()
    var core: CoreKind = .xray

    var subtitle: String {
        "\(protocolName.uppercased()) · \(address):\(port)" + (core == .singbox ? " · sing-box" : "")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, protocolName, address, port, shareLink, outboundJSON, latencyMs, subscriptionURL, createdAt, core
    }

    init(id: UUID = UUID(), name: String, protocolName: String, address: String, port: Int,
         shareLink: String? = nil, outboundJSON: String, latencyMs: Int? = nil,
         subscriptionURL: String? = nil, createdAt: Date = Date(), core: CoreKind = .xray) {
        self.id = id; self.name = name; self.protocolName = protocolName; self.address = address; self.port = port
        self.shareLink = shareLink; self.outboundJSON = outboundJSON; self.latencyMs = latencyMs
        self.subscriptionURL = subscriptionURL; self.createdAt = createdAt; self.core = core
    }

    /// Tolerant decoding: profiles saved by older versions have no `core` field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        protocolName = try c.decodeIfPresent(String.self, forKey: .protocolName) ?? "unknown"
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 0
        shareLink = try c.decodeIfPresent(String.self, forKey: .shareLink)
        outboundJSON = try c.decode(String.self, forKey: .outboundJSON)
        latencyMs = try c.decodeIfPresent(Int.self, forKey: .latencyMs)
        subscriptionURL = try c.decodeIfPresent(String.self, forKey: .subscriptionURL)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        core = try c.decodeIfPresent(CoreKind.self, forKey: .core) ?? .xray
    }
}

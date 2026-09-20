import Foundation

/// Parses share links for protocols only sing-box provides on this app:
/// `ssh://user:password@host:port#name`, TUIC v5
/// `tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native&sni=…&alpn=h3&allow_insecure=1#name`,
/// AnyTLS `anytls://password@host:port?sni=…#name` and Hysteria v1
/// `hysteria://host:port?auth=…&upmbps=100&downmbps=100&peer=…#name`.
enum SingboxLinkParser {
    static let schemes = ["ssh://", "tuic://", "anytls://", "hysteria://"]

    static func handles(_ line: String) -> Bool {
        let lower = line.lowercased()
        return schemes.contains { lower.hasPrefix($0) }
    }

    static func parse(_ line: String) throws -> ServerProfile {
        guard let components = URLComponents(string: line.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else {
            throw XrayCoreError.invoke("Invalid link")
        }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let name = components.fragment?.removingPercentEncoding?.trimmingCharacters(in: .whitespaces)
        var outbound: [String: Any] = ["server": host]
        var protocolName = scheme
        let port: Int

        switch scheme {
        case "ssh":
            port = components.port ?? 22
            outbound["type"] = "ssh"
            outbound["server_port"] = port
            outbound["user"] = components.user?.removingPercentEncoding ?? "root"
            if let pw = components.password?.removingPercentEncoding, !pw.isEmpty { outbound["password"] = pw }
            if let pk = query["privatekey"] ?? query["private_key"] ?? query["key"], !pk.isEmpty {
                outbound["private_key"] = ShareLinkParser.decodeBase64(pk) ?? pk.removingPercentEncoding ?? pk
            }
            if let pass = query["passphrase"], !pass.isEmpty { outbound["private_key_passphrase"] = pass }
            if let hk = query["hostkey"] ?? query["host_key"], !hk.isEmpty { outbound["host_key"] = [hk] }
            protocolName = "ssh"
        case "tuic":
            port = components.port ?? 443
            outbound["type"] = "tuic"
            outbound["server_port"] = port
            outbound["uuid"] = components.user?.removingPercentEncoding ?? ""
            outbound["password"] = components.password?.removingPercentEncoding ?? ""
            outbound["congestion_control"] = query["congestion_control"] ?? query["congestion_controller"] ?? "bbr"
            outbound["udp_relay_mode"] = query["udp_relay_mode"] ?? "native"
            if ["1", "true"].contains(query["zero_rtt_handshake"] ?? "") { outbound["zero_rtt_handshake"] = true }
            var tls: [String: Any] = ["enabled": true]
            if let sni = query["sni"] ?? query["peer"], !sni.isEmpty { tls["server_name"] = sni }
            if let alpn = query["alpn"], !alpn.isEmpty { tls["alpn"] = alpn.split(separator: ",").map(String.init) }
            if ["1", "true"].contains((query["allow_insecure"] ?? query["allowinsecure"] ?? query["insecure"] ?? "").lowercased()) { tls["insecure"] = true }
            if ["1", "true"].contains(query["disable_sni"] ?? "") { tls["disable_sni"] = true }
            outbound["tls"] = tls
            protocolName = "tuic"
        case "anytls":
            port = components.port ?? 443
            outbound["type"] = "anytls"
            outbound["server_port"] = port
            // The secret sits in the userinfo, with or without a username in front of it.
            outbound["password"] = (components.password ?? components.user)?.removingPercentEncoding ?? ""
            outbound["tls"] = tlsSettings(from: query, fallbackSNI: host)
            protocolName = "anytls"
        case "hysteria":
            port = components.port ?? 443
            // sing-box speaks only the UDP transport; a link asking for faketcp
            // would connect and then fail silently, so say so while parsing.
            if let wire = query["protocol"], !wire.isEmpty, wire.lowercased() != "udp" {
                throw XrayCoreError.invoke("Hysteria over \(wire) is not supported")
            }
            outbound["type"] = "hysteria"
            outbound["server_port"] = port
            if let auth = query["auth"] ?? query["auth_str"] ?? query["authstr"], !auth.isEmpty {
                outbound["auth_str"] = auth.removingPercentEncoding ?? auth
            }
            // Hysteria v1 refuses to start without both rates, so a link that
            // leaves them out gets a usable default rather than an error.
            outbound["up_mbps"] = Int(query["upmbps"] ?? query["up_mbps"] ?? query["up"] ?? "") ?? 100
            outbound["down_mbps"] = Int(query["downmbps"] ?? query["down_mbps"] ?? query["down"] ?? "") ?? 100
            // `obfs=xplus` names the obfuscation and `obfsParam` carries its key;
            // newer links put the key in `obfs` itself.
            if let key = query["obfsparam"] ?? query["obfs_password"], !key.isEmpty {
                outbound["obfs"] = key.removingPercentEncoding ?? key
            } else if let obfs = query["obfs"], !obfs.isEmpty, obfs.lowercased() != "xplus" {
                outbound["obfs"] = obfs
            }
            outbound["tls"] = tlsSettings(from: query, fallbackSNI: host)
            protocolName = "hysteria"
        default:
            throw XrayCoreError.invoke("Unsupported scheme \(scheme)")
        }

        let data = try JSONSerialization.data(withJSONObject: outbound, options: [.sortedKeys])
        return ServerProfile(name: name?.isEmpty == false ? name! : "\(host):\(port)",
                             protocolName: protocolName, address: host, port: port, shareLink: line,
                             outboundJSON: String(decoding: data, as: UTF8.self), core: .singbox)
    }

    /// The TLS block both AnyTLS and Hysteria carry in their query string.
    private static func tlsSettings(from query: [String: String], fallbackSNI: String) -> [String: Any] {
        var tls: [String: Any] = ["enabled": true]
        let sni = query["sni"] ?? query["peer"] ?? query["host"]
        tls["server_name"] = (sni?.isEmpty == false ? sni! : fallbackSNI)
        if let alpn = query["alpn"], !alpn.isEmpty { tls["alpn"] = alpn.split(separator: ",").map(String.init) }
        if ["1", "true"].contains((query["allow_insecure"] ?? query["allowinsecure"] ?? query["insecure"] ?? "").lowercased()) {
            tls["insecure"] = true
        }
        if let fingerprint = query["fp"] ?? query["fingerprint"], !fingerprint.isEmpty {
            tls["utls"] = ["enabled": true, "fingerprint": fingerprint]
        }
        return tls
    }
}

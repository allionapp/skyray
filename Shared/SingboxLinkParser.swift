import Foundation

/// Parses share links for protocols only sing-box provides on this app:
/// `ssh://user:password@host:port#name` and TUIC v5
/// `tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native&sni=…&alpn=h3&allow_insecure=1#name`.
enum SingboxLinkParser {
    static let schemes = ["ssh://", "tuic://"]

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
        default:
            throw XrayCoreError.invoke("Unsupported scheme \(scheme)")
        }

        let data = try JSONSerialization.data(withJSONObject: outbound, options: [.sortedKeys])
        return ServerProfile(name: name?.isEmpty == false ? name! : "\(host):\(port)",
                             protocolName: protocolName, address: host, port: port, shareLink: line,
                             outboundJSON: String(decoding: data, as: UTF8.self), core: .singbox)
    }
}

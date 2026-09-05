import Foundation

/// Turns pasted text (share links, a subscription body, Clash YAML, or raw
/// Xray JSON) into `ServerProfile`s using libXray for the protocol details.
/// Pure and thread-safe: callers should run it off the main thread for large inputs.
enum ShareLinkParser {
    static let supportedSchemes = ["vmess://", "vless://", "trojan://", "ss://", "socks://", "hysteria2://", "hy2://"] + SingboxLinkParser.schemes

    struct Failure {
        let line: String
        let reason: String
    }

    struct Outcome {
        var profiles: [ServerProfile] = []
        var failures: [Failure] = []
    }

    static func parse(_ rawText: String, subscriptionURL: String? = nil) -> Outcome {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !containsShareLink(text), !text.hasPrefix("{"), !isClashYaml(text), let decoded = decodeBase64(text) {
            text = decoded
        }

        if text.hasPrefix("{") { return parseRawJSON(text) }
        if isClashYaml(text) { return parseWholeTextWithCore(text, subscriptionURL: subscriptionURL) }

        var outcome = Outcome()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in supportedSchemes.contains { line.lowercased().hasPrefix($0) } }

        for line in lines {
            if SingboxLinkParser.handles(line) {
                do {
                    var profile = try SingboxLinkParser.parse(line)
                    profile.subscriptionURL = subscriptionURL
                    outcome.profiles.append(profile)
                } catch {
                    outcome.failures.append(Failure(line: line, reason: error.localizedDescription))
                }
                continue
            }
            do {
                let outbounds = try XrayCore.parseShareLinks(line)
                guard var outbound = outbounds.first else {
                    outcome.failures.append(Failure(line: line, reason: "No outbound produced"))
                    continue
                }
                applyLinkExtras(from: line, to: &outbound)
                var profile = try makeProfile(from: outbound, fallbackName: nil)
                profile.name = displayName(for: line) ?? profile.name
                profile.shareLink = line
                profile.subscriptionURL = subscriptionURL
                outcome.profiles.append(profile)
            } catch {
                outcome.failures.append(Failure(line: line, reason: error.localizedDescription))
            }
        }
        return outcome
    }

    /// Clash YAML and other multi-server formats are handed to libXray as a whole.
    private static func parseWholeTextWithCore(_ text: String, subscriptionURL: String?) -> Outcome {
        var outcome = Outcome()
        do {
            for outbound in try XrayCore.parseShareLinks(text) {
                let name = (outbound["sendThrough"] as? String) ?? (outbound["tag"] as? String)
                var profile = try makeProfile(from: outbound, fallbackName: name)
                profile.subscriptionURL = subscriptionURL
                outcome.profiles.append(profile)
            }
        } catch {
            outcome.failures.append(Failure(line: String(text.prefix(80)), reason: error.localizedDescription))
        }
        return outcome
    }

    private static func parseRawJSON(_ text: String) -> Outcome {
        var outcome = Outcome()
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            outcome.failures.append(Failure(line: String(text.prefix(80)), reason: "Invalid JSON"))
            return outcome
        }
        let outbounds: [[String: Any]]
        if let list = object["outbounds"] as? [[String: Any]] {
            outbounds = list.filter { !["freedom", "blackhole", "dns", "loopback"].contains(($0["protocol"] as? String) ?? "") }
        } else {
            outbounds = [object]
        }
        for outbound in outbounds {
            do {
                outcome.profiles.append(try makeProfile(from: outbound, fallbackName: outbound["tag"] as? String))
            } catch {
                outcome.failures.append(Failure(line: (outbound["tag"] as? String) ?? "outbound", reason: error.localizedDescription))
            }
        }
        return outcome
    }

    /// Options the share-link converter drops but users rely on, e.g. `allowInsecure=1`.
    static func applyLinkExtras(from link: String, to outbound: inout [String: Any]) {
        guard let query = URLComponents(string: link)?.queryItems else { return }
        let flags = Dictionary(query.map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let insecure = ["1", "true"].contains((flags["allowinsecure"] ?? flags["insecure"] ?? "").lowercased())
        guard insecure else { return }
        var stream = outbound["streamSettings"] as? [String: Any] ?? [:]
        let security = (stream["security"] as? String) ?? ""
        guard security == "tls" else { return }
        var tls = stream["tlsSettings"] as? [String: Any] ?? [:]
        tls["allowInsecure"] = true
        stream["tlsSettings"] = tls
        outbound["streamSettings"] = stream
    }

    static func makeProfile(from outbound: [String: Any], fallbackName: String?) throws -> ServerProfile {
        let protocolName = (outbound["protocol"] as? String) ?? "unknown"
        let settings = outbound["settings"] as? [String: Any] ?? [:]
        var address = ""
        var port = 0
        if let a = settings["address"] as? String { address = a }
        if let p = settings["port"] as? Int { port = p } else if let p = settings["port"] as? String { port = Int(p) ?? 0 }
        if address.isEmpty {
            let list = (settings["vnext"] as? [[String: Any]]) ?? (settings["servers"] as? [[String: Any]]) ?? []
            if let first = list.first {
                address = first["address"] as? String ?? ""
                port = first["port"] as? Int ?? 0
            }
        }
        guard !address.isEmpty, port > 0 else { throw XrayCoreError.invoke("Missing server address or port") }
        var clean = outbound
        clean.removeValue(forKey: "sendThrough")
        clean.removeValue(forKey: "tag")
        let data = try JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys])
        let name = fallbackName.flatMap { $0.isEmpty || $0 == "proxy" ? nil : $0 } ?? "\(address):\(port)"
        return ServerProfile(name: name, protocolName: protocolName, address: address, port: port,
                             shareLink: nil, outboundJSON: String(decoding: data, as: UTF8.self))
    }

    /// Human-readable name: the `#fragment` of a link, or `ps` for vmess links.
    static func displayName(for link: String) -> String? {
        if let hash = link.firstIndex(of: "#") {
            let fragment = String(link[link.index(after: hash)...])
            if let name = fragment.removingPercentEncoding?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        }
        if link.lowercased().hasPrefix("vmess://") {
            let body = String(link.dropFirst("vmess://".count))
            if let json = decodeBase64(body),
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ps = dict["ps"] as? String, !ps.isEmpty {
                return ps
            }
        }
        return nil
    }

    static func containsShareLink(_ text: String) -> Bool {
        let lower = text.lowercased()
        return supportedSchemes.contains { lower.contains($0) }
    }

    static func isClashYaml(_ text: String) -> Bool {
        text.range(of: #"(?m)^proxies:\s*$"#, options: .regularExpression) != nil
            || text.range(of: #"(?m)^proxies:\s*\["#, options: .regularExpression) != nil
    }

    static func decodeBase64(_ text: String) -> String? {
        var s = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s), let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}

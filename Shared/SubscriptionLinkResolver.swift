import Foundation

/// Understands the "launcher" deep links that VPN panels hand out for other
/// clients (hiddify://import/<url>, v2box://install-sub?url=…, clash://install-config?url=…,
/// sing-box://import-remote-profile?url=…, streisand://import/<url>, happ://add/<url>,
/// sub://<base64 url>, skyray://import/<url>) and extracts the real http(s) URL.
enum SubscriptionLinkResolver {
    struct Resolved: Equatable {
        var url: String
        var title: String?
    }

    static func resolve(_ raw: String) -> Resolved? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return Resolved(url: stripFragment(text), title: fragment(of: text))
        }

        // Schemes whose payload is the URL after the host/path prefix.
        let pathPrefixes = ["hiddify://import/", "streisand://import/", "happ://add/", "skyray://import/",
                            "hiddifynext://import/", "shadowrocket://add/", "v2rayng://install-sub/"]
        for prefix in pathPrefixes where lower.hasPrefix(prefix) {
            let payload = String(text.dropFirst(prefix.count))
            return unwrap(payload)
        }

        // Schemes that carry the URL in a query parameter.
        if let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
           ["v2box", "v2rayng", "clash", "clashmeta", "clashx", "stash", "sing-box", "singbox", "nekobox", "nekoray",
            "surge", "loon", "quantumult-x", "hiddify", "skyray", "shadowrocket"].contains(scheme) {
            let items = components.queryItems ?? []
            for key in ["url", "link", "config", "sub"] {
                if let value = items.first(where: { $0.name.lowercased() == key })?.value, let r = unwrap(value) {
                    let name = items.first(where: { ["name", "title", "remark"].contains($0.name.lowercased()) })?.value
                    return Resolved(url: r.url, title: name ?? r.title ?? fragment(of: text))
                }
            }
        }

        // sub://<base64-encoded url>
        if lower.hasPrefix("sub://") {
            let payload = String(text.dropFirst("sub://".count))
            if let decoded = ShareLinkParser.decodeBase64(stripFragment(payload)) {
                guard var r = unwrap(decoded) else { return nil }
                if let title = fragment(of: payload) { r.title = title }
                return r
            }
        }
        return nil
    }

    /// The EthaVPN service's hosts: one account's link works on each of them. Oldest first:
    /// mobileiphone.org is filtered in Iran, mobileiphonez.org is the CDN-fronted domain, and
    /// skyrayconfig.org serves only the links and is where an account ends up. An account moves to
    /// an older one only when the newer does not answer, and never onto the first. Any other https
    /// link is still accepted as a plain subscription.
    static let serviceHosts = ["fra.mobileiphone.org", "fra.mobileiphonez.org", "fra.skyrayconfig.org"]

    /// The account a link of the service names: its /sub/<token> path, the same on every host.
    /// nil for any other link.
    static func serviceAccount(of link: String) -> String? {
        guard let c = URLComponents(string: stripFragment(link.trimmingCharacters(in: .whitespacesAndNewlines))),
              c.scheme?.lowercased() == "https", let host = c.host?.lowercased(), serviceHosts.contains(host),
              c.path.hasPrefix("/sub/") else { return nil }
        let token = c.path.dropFirst("/sub/".count)
        return token.count >= 8 && !token.contains("/") ? c.path : nil
    }

    /// A service link's host among `serviceHosts` (higher is newer); -1 for any other link.
    static func hostRank(of link: String) -> Int {
        guard let host = URLComponents(string: stripFragment(link.trimmingCharacters(in: .whitespacesAndNewlines)))?.host?.lowercased()
        else { return -1 }
        return serviceHosts.firstIndex(of: host) ?? -1
    }

    private static func unwrap(_ payload: String) -> Resolved? {
        var value = payload
        if let decoded = value.removingPercentEncoding, decoded.lowercased().hasPrefix("http") { value = decoded }
        let lower = value.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return Resolved(url: stripFragment(value), title: fragment(of: value))
    }

    private static func stripFragment(_ s: String) -> String {
        guard let hash = s.firstIndex(of: "#") else { return s }
        return String(s[..<hash])
    }

    private static func fragment(of s: String) -> String? {
        guard let hash = s.firstIndex(of: "#") else { return nil }
        let f = String(s[s.index(after: hash)...]).removingPercentEncoding ?? ""
        return f.isEmpty ? nil : f
    }
}

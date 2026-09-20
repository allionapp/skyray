import Foundation
import LibXray

/// What one probe found about a server; `delayMs` is -1 when it failed.
struct ProbeResult {
    let delayMs: Int
    let exitIP: String?
    let country: String?
    let error: String

    var success: Bool { delayMs >= 0 }
    static let failed = ProbeResult(delayMs: -1, exitIP: nil, country: nil, error: "")
}

/// One HTTP request through each server, run inside the app's own Go runtime:
/// reachability, delay, and where the traffic comes out, in a single round trip.
enum CoreProbe {
    /// Tests up to `AppConstants.pingBatchSize` servers of either core in one
    /// call; results come back in the same order as `profiles`.
    static func probe(_ profiles: [ServerProfile],
                      timeoutSeconds: Int = AppConstants.pingTimeoutSeconds) -> [ProbeResult] {
        let items: [[String: Any]] = profiles.compactMap { p in
            guard let d = p.outboundJSON.data(using: .utf8),
                  let ob = try? JSONSerialization.jsonObject(with: d) else { return nil }
            return ["core": p.core == .singbox ? "singbox" : "xray", "outbound": ob]
        }
        guard items.count == profiles.count,
              let payload = try? JSONSerialization.data(withJSONObject: items) else {
            return profiles.map { _ in ProbeResult.failed }
        }
        var error: NSError?
        let reply = RaycoreProbeBatch(String(decoding: payload, as: UTF8.self), AppConstants.probeURL, timeoutSeconds * 1000, &error)
        guard error == nil, let data = reply.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return profiles.map { _ in ProbeResult.failed }
        }
        return profiles.indices.map { i in
            guard i < results.count else { return ProbeResult.failed }
            let r = results[i]
            return ProbeResult(delayMs: (r["delay"] as? Int) ?? -1,
                               exitIP: r["ip"] as? String, country: r["country"] as? String,
                               error: (r["error"] as? String) ?? "")
        }
    }
}

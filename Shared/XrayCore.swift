import Foundation
import LibXray

enum XrayCoreError: LocalizedError {
    case invoke(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invoke(let message): return message
        case .badResponse: return "Unexpected response from Xray core"
        }
    }
}

struct PingResult {
    let success: Bool
    let delayMs: Int
    let error: String
}

/// Thin Swift wrapper over libXray's JSON `Invoke` API.
enum XrayCore {
    private static let apiVersion = 2

    @discardableResult
    static func invoke(_ method: String, payload: [String: Any] = [:]) throws -> Any? {
        var request: [String: Any] = ["apiVersion": apiVersion, "method": method]
        if !payload.isEmpty { request["payload"] = payload }
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else { throw XrayCoreError.badResponse }

        let responseJSON = LibXrayInvoke(requestJSON)
        guard let responseData = responseJSON.data(using: .utf8),
              let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else { throw XrayCoreError.badResponse }

        if response["success"] as? Bool == true {
            return response["data"]
        }
        throw XrayCoreError.invoke((response["error"] as? String) ?? "unknown error")
    }

    static func version() -> String {
        let data = try? invoke("xrayVersion") as? [String: Any]
        return data?["version"] as? String ?? "unknown"
    }

    /// Converts one or more share links (vmess://, vless://, trojan://, ss://,
    /// socks://, hysteria2://) into Xray outbound objects.
    static func parseShareLinks(_ text: String) throws -> [[String: Any]] {
        let data = try invoke("convertShareLinksToXrayJson", payload: ["text": text]) as? [String: Any]
        return data?["outbounds"] as? [[String: Any]] ?? []
    }

    static func testConfig(_ configJSON: String) throws {
        try invoke("testXray", payload: ["xrayJson": configJSON])
    }

    static func run(_ configJSON: String) throws {
        try invoke("runXray", payload: ["xrayJson": configJSON])
    }

    static func stop() throws {
        try invoke("stopXray")
    }

    static func isRunning() -> Bool {
        let data = try? invoke("getXrayState") as? [String: Any]
        return data?["running"] as? Bool ?? false
    }

    /// Measures real HTTP latency through each outbound. libXray accepts at most
    /// five configs per call, so callers should batch accordingly.
    static func ping(outbounds: [[String: Any]],
                     timeoutSeconds: Int = AppConstants.pingTimeoutSeconds,
                     url: String = AppConstants.pingURL) throws -> [PingResult] {
        var configs: [[String: Any]] = []
        for outbound in outbounds {
            var tagged = outbound
            tagged["tag"] = "proxy"
            let json = try JSONSerialization.data(withJSONObject: ["outbounds": [tagged]])
            configs.append(["xrayJson": String(decoding: json, as: UTF8.self), "outboundTag": "proxy"])
        }
        let data = try invoke("pingBatch", payload: ["configs": configs, "timeout": timeoutSeconds, "url": url]) as? [String: Any]
        let results = data?["results"] as? [[String: Any]] ?? []
        return results.map {
            PingResult(success: $0["success"] as? Bool ?? false,
                       delayMs: $0["delay"] as? Int ?? -1,
                       error: $0["error"] as? String ?? "")
        }
    }
}

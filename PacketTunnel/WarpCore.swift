import Foundation
import Aether

/// Cloudflare WARP, run by the Aether core (AGPL-3.0, CluvexStudio/Aether).
///
/// On Android the core is a child process; iOS allows no such thing inside a
/// Network Extension, so the same core is linked in as a static library and
/// driven through its C API. It still ends up where Xray and sing-box do: a
/// local SOCKS5 proxy for hev-socks5-tunnel to dial.
enum WarpCore {
    /// One attempt: a name for the log and the flags that pick the transport.
    /// The order is what a filtered network in Iran actually allows — MASQUE
    /// over HTTP/2 passes for ordinary HTTPS, QUIC is dropped, and plain
    /// WireGuard is throttled to a crawl.
    private static let transports: [(String, [String])] = [
        ("masque-h2", ["--masque", "--h2"]),
        ("warp-in-warp", ["--gool"]),
        ("wireguard", ["--wg"]),
    ]

    private static let perTransportTimeout: TimeInterval = 90
    private static var job: UInt64?

    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    static var version: String {
        guard let raw = aether_version() else { return "unknown" }
        defer { aether_string_free(raw) }
        return String(cString: raw)
    }

    /// Brings WARP up and returns the transport that worked, or throws.
    @discardableResult
    static func start(port: Int, configDirectory: URL) throws -> String {
        stop()
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        var lastReason = "WARP could not connect"

        for (label, flags) in transports {
            TunnelLog.write("[warp] trying \(label)")
            let arguments = flags + [
                "-4", "--scan", "turbo",
                "--bind", "127.0.0.1:\(port)",
                "--config", configDirectory.appendingPathComponent("aether.toml").path,
            ]
            guard let started = call({ aether_core_start($0) }, arguments) else {
                lastReason = "the WARP core would not start"
                continue
            }
            guard let id = (started["data"] as? [String: Any])?["job"] as? UInt64
                ?? ((started["data"] as? [String: Any])?["job"] as? NSNumber)?.uint64Value else {
                lastReason = "the WARP core did not report a job"
                continue
            }
            job = id
            if waitForProxy(port: port, job: id) {
                TunnelLog.write("[warp] connected over \(label)")
                return label
            }
            lastReason = "\(label) did not connect"
            stop()
        }
        throw Failure(reason: lastReason)
    }

    static func stop() {
        guard let id = job else { return }
        job = nil
        _ = call({ _ in aether_job_cancel(id) }, nil)
        _ = call({ _ in aether_job_free(id) }, nil)
    }

    /// The core has no callback for "the proxy is up", so the port answers for
    /// it: it only accepts once the tunnel has carried real data.
    private static func waitForProxy(port: Int, job id: UInt64) -> Bool {
        let deadline = Date().addingTimeInterval(perTransportTimeout)
        while Date() < deadline {
            if let state = pollState(job: id), state != "running" {
                TunnelLog.write("[warp] core stopped: \(state)")
                return false
            }
            if canConnect(port: port) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private static func pollState(job id: UInt64) -> String? {
        guard let response = call({ _ in aether_job_poll(id) }, nil) else { return nil }
        if let error = response["error"] as? String {
            TunnelLog.write("[warp] \(error)")
            return "failed"
        }
        return (response["data"] as? [String: Any])?["state"] as? String
    }

    private static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        return connected
    }

    /// Every entry point takes an optional JSON argument and returns a JSON
    /// string this owns and must free.
    private static func call(_ entry: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?, _ arguments: [String]?) -> [String: Any]? {
        var raw: UnsafeMutablePointer<CChar>?
        if let arguments, let payload = try? JSONSerialization.data(withJSONObject: arguments),
           let text = String(data: payload, encoding: .utf8) {
            raw = text.withCString { entry($0) }
        } else {
            raw = entry(nil)
        }
        guard let raw else { return nil }
        defer { aether_string_free(raw) }
        let text = String(cString: raw)
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}

import Foundation
import Network

/// Measures the TCP handshake time to a host:port. Works with or without the VPN.
enum TCPPing {
    static func measure(host: String, port: Int, timeout: TimeInterval = 5) async -> Int {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return -1 }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let started = Date()
            var finished = false
            let finish: (Int) -> Void = { ms in
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: ms)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(Int(Date().timeIntervalSince(started) * 1000))
                case .failed, .cancelled: finish(-1)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(-1) }
        }
    }
}

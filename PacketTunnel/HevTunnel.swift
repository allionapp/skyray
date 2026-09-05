import Foundation
import HevSocks5Tunnel

/// Runs hev-socks5-tunnel, which reads IP packets from the utun device and
/// forwards them to Xray's local SOCKS5 inbound.
final class HevTunnel {
    static let tunnelAddress = "198.18.0.1"
    static let tunnelAddressV6 = "fd00:ffff::1"
    static let mtu = 1500

    private var thread: Thread?

    struct Stats {
        let txPackets: Int, txBytes: Int, rxPackets: Int, rxBytes: Int
    }

    func start(tunFD: Int32, socksPort: Int, completion: @escaping (Int32) -> Void) {
        let yaml = """
        tunnel:
          mtu: \(Self.mtu)
          ipv4: \(Self.tunnelAddress)
          ipv6: '\(Self.tunnelAddressV6)'
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 86016
          tcp-buffer-size: 65536
          max-session-count: 512
          connect-timeout: 5000
          tcp-read-write-timeout: 300000
          udp-read-write-timeout: 60000
          limit-nofile: 65535
          log-level: warn
        """
        let thread = Thread {
            var bytes = Array(yaml.utf8)
            let result = bytes.withUnsafeMutableBufferPointer { buffer -> Int32 in
                hev_socks5_tunnel_main_from_str(buffer.baseAddress, UInt32(buffer.count), tunFD)
            }
            completion(result)
        }
        thread.name = "hev-socks5-tunnel"
        thread.stackSize = 4 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    func stop() {
        hev_socks5_tunnel_quit()
        thread = nil
    }

    func stats() -> Stats {
        var tp = 0, tb = 0, rp = 0, rb = 0
        hev_socks5_tunnel_stats(&tp, &tb, &rp, &rb)
        return Stats(txPackets: tp, txBytes: tb, rxPackets: rp, rxBytes: rb)
    }
}

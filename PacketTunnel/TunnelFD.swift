import Foundation
import NetworkExtension

/// Locates the utun file descriptor that the system created for this
/// packet tunnel so it can be handed to hev-socks5-tunnel.
enum TunnelFD {
    private static let SYSPROTO_CONTROL: Int32 = 2
    private static let UTUN_OPT_IFNAME: Int32 = 2

    static func find(in provider: NEPacketTunnelProvider) -> Int32? {
        if let fd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, fd >= 0 {
            return fd
        }
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
        for fd: Int32 in 0..<1024 {
            var length = socklen_t(name.count)
            if getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &name, &length) == 0,
               String(cString: name).hasPrefix("utun") {
                return fd
            }
        }
        return nil
    }
}

import Foundation

/// Values shared between the app and the packet tunnel extension.
enum AppConstants {
    static let appGroup = "group.com.allion.skyray"
    static let tunnelBundleId = "com.allion.skyray.PacketTunnel"
    static let vpnDisplayName = "SkyRay"

    /// Local SOCKS5 inbound that Xray opens inside the tunnel extension.
    static let socksPort = 10808

    static let profilesFile = "profiles.json"
    static let profilesBackupFile = "profiles.backup.json"
    /// Only the selected profile, written by the app for the extension so the
    /// extension never has to parse a large server list (memory is scarce there).
    static let activeProfileFile = "active-profile.json"
    static let settingsFile = "settings.json"
    static let subscriptionsInfoFile = "subscriptions.json"
    static let tunnelLogFile = "tunnel.log"
    static let selectedProfileKey = "selectedProfileId"

    static let pingURL = "https://www.google.com/generate_204"
    /// Plain-HTTP probe used for sing-box outbounds (cheaper, no TLS on top of the tunnel).
    static let pingURLPlain = "http://cp.cloudflare.com/generate_204"
    static let pingTimeoutSeconds = 8
    /// libXray accepts at most five configs per pingBatch call.
    static let pingBatchSize = 5
    static let pingConcurrentBatches = 3

    /// iOS kills a packet tunnel extension at ~50 MB; we warn well before that.
    static let extensionMemoryWarningBytes = 40 * 1024 * 1024
}

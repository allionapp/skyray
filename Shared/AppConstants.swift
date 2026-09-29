import Foundation

/// Values shared between the app and the packet tunnel extension.
enum AppConstants {
    static let appGroup = "group.com.allion.skyray"
    static let tunnelBundleId = "com.allion.skyray.PacketTunnel"
    static let vpnDisplayName = "SkyRay"

    /// Local SOCKS5 inbound that Xray opens inside the tunnel extension.
    static let socksPort = 10808

    /// Aether's own SOCKS5 port, kept apart from the Xray/sing-box one.
    static let warpSocksPort = 10819

    static let profilesFile = "profiles.json"
    static let profilesBackupFile = "profiles.backup.json"
    /// Only the selected profile, written by the app for the extension so the
    /// extension never has to parse a large server list (memory is scarce there).
    static let activeProfileFile = "active-profile.json"
    static let settingsFile = "settings.json"
    static let subscriptionsInfoFile = "subscriptions.json"
    static let tunnelLogFile = "tunnel.log"
    static let selectedProfileKey = "selectedProfileId"
    static let automaticSelectionKey = "automaticSelection"

    static let privacyPolicyURL = "https://allionapp.github.io/skyray-site/privacy.html"
    /// SkyRay on the App Store: Settings' "Check for update" opens it.
    static let appStoreURL = "itms-apps://apps.apple.com/app/id6809038308"
    static let supportURL = "https://allionapp.github.io/skyray-site/support.html"
    static let termsURL = "https://allionapp.github.io/skyray-site/terms.html"
    /// Support, as in the Android build, when a subscription names no support address of its own.
    static let supportBotURL = "https://t.me/Ethaconfigbot?start=app_support"

    /// Cloudflare's trace answers with the exit IP and country in two plain
    /// lines, so one request measures the delay and names the exit at once.
    static let probeURL = "https://www.cloudflare.com/cdn-cgi/trace"
    static let pingTimeoutSeconds = 8
    /// Servers probed per core instance; the Go side runs them concurrently.
    static let pingBatchSize = 5
    static let pingConcurrentBatches = 3

    /// iOS kills a packet tunnel extension at ~50 MB; we warn well before that.
    static let extensionMemoryWarningBytes = 40 * 1024 * 1024
}

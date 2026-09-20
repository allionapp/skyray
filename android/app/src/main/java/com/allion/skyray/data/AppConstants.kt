package com.allion.skyray.data

/** Values shared across the app and the VPN service (same process on Android). */
object AppConstants {
    const val VPN_DISPLAY_NAME = "SkyRay"
    /** Local SOCKS5 inbound that Xray/sing-box opens for hev-socks5-tunnel. */
    const val SOCKS_PORT = 10808

    const val PROFILES_FILE = "profiles.json"
    const val PROFILES_BACKUP_FILE = "profiles.backup.json"
    const val SETTINGS_FILE = "settings.json"
    const val SUBSCRIPTIONS_FILE = "subscriptions.json"
    const val TUNNEL_LOG_FILE = "tunnel.log"

    const val PRIVACY_POLICY_URL = "https://allionapp.github.io/skyray-site/privacy.html"
    const val SUPPORT_URL = "https://allionapp.github.io/skyray-site/support.html"
    const val TERMS_URL = "https://allionapp.github.io/skyray-site/terms.html"

    /** Aether's own SOCKS5 port, kept apart from the Xray/sing-box one. */
    const val WARP_SOCKS_PORT = 10819

    /**
     * Cloudflare's trace answers with the exit IP and country in two plain
     * lines, so one request measures the delay and names the exit at once.
     */
    const val PROBE_URL = "https://www.cloudflare.com/cdn-cgi/trace"
    const val PING_TIMEOUT_SECONDS = 8
    /** Servers probed per core instance; the Go side runs them concurrently. */
    const val PING_BATCH_SIZE = 5

    const val VPN_ACTION_CONNECT = "com.allion.skyray.CONNECT"
    const val VPN_ACTION_DISCONNECT = "com.allion.skyray.DISCONNECT"
    const val EXTRA_OUTBOUND_JSON = "outbound_json"
    const val EXTRA_CORE = "core"
}

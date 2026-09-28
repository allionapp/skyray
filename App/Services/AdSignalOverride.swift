import Foundation

/// Makes the language, region and time zone that Google's SDKs read from this
/// process match the tunnel exit while connected, so an AdMob or UMP request —
/// which on iOS rides the tunnel (see VPNManager.fetchExitInfo) — does not also
/// carry `fa`/`IR`/`Asia/Tehran` in its payload from behind a foreign exit.
///
/// # What it does and does not do
///
/// On iOS the exit IP already places the request at the exit node; this only
/// removes the remaining *payload* signals (`hl` language, region, time zone)
/// that would otherwise still say Iran. It reads the exit country from the
/// Cloudflare probe (`VPNManager.exitInfo`); an unknown exit becomes neutral
/// `en`/`Etc/UTC`, never the device's real `fa`/Tehran.
///
/// `u_tz` in the ad request is collected by the SDK's own WebView from the
/// system time zone, which an app cannot change; `NSTimeZone` is still set here
/// for any other reader and does no harm. (Ehsan is handling `u_tz` separately.)
///
/// # Why it persists, and how a kill is made safe
///
/// `AppleLanguages`/`AppleLocale` are the only lever iOS gives an app over what
/// `NSLocale` reports, and they live in `UserDefaults`, which persists. The
/// override is only correct while a tunnel carries the traffic, and the tunnel
/// is never up at a cold start, so the app's own prior values are captured and
/// restored on disconnect, and `clearStaleOverrideAtLaunch()` puts them back at
/// the next launch if a kill left the override on. The app uses the device
/// language for its own UI, and writing these keys at runtime does not flip the
/// running UI, so the override is invisible to the user.
enum AdSignalOverride {

    /// The device's real default time zone, captured on the first apply. In
    /// memory only: a kill resets the process default to the system zone itself.
    private static var savedTimeZone: TimeZone?
    private static var active = false

    private static let appleLanguagesKey = "AppleLanguages"
    private static let appleLocaleKey = "AppleLocale"
    private static let savedLanguagesKey = "skyray_ad_signal_saved_languages"
    private static let savedLocaleKey = "skyray_ad_signal_saved_locale"
    private static let markerKey = "skyray_ad_signal_active"

    /// exit country code -> (language, IANA time zone). Unknown -> neutral en/UTC.
    private static func geo(for country: String?) -> (language: String, timeZone: String) {
        guard let cc = country?.uppercased(), !cc.isEmpty else { return ("en", "Etc/UTC") }
        return table[cc] ?? ("en", "Etc/UTC")
    }

    private static let table: [String: (String, String)] = [
        "US": ("en", "America/New_York"), "NL": ("nl", "Europe/Amsterdam"),
        "DE": ("de", "Europe/Berlin"), "GB": ("en", "Europe/London"),
        "FR": ("fr", "Europe/Paris"), "CA": ("en", "America/Toronto"),
        "SE": ("sv", "Europe/Stockholm"), "FI": ("fi", "Europe/Helsinki"),
        "NO": ("no", "Europe/Oslo"), "DK": ("da", "Europe/Copenhagen"),
        "CH": ("de", "Europe/Zurich"), "AT": ("de", "Europe/Vienna"),
        "PL": ("pl", "Europe/Warsaw"), "IE": ("en", "Europe/Dublin"),
        "ES": ("es", "Europe/Madrid"), "IT": ("it", "Europe/Rome"),
        "SG": ("en", "Asia/Singapore"), "JP": ("ja", "Asia/Tokyo"),
        "AE": ("en", "Asia/Dubai"), "TR": ("tr", "Europe/Istanbul"),
    ]

    /// Point the process at [country]'s language, region and time zone. Safe to
    /// call repeatedly — call it before the first ad request leaves over the
    /// tunnel, and again to refine once the exit country becomes known.
    static func apply(country: String?) {
        let defaults = UserDefaults.standard
        if !active {
            savedTimeZone = NSTimeZone.default
            // Capture the app's *own* prior values (nil unless the user set a
            // per-app language), from the app domain, so restore never freezes
            // the inherited device list.
            let ownDomain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            if let ownLanguages = ownDomain?[appleLanguagesKey] { defaults.set(ownLanguages, forKey: savedLanguagesKey) }
            if let ownLocale = ownDomain?[appleLocaleKey] { defaults.set(ownLocale, forKey: savedLocaleKey) }
            defaults.set(true, forKey: markerKey)
            active = true
        }
        let g = geo(for: country)
        if let tz = TimeZone(identifier: g.timeZone) { NSTimeZone.default = tz }
        defaults.set([g.language], forKey: appleLanguagesKey)
        let cc = country?.uppercased() ?? ""
        defaults.set(cc.isEmpty ? g.language : "\(g.language)_\(cc)", forKey: appleLocaleKey)
    }

    /// Put the device's real time zone and locale back. No-op when inactive.
    static func restore() {
        guard active else { return }
        if let tz = savedTimeZone { NSTimeZone.default = tz }
        restoreSaved()
        savedTimeZone = nil
        active = false
    }

    /// Call at launch, before the UI reads the locale: if a kill left the
    /// override on, put the real values back (the tunnel is never up at a cold
    /// start, so a marker still set means the previous run was killed with it on).
    static func clearStaleOverrideAtLaunch() {
        guard UserDefaults.standard.bool(forKey: markerKey) else { return }
        restoreSaved()
    }

    private static func restoreSaved() {
        let defaults = UserDefaults.standard
        if let languages = defaults.object(forKey: savedLanguagesKey) { defaults.set(languages, forKey: appleLanguagesKey) }
        else { defaults.removeObject(forKey: appleLanguagesKey) }
        if let locale = defaults.object(forKey: savedLocaleKey) { defaults.set(locale, forKey: appleLocaleKey) }
        else { defaults.removeObject(forKey: appleLocaleKey) }
        defaults.removeObject(forKey: savedLanguagesKey)
        defaults.removeObject(forKey: savedLocaleKey)
        defaults.removeObject(forKey: markerKey)
    }
}

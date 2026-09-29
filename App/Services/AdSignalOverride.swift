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
    /// The exit country last applied, so the values can be put back if something resets them.
    private static var currentCountry: String?

    private static let appleLanguagesKey = "AppleLanguages"
    private static let appleLocaleKey = "AppleLocale"
    private static let savedLanguagesKey = "skyray_ad_signal_saved_languages"
    private static let savedLocaleKey = "skyray_ad_signal_saved_locale"
    private static let markerKey = "skyray_ad_signal_active"
    private static let appliedLanguagesKey = "skyray_ad_signal_applied_languages"

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
    /// Right before an ad request: something in the process (seen on a device after an ad was
    /// shown) can put the device's own language list back; the exit's values go back first.
    static func reassert() {
        guard active else { return }
        apply(country: currentCountry)
    }

    static func apply(country: String?) {
        currentCountry = country
        let defaults = UserDefaults.standard
        if !active {
            // A previous run killed while connected (iOS does this to background apps, and the
            // tunnel outlives them) left its override in place, and this can run before the
            // launch-time cleanup. Undo it first, or it would be saved as the app's "own" values
            // and never go away.
            if defaults.bool(forKey: markerKey) { restoreSaved() }
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
        defaults.set([g.language], forKey: appliedLanguagesKey)
        let cc = country?.uppercased() ?? ""
        defaults.set(cc.isEmpty ? g.language : "\(g.language)_\(cc)", forKey: appleLocaleKey)
        ProfileStore.shared.appendTunnelLine("[ads] signals for exit \(cc.isEmpty ? "unknown" : cc): \(snapshot())")
    }

    /// A single language the override itself uses (or last applied), with a locale that is
    /// that language or its "_CC" form: what the override writes, not what a person picks.
    private static func looksLikeOverride(languages: Any?, locale: Any?) -> Bool {
        guard let list = languages as? [String], list.count == 1, let language = list.first else { return false }
        let applied = (UserDefaults.standard.array(forKey: appliedLanguagesKey) as? [String])?.first
        let ownLanguages = Set(table.values.map(\.0) + ["en"])
        guard language == applied || ownLanguages.contains(language) else { return false }
        guard let locale = locale as? String else { return true }
        return locale == language || locale.hasPrefix(language + "_")
    }

    /// What Google's SDKs can read from this process right now, for the log: the preferred
    /// languages (hl), the current locale and region (gl), the process time zone and the
    /// system one (u_tz comes from the latter, via the SDK's own WebView).
    static func snapshot() -> String {
        let languages = Locale.preferredLanguages.prefix(2).joined(separator: ",")
        let current = Locale.current
        let fresh = Locale.autoupdatingCurrent
        return "languages=\(languages) locale=\(current.identifier) autoupdating=\(fresh.identifier) "
            + "region=\(current.regionCode ?? "-") tz=\(TimeZone.current.identifier) "
            + "default-tz=\(NSTimeZone.default.identifier) system-tz=\(NSTimeZone.system.identifier)"
    }

    /// Put the device's real time zone and locale back. No-op when inactive.
    static func restore() {
        guard active else { return }
        ProfileStore.shared.appendTunnelLine("[ads] signals restored to the device's")
        if let tz = savedTimeZone { NSTimeZone.default = tz }
        restoreSaved()
        savedTimeZone = nil
        currentCountry = nil
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
        let savedLanguages = defaults.object(forKey: savedLanguagesKey)
        let savedLocale = defaults.object(forKey: savedLocaleKey)
        // Values an earlier version saved from its own override are not the app's; drop them.
        let ours = looksLikeOverride(languages: savedLanguages, locale: savedLocale)
        if let languages = savedLanguages, !ours { defaults.set(languages, forKey: appleLanguagesKey) }
        else { defaults.removeObject(forKey: appleLanguagesKey) }
        if let locale = savedLocale, !ours { defaults.set(locale, forKey: appleLocaleKey) }
        else { defaults.removeObject(forKey: appleLocaleKey) }
        defaults.removeObject(forKey: appliedLanguagesKey)
        defaults.removeObject(forKey: savedLanguagesKey)
        defaults.removeObject(forKey: savedLocaleKey)
        defaults.removeObject(forKey: markerKey)
    }
}

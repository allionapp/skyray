package com.allion.skyray.core

import android.util.Log
import java.util.Locale
import java.util.TimeZone

/**
 * Makes this process report the tunnel exit's country and language to Google's
 * SDKs while the tunnel is up, so an AdMob or UMP request does not carry
 * `fa`/`IR`/`Asia/Tehran` in its payload from behind a foreign exit.
 *
 * # When this is applied
 *
 * Only when the app's own traffic actually rides the tunnel — i.e. an `xray`
 * connection, where the core protects its own sockets and
 * `SkyRayVpnService` no longer excludes the app from the VPN. Then the ad
 * request's IP is the exit's, and matching the locale to it is consistent. On
 * `singbox`/WARP the app is still excluded (its ad traffic uses the real
 * network), so this is NOT applied there: faking the locale while the IP stays
 * Iranian would be an inconsistency, not a disguise.
 *
 * # What it changes, and does not
 *
 * It sets only the JVM default time zone and locale, which is what the native
 * SDKs read from the process. It does not touch the phone's clock, the system
 * time zone, or the app's own UI language (Compose resolves that from the
 * resource `Configuration`, not `Locale.getDefault()`). The originals are
 * captured on the first apply and put back on [restore]; the defaults are
 * in-memory only, so a killed process comes back to the device's own values by
 * itself — no persistence, and nothing to undo at the next launch.
 *
 * `u_tz` in the ad request is read by the SDK from the system time zone in its
 * own WebView, which a normal app cannot change; the time zone is set here for
 * other readers and does no harm. (Ehsan is handling `u_tz` separately.)
 *
 * Nothing here fakes identity that is not location: the advertising id, the
 * account signal and the device model are not touched.
 */
object AdSignalOverride {
    private const val TAG = "SkyRayAdSignal"

    private var savedTz: TimeZone? = null
    private var savedLocale: Locale? = null
    private var active = false

    /** exit country code -> (language, IANA time zone). Unknown -> neutral en/UTC. */
    private fun geo(country: String?): Pair<String, String> {
        val cc = country?.uppercase()?.takeIf { it.isNotEmpty() } ?: return "en" to "Etc/UTC"
        return table[cc] ?: ("en" to "Etc/UTC")
    }

    private val table: Map<String, Pair<String, String>> = mapOf(
        "US" to ("en" to "America/New_York"), "NL" to ("nl" to "Europe/Amsterdam"),
        "DE" to ("de" to "Europe/Berlin"), "GB" to ("en" to "Europe/London"),
        "FR" to ("fr" to "Europe/Paris"), "CA" to ("en" to "America/Toronto"),
        "SE" to ("sv" to "Europe/Stockholm"), "FI" to ("fi" to "Europe/Helsinki"),
        "NO" to ("no" to "Europe/Oslo"), "DK" to ("da" to "Europe/Copenhagen"),
        "CH" to ("de" to "Europe/Zurich"), "AT" to ("de" to "Europe/Vienna"),
        "PL" to ("pl" to "Europe/Warsaw"), "IE" to ("en" to "Europe/Dublin"),
        "ES" to ("es" to "Europe/Madrid"), "IT" to ("it" to "Europe/Rome"),
        "SG" to ("en" to "Asia/Singapore"), "JP" to ("ja" to "Asia/Tokyo"),
        "AE" to ("en" to "Asia/Dubai"), "TR" to ("tr" to "Europe/Istanbul"),
    )

    /**
     * Point the process at [country]'s language and time zone. Safe to call
     * repeatedly — call it before the first ad request leaves over the tunnel,
     * and again to refine once the exit country is known. Never Iran: an unknown
     * exit becomes en/UTC.
     */
    @Synchronized
    fun apply(country: String?) {
        if (!active) {
            savedTz = TimeZone.getDefault()
            savedLocale = Locale.getDefault()
            active = true
        }
        try {
            val (language, timeZoneId) = geo(country)
            TimeZone.setDefault(TimeZone.getTimeZone(timeZoneId))
            val cc = country?.uppercase() ?: ""
            Locale.setDefault(if (cc.isEmpty()) Locale(language) else Locale(language, cc))
            Log.i(TAG, "apply country=$country -> lang=$language tz=$timeZoneId")
        } catch (t: Throwable) {
            Log.w(TAG, "apply failed", t)
        }
    }

    /** Put the device's real time zone and locale back. No-op when inactive. */
    @Synchronized
    fun restore() {
        if (!active) return
        try {
            savedTz?.let { TimeZone.setDefault(it) }
            savedLocale?.let { Locale.setDefault(it) }
            Log.i(TAG, "restore")
        } catch (t: Throwable) {
            Log.w(TAG, "restore failed", t)
        } finally {
            active = false
            savedTz = null
            savedLocale = null
        }
    }
}

package com.allion.skyray.data

import android.content.Context
import org.json.JSONArray
import java.io.File

/**
 * Persists profiles and settings as JSON files in the app's private storage.
 * Unlike iOS (separate app + extension processes needing an App Group), the
 * Android VPN service runs in the same process, so a single file store works
 * for both the UI and the tunnel.
 */
class ProfileStore private constructor(context: Context) {
    private val dir: File = context.filesDir
    /** Kept apart from settings.json: the settings screen writes back its own
     * copy of AppSettings, which would undo a selection made meanwhile. */
    private val selection = context.getSharedPreferences("selection", Context.MODE_PRIVATE)

    var selectedProfileId: String?
        get() = selection.getString("selectedProfileId", null) ?: loadSettings().selectedProfileId
        set(value) = selection.edit().putString("selectedProfileId", value).apply()

    /** Absent means automatic, the default for new and existing users alike. */
    var automaticSelection: Boolean
        get() = selection.getBoolean("automaticSelection", true)
        set(value) = selection.edit().putBoolean("automaticSelection", value).apply()

    private fun file(name: String) = File(dir, name)

    fun loadProfiles(): List<ServerProfile> {
        decodeProfiles(file(AppConstants.PROFILES_FILE))?.let { return it }
        decodeProfiles(file(AppConstants.PROFILES_BACKUP_FILE))?.let { return it }
        return emptyList()
    }

    private fun decodeProfiles(f: File): List<ServerProfile>? {
        if (!f.exists()) return null
        return runCatching {
            val arr = JSONArray(f.readText())
            (0 until arr.length()).mapNotNull { ServerProfile.fromJson(arr.getJSONObject(it)) }
        }.getOrNull()
    }

    fun saveProfiles(profiles: List<ServerProfile>) {
        val main = file(AppConstants.PROFILES_FILE)
        val backup = file(AppConstants.PROFILES_BACKUP_FILE)
        if (main.exists()) main.copyTo(backup, overwrite = true)
        val arr = JSONArray(profiles.map { it.toJson() })
        main.writeText(arr.toString())
    }

    fun loadSettings(): AppSettings {
        val f = file(AppConstants.SETTINGS_FILE)
        if (!f.exists()) return AppSettings()
        return runCatching { AppSettings.fromJson(org.json.JSONObject(f.readText())) }.getOrDefault(AppSettings())
    }

    fun saveSettings(settings: AppSettings) {
        file(AppConstants.SETTINGS_FILE).writeText(settings.toJson().toString())
    }

    fun loadSubscriptions(): List<SubscriptionInfo> {
        val f = file(AppConstants.SUBSCRIPTIONS_FILE)
        if (!f.exists()) return emptyList()
        return runCatching {
            val arr = JSONArray(f.readText())
            (0 until arr.length()).map { SubscriptionInfo.fromJson(arr.getJSONObject(it)) }
        }.getOrDefault(emptyList())
    }

    fun saveSubscriptions(list: List<SubscriptionInfo>) {
        file(AppConstants.SUBSCRIPTIONS_FILE).writeText(JSONArray(list.map { it.toJson() }).toString())
    }

    fun appendTunnelLog(line: String) {
        runCatching {
            val f = file(AppConstants.TUNNEL_LOG_FILE)
            f.appendText("${java.time.Instant.now()} $line\n")
            // Keep the log from growing without bound.
            val text = f.readText()
            if (text.length > 200_000) f.writeText(text.takeLast(150_000))
        }
    }

    fun readTunnelLog(): String = runCatching { file(AppConstants.TUNNEL_LOG_FILE).readText() }.getOrDefault("")

    companion object {
        @Volatile private var instance: ProfileStore? = null
        fun get(context: Context): ProfileStore =
            instance ?: synchronized(this) {
                instance ?: ProfileStore(context.applicationContext).also { instance = it }
            }
    }
}

package com.allion.skyray.data

import org.json.JSONObject

enum class RoutingMode { proxyAll, bypassIran, global }
enum class RuleAction { proxy, direct, block }
enum class AppTheme { system, light, dark }
enum class AutoConnectChoice { lastUsed, fastest }

data class RoutingRule(
    val id: String = java.util.UUID.randomUUID().toString(),
    var pattern: String,
    var action: RuleAction = RuleAction.direct,
    var enabled: Boolean = true,
) {
    val isIP: Boolean
        get() {
            val p = pattern.lowercase()
            if (p.startsWith("geoip:")) return true
            val head = p.substringBefore("/")
            return head.matches(Regex("^[0-9.]+$")) || head.contains(":")
        }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("pattern", pattern); put("action", action.name); put("enabled", enabled)
    }

    companion object {
        fun fromJson(o: JSONObject): RoutingRule = RoutingRule(
            id = o.optString("id", java.util.UUID.randomUUID().toString()),
            pattern = o.optString("pattern"),
            action = runCatching { RuleAction.valueOf(o.optString("action", "direct")) }.getOrDefault(RuleAction.direct),
            enabled = o.optBoolean("enabled", true),
        )
    }
}

/** User settings, persisted as JSON in the app's private storage. */
data class AppSettings(
    var routingMode: RoutingMode = RoutingMode.proxyAll,
    var blockAds: Boolean = false,
    var customRules: MutableList<RoutingRule> = mutableListOf(),

    var connectOnDemand: Boolean = false,
    var autoConnectOnLaunch: Boolean = false,
    var autoConnectChoice: AutoConnectChoice = AutoConnectChoice.lastUsed,

    var remoteDns: String = "https://1.1.1.1/dns-query",
    var directDns: String = "8.8.8.8",

    var logLevel: String = "warning",
    var muxEnabled: Boolean = false,

    var fragmentEnabled: Boolean = false,
    var fragmentPackets: String = "tlshello",
    var fragmentLength: String = "100-200",
    var fragmentInterval: String = "10-20",

    var allowLan: Boolean = false,
    var httpPort: Int = 10809,

    var subscriptionAutoUpdateHours: Int = 12,
    var pingOnOpen: Boolean = false,
    var pingAfterSubscriptionUpdate: Boolean = false,

    var theme: AppTheme = AppTheme.system,
    var selectedProfileId: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("routingMode", routingMode.name)
        put("blockAds", blockAds)
        put("customRules", org.json.JSONArray(customRules.map { it.toJson() }))
        put("connectOnDemand", connectOnDemand)
        put("autoConnectOnLaunch", autoConnectOnLaunch)
        put("autoConnectChoice", autoConnectChoice.name)
        put("remoteDNS", remoteDns)
        put("directDNS", directDns)
        put("logLevel", logLevel)
        put("muxEnabled", muxEnabled)
        put("fragmentEnabled", fragmentEnabled)
        put("fragmentPackets", fragmentPackets)
        put("fragmentLength", fragmentLength)
        put("fragmentInterval", fragmentInterval)
        put("allowLAN", allowLan)
        put("httpPort", httpPort)
        put("subscriptionAutoUpdateHours", subscriptionAutoUpdateHours)
        put("pingOnOpen", pingOnOpen)
        put("pingAfterSubscriptionUpdate", pingAfterSubscriptionUpdate)
        put("theme", theme.name)
        put("selectedProfileId", selectedProfileId)
    }

    companion object {
        fun fromJson(o: JSONObject): AppSettings {
            val rules = mutableListOf<RoutingRule>()
            o.optJSONArray("customRules")?.let { arr ->
                for (i in 0 until arr.length()) rules.add(RoutingRule.fromJson(arr.getJSONObject(i)))
            }
            return AppSettings(
                routingMode = runCatching { RoutingMode.valueOf(o.optString("routingMode", "proxyAll")) }.getOrDefault(RoutingMode.proxyAll),
                blockAds = o.optBoolean("blockAds", false),
                customRules = rules,
                connectOnDemand = o.optBoolean("connectOnDemand", false),
                autoConnectOnLaunch = o.optBoolean("autoConnectOnLaunch", false),
                autoConnectChoice = runCatching { AutoConnectChoice.valueOf(o.optString("autoConnectChoice", "lastUsed")) }.getOrDefault(AutoConnectChoice.lastUsed),
                remoteDns = o.optString("remoteDNS", "https://1.1.1.1/dns-query"),
                directDns = o.optString("directDNS", "8.8.8.8"),
                logLevel = o.optString("logLevel", "warning"),
                muxEnabled = o.optBoolean("muxEnabled", false),
                fragmentEnabled = o.optBoolean("fragmentEnabled", false),
                fragmentPackets = o.optString("fragmentPackets", "tlshello"),
                fragmentLength = o.optString("fragmentLength", "100-200"),
                fragmentInterval = o.optString("fragmentInterval", "10-20"),
                allowLan = o.optBoolean("allowLAN", false),
                httpPort = o.optInt("httpPort", 10809),
                subscriptionAutoUpdateHours = o.optInt("subscriptionAutoUpdateHours", 12),
                pingOnOpen = o.optBoolean("pingOnOpen", false),
                pingAfterSubscriptionUpdate = o.optBoolean("pingAfterSubscriptionUpdate", false),
                theme = runCatching { AppTheme.valueOf(o.optString("theme", "system")) }.getOrDefault(AppTheme.system),
                selectedProfileId = if (o.has("selectedProfileId") && !o.isNull("selectedProfileId")) o.optString("selectedProfileId") else null,
            )
        }
    }
}

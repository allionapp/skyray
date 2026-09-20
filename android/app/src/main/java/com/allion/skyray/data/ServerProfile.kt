package com.allion.skyray.data

import org.json.JSONObject
import java.util.UUID

enum class CoreKind {
    xray,
    singbox,

    /** Cloudflare WARP through the Aether core; carries no outbound of its own. */
    warp,
}

/**
 * One proxy server. [outboundJson] is a single outbound object for [core],
 * serialized as JSON (an Xray outbound, or a sing-box outbound).
 */
data class ServerProfile(
    val id: String = UUID.randomUUID().toString(),
    var name: String,
    var protocolName: String,
    var address: String,
    var port: Int,
    var shareLink: String? = null,
    var outboundJson: String,
    var latencyMs: Int? = null,
    /** Where traffic through this server comes out, as the last probe saw it. */
    var exitIp: String? = null,
    /** ISO 3166 code of that exit, e.g. "DE". */
    var country: String? = null,
    var subscriptionUrl: String? = null,
    var createdAt: Long = System.currentTimeMillis(),
    var core: CoreKind = CoreKind.xray,
) {
    val subtitle: String
        get() = "${protocolName.uppercase()} · $address:$port" + if (core == CoreKind.singbox) " · sing-box" else ""

    /** The exit country's flag, or null until a probe has seen the exit. */
    val flag: String? get() = country?.let { CountryLabel.flag(it) }

    /**
     * A DNS tunnel has no host to open a socket to — it speaks to whatever
     * resolver answers — so a TCP handshake test says nothing about it.
     */
    val hasDialableEndpoint: Boolean get() = protocolName != "dnstt"

    /** "VLESS · XHTTP · TLS": what tells servers apart when their names only differ in the tail. */
    val kindLabel: String
        get() {
            val parts = mutableListOf(protocolName.uppercase())
            runCatching {
                val ob = JSONObject(outboundJson)
                val stream = ob.optJSONObject("streamSettings")
                if (stream != null) {
                    stream.optString("network").takeIf { it.isNotEmpty() }?.let { n ->
                        parts += when (n) { "ws" -> "WebSocket"; "raw", "tcp" -> "TCP"; else -> n.uppercase() }
                    }
                    stream.optString("security").takeIf { it.isNotEmpty() && it != "none" }?.let { sec ->
                        parts += if (sec == "tls") "TLS" else sec.replaceFirstChar { it.uppercase() }
                    }
                } else if (ob.optJSONObject("tls")?.optBoolean("enabled") == true) {
                    parts += "TLS"
                }
            }
            return parts.joinToString(" · ")
        }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("protocolName", protocolName)
        put("address", address)
        put("port", port)
        put("shareLink", shareLink)
        put("outboundJSON", outboundJson)
        put("latencyMs", latencyMs)
        put("exitIP", exitIp)
        put("country", country)
        put("subscriptionURL", subscriptionUrl)
        put("createdAt", createdAt)
        put("core", core.name)
    }

    companion object {
        /** Tolerant decoding: ignores unknown/missing fields from older or iOS-shaped JSON. */
        fun fromJson(o: JSONObject): ServerProfile? {
            val outbound = o.optString("outboundJSON", "").ifEmpty { return null }
            val address = o.optString("address", "")
            val name = o.optString("name", address)
            return ServerProfile(
                id = o.optString("id", UUID.randomUUID().toString()),
                name = name,
                protocolName = o.optString("protocolName", "unknown"),
                address = address,
                port = o.optInt("port", 0),
                shareLink = o.optString("shareLink", null.toString()).takeIf { o.has("shareLink") && !o.isNull("shareLink") },
                outboundJson = outbound,
                latencyMs = if (o.has("latencyMs") && !o.isNull("latencyMs")) o.optInt("latencyMs") else null,
                exitIp = if (o.has("exitIP") && !o.isNull("exitIP")) o.optString("exitIP") else null,
                country = if (o.has("country") && !o.isNull("country")) o.optString("country") else null,
                subscriptionUrl = if (o.has("subscriptionURL") && !o.isNull("subscriptionURL")) o.optString("subscriptionURL") else null,
                createdAt = o.optLong("createdAt", System.currentTimeMillis()),
                core = runCatching { CoreKind.valueOf(o.optString("core", "xray")) }.getOrDefault(CoreKind.xray),
            )
        }
    }
}

data class SubscriptionInfo(
    val url: String,
    var title: String? = null,
    var used: Long? = null,
    var total: Long? = null,
    var expireEpochSeconds: Long? = null,
    var updateIntervalHours: Int? = null,
    var webPageUrl: String? = null,
    var supportUrl: String? = null,
    var announce: String? = null,
    var lastUpdated: Long = System.currentTimeMillis(),
) {
    val isExpired: Boolean get() = expireEpochSeconds?.let { it * 1000 < System.currentTimeMillis() } ?: false

    val remaining: Long? get() = total?.let { t -> used?.let { u -> (t - u).coerceAtLeast(0) } }

    /** Unlimited plans report total = 0, which must not render as "0 B left". */
    val hasQuota: Boolean get() = (total ?: 0) > 0 && used != null

    val expiresSoon: Boolean
        get() = expireEpochSeconds?.let {
            val millis = it * 1000
            millis > System.currentTimeMillis() && millis - System.currentTimeMillis() < 3 * 24 * 3600 * 1000L
        } ?: false

    fun toJson(): JSONObject = JSONObject().apply {
        put("url", url); put("title", title); put("used", used); put("total", total)
        put("expire", expireEpochSeconds); put("updateIntervalHours", updateIntervalHours)
        put("webPageURL", webPageUrl); put("supportURL", supportUrl); put("announce", announce)
        put("lastUpdated", lastUpdated)
    }

    companion object {
        fun fromJson(o: JSONObject): SubscriptionInfo = SubscriptionInfo(
            url = o.optString("url"),
            title = o.optString("title", null.toString()).takeIf { o.has("title") && !o.isNull("title") },
            used = if (o.has("used") && !o.isNull("used")) o.optLong("used") else null,
            total = if (o.has("total") && !o.isNull("total")) o.optLong("total") else null,
            expireEpochSeconds = if (o.has("expire") && !o.isNull("expire")) o.optLong("expire") else null,
            updateIntervalHours = if (o.has("updateIntervalHours") && !o.isNull("updateIntervalHours")) o.optInt("updateIntervalHours") else null,
            webPageUrl = if (o.has("webPageURL") && !o.isNull("webPageURL")) o.optString("webPageURL") else null,
            supportUrl = if (o.has("supportURL") && !o.isNull("supportURL")) o.optString("supportURL") else null,
            announce = if (o.has("announce") && !o.isNull("announce")) o.optString("announce") else null,
            lastUpdated = o.optLong("lastUpdated", System.currentTimeMillis()),
        )
    }
}

/** Turns an ISO country code into a flag and a name in the user's language. */
object CountryLabel {
    fun flag(code: String): String? {
        val upper = code.uppercase()
        if (upper.length != 2 || !upper.all { it in 'A'..'Z' }) return null
        // Two regional-indicator symbols render as one flag.
        return upper.map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
    }

    fun name(code: String): String =
        java.util.Locale("", code.uppercase()).getDisplayCountry(java.util.Locale.getDefault()).ifEmpty { code.uppercase() }
}

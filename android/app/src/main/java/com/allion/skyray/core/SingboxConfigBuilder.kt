package com.allion.skyray.core

import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.AppSettings
import com.allion.skyray.data.RoutingMode
import org.json.JSONArray
import org.json.JSONObject

/**
 * Builds a full sing-box configuration mirroring XrayConfigBuilder: a local
 * SOCKS inbound for hev-socks5-tunnel, the user's outbound, DNS and routing.
 * Port of Shared/SingboxConfigBuilder.swift.
 */
object SingboxConfigBuilder {
    /** sing-box 1.12+ DNS server object from a user-facing address. */
    fun dnsServer(tag: String, address: String, detour: String): JSONObject {
        val server = JSONObject().put("tag", tag).put("detour", detour)
        val trimmed = address.trim()
        when {
            trimmed.lowercase().startsWith("https://") -> {
                val uri = runCatching { java.net.URI(trimmed) }.getOrNull()
                server.put("type", "https")
                server.put("server", uri?.host ?: trimmed)
                if (uri != null && uri.port > 0) server.put("server_port", uri.port)
                val path = uri?.path
                if (!path.isNullOrEmpty() && path != "/dns-query") server.put("path", path)
            }
            trimmed.lowercase().startsWith("tls://") -> {
                val hostPort = trimmed.substring(6)
                val parts = hostPort.split(":")
                server.put("type", "tls")
                server.put("server", parts.getOrNull(0) ?: "1.1.1.1")
                parts.getOrNull(1)?.toIntOrNull()?.let { server.put("server_port", it) }
            }
            trimmed.lowercase().startsWith("quic://") -> {
                server.put("type", "quic")
                server.put("server", trimmed.substring(7))
            }
            else -> {
                server.put("type", "udp")
                server.put("server", trimmed.ifEmpty { "8.8.8.8" })
            }
        }
        return server
    }

    @Throws(XrayCoreException::class)
    fun runtimeConfig(outboundJson: String, settings: AppSettings = AppSettings(), socksPort: Int = AppConstants.SOCKS_PORT): String {
        val proxy = runCatching { JSONObject(outboundJson) }.getOrNull() ?: throw XrayCoreException("Invalid outbound JSON")
        proxy.put("tag", "proxy")
        if (settings.fragmentEnabled) {
            proxy.optJSONObject("tls")?.let { tls ->
                if (tls.optBoolean("enabled", false)) {
                    tls.put("fragment", true)
                    proxy.put("tls", tls)
                }
            }
        }

        val rules = JSONArray()
        if (settings.routingMode != RoutingMode.global) {
            rules.put(JSONObject().put("ip_is_private", true).put("outbound", "direct"))
        }
        if (settings.blockAds) {
            rules.put(
                JSONObject().put(
                    "domain_suffix",
                    JSONArray(
                        listOf(
                            "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adnxs.com",
                            "yektanet.com", "tapsell.ir", "adro.co", "mediaad.org", "sabavision.com",
                            "daartads.com", "adivery.com",
                        ),
                    ),
                ).put("outbound", "block"),
            )
        }
        settings.customRules.filter { it.enabled && it.pattern.trim().isNotEmpty() }.forEach { rule ->
            val pattern = rule.pattern.trim()
            val r = JSONObject().put("outbound", rule.action.name)
            when {
                rule.isIP -> {
                    if (pattern.lowercase().startsWith("geoip:")) return@forEach
                    val cidr = if (pattern.contains("/")) pattern else if (pattern.contains(":")) "$pattern/128" else "$pattern/32"
                    r.put("ip_cidr", JSONArray(listOf(cidr)))
                }
                pattern.lowercase().startsWith("full:") -> r.put("domain", JSONArray(listOf(pattern.substring(5))))
                pattern.lowercase().startsWith("domain:") -> r.put("domain_suffix", JSONArray(listOf(pattern.substring(7))))
                pattern.lowercase().startsWith("keyword:") -> r.put("domain_keyword", JSONArray(listOf(pattern.substring(8))))
                pattern.lowercase().startsWith("regexp:") -> r.put("domain_regex", JSONArray(listOf(pattern.substring(7))))
                pattern.lowercase().startsWith("geosite:") -> return@forEach // geosite lists are Xray-only
                else -> r.put("domain_suffix", JSONArray(listOf(pattern)))
            }
            rules.put(r)
        }
        if (settings.routingMode == RoutingMode.bypassIran) {
            rules.put(JSONObject().put("domain_suffix", JSONArray(listOf(".ir"))).put("outbound", "direct"))
        }

        val dnsServers = JSONArray()
        if (settings.routingMode == RoutingMode.bypassIran) dnsServers.put(dnsServer("dns-direct", settings.directDns, "direct"))
        dnsServers.put(dnsServer("dns-remote", settings.remoteDns, "proxy"))
        val dnsRules = JSONArray()
        if (settings.routingMode == RoutingMode.bypassIran) {
            dnsRules.put(JSONObject().put("domain_suffix", JSONArray(listOf(".ir"))).put("server", "dns-direct"))
        }

        val inbounds = JSONArray()
        inbounds.put(
            JSONObject().put("type", "socks").put("tag", "socks-in")
                .put("listen", if (settings.allowLan) "0.0.0.0" else "127.0.0.1")
                .put("listen_port", socksPort),
        )
        if (settings.allowLan) {
            inbounds.put(JSONObject().put("type", "http").put("tag", "http-in").put("listen", "0.0.0.0").put("listen_port", settings.httpPort))
        }

        val level = when (settings.logLevel) { "warning" -> "warn"; "none" -> "panic"; else -> settings.logLevel }
        val routeRules = JSONArray()
        routeRules.put(JSONObject().put("action", "sniff"))
        routeRules.put(JSONObject().put("protocol", "dns").put("action", "hijack-dns"))
        for (i in 0 until rules.length()) routeRules.put(rules.get(i))

        val config = JSONObject()
            .put("log", JSONObject().put("level", level).put("timestamp", false))
            .put("dns", JSONObject().put("servers", dnsServers).put("rules", dnsRules).put("final", "dns-remote").put("strategy", "prefer_ipv4"))
            .put("inbounds", inbounds)
            .put(
                "outbounds",
                JSONArray().put(proxy)
                    .put(JSONObject().put("type", "direct").put("tag", "direct"))
                    .put(JSONObject().put("type", "block").put("tag", "block")),
            )
            .put("route", JSONObject().put("rules", routeRules).put("final", "proxy").put("auto_detect_interface", false))

        return config.toString()
    }
}

package com.allion.skyray.core

import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.AppSettings
import com.allion.skyray.data.RoutingMode
import com.allion.skyray.data.RuleAction
import org.json.JSONArray
import org.json.JSONObject

/**
 * Builds the full Xray runtime configuration used inside the VPN service:
 * inbounds (SOCKS + HTTP), the user's outbound, DNS, policy and routing.
 * Port of Shared/XrayConfigBuilder.swift.
 */
object XrayConfigBuilder {
    val privateRanges = listOf(
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8",
        "169.254.0.0/16", "100.64.0.0/10", "fc00::/7", "fe80::/10", "::1/128",
    )

    @Throws(XrayCoreException::class)
    fun runtimeConfig(
        outboundJson: String,
        settings: AppSettings = AppSettings(),
        socksPort: Int = AppConstants.SOCKS_PORT,
        hasGeoData: Boolean = true,
    ): String {
        val proxy = runCatching { JSONObject(outboundJson) }.getOrNull()
            ?: throw XrayCoreException("Invalid outbound JSON")
        proxy.put("tag", "proxy")
        if (settings.muxEnabled) {
            proxy.put("mux", JSONObject().put("enabled", true).put("concurrency", 8))
        } else {
            proxy.remove("mux")
        }

        val outbounds = JSONArray()
        if (settings.fragmentEnabled) {
            val stream = proxy.optJSONObject("streamSettings") ?: JSONObject()
            val sockopt = stream.optJSONObject("sockopt") ?: JSONObject()
            sockopt.put("dialerProxy", "fragment")
            stream.put("sockopt", sockopt)
            proxy.put("streamSettings", stream)
            outbounds.put(
                JSONObject()
                    .put("tag", "fragment")
                    .put("protocol", "freedom")
                    .put(
                        "settings",
                        JSONObject().put("domainStrategy", "UseIP").put(
                            "fragment",
                            JSONObject().put("packets", settings.fragmentPackets)
                                .put("length", settings.fragmentLength)
                                .put("interval", settings.fragmentInterval),
                        ),
                    )
                    .put("streamSettings", JSONObject().put("sockopt", JSONObject().put("tcpNoDelay", true))),
            )
        }
        // proxy goes first
        val allOutbounds = JSONArray()
        allOutbounds.put(proxy)
        for (i in 0 until outbounds.length()) allOutbounds.put(outbounds.get(i))
        allOutbounds.put(JSONObject().put("tag", "direct").put("protocol", "freedom").put("settings", JSONObject().put("domainStrategy", "UseIP")))
        allOutbounds.put(JSONObject().put("tag", "block").put("protocol", "blackhole"))

        val rules = JSONArray()
        if (settings.routingMode != RoutingMode.global) {
            val ips = JSONArray()
            if (hasGeoData) ips.put("geoip:private")
            privateRanges.forEach { ips.put(it) }
            rules.put(JSONObject().put("type", "field").put("ip", ips).put("outboundTag", "direct"))
        }
        if (settings.blockAds) {
            val ads = mutableListOf(
                "domain:doubleclick.net", "domain:googlesyndication.com", "domain:googleadservices.com",
                "domain:adservice.google.com", "domain:adnxs.com", "domain:yektanet.com", "domain:tapsell.ir",
                "domain:adro.co", "domain:mediaad.org", "domain:sabavision.com", "domain:daartads.com",
                "domain:adivery.com", "domain:magnetadservices.com", "domain:e-planning.net",
            )
            if (hasGeoData) ads.add(0, "geosite:category-ads")
            rules.put(JSONObject().put("type", "field").put("domain", JSONArray(ads)).put("outboundTag", "block"))
        }
        val domainRules = mutableMapOf<RuleAction, MutableList<String>>()
        val ipRules = mutableMapOf<RuleAction, MutableList<String>>()
        settings.customRules.filter { it.enabled && it.pattern.trim().isNotEmpty() }.forEach { rule ->
            val pattern = rule.pattern.trim()
            if (rule.isIP) ipRules.getOrPut(rule.action) { mutableListOf() }.add(pattern)
            else domainRules.getOrPut(rule.action) { mutableListOf() }.add(pattern)
        }
        RuleAction.entries.forEach { action ->
            domainRules[action]?.let { rules.put(JSONObject().put("type", "field").put("domain", JSONArray(it)).put("outboundTag", action.name)) }
            ipRules[action]?.let { rules.put(JSONObject().put("type", "field").put("ip", JSONArray(it)).put("outboundTag", action.name)) }
        }
        if (settings.routingMode == RoutingMode.bypassIran) {
            if (hasGeoData) {
                rules.put(JSONObject().put("type", "field").put("domain", JSONArray(listOf("geosite:category-ir", "domain:ir"))).put("outboundTag", "direct"))
                rules.put(JSONObject().put("type", "field").put("ip", JSONArray(listOf("geoip:ir"))).put("outboundTag", "direct"))
            } else {
                rules.put(JSONObject().put("type", "field").put("domain", JSONArray(listOf("domain:ir"))).put("outboundTag", "direct"))
            }
        }

        val dnsServers = JSONArray()
        if (settings.routingMode == RoutingMode.bypassIran) {
            val direct = JSONObject().put("address", settings.directDns).put("skipFallback", true)
                .put("domains", if (hasGeoData) JSONArray(listOf("geosite:category-ir", "domain:ir")) else JSONArray(listOf("domain:ir")))
            dnsServers.put(direct)
        }
        dnsServers.put(settings.remoteDns)
        dnsServers.put("8.8.8.8")

        val inbounds = JSONArray()
        inbounds.put(
            JSONObject().put("tag", "socks-in")
                .put("listen", if (settings.allowLan) "0.0.0.0" else "127.0.0.1")
                .put("port", socksPort).put("protocol", "socks")
                .put("settings", JSONObject().put("auth", "noauth").put("udp", true))
                .put("sniffing", JSONObject().put("enabled", true).put("destOverride", JSONArray(listOf("http", "tls", "quic"))).put("routeOnly", false)),
        )
        if (settings.allowLan) {
            inbounds.put(
                JSONObject().put("tag", "http-in").put("listen", "0.0.0.0").put("port", settings.httpPort)
                    .put("protocol", "http")
                    .put("sniffing", JSONObject().put("enabled", true).put("destOverride", JSONArray(listOf("http", "tls")))),
            )
        }

        val config = JSONObject()
            .put("log", JSONObject().put("loglevel", settings.logLevel).put("access", "none"))
            .put("dns", JSONObject().put("servers", dnsServers).put("queryStrategy", "UseIP"))
            .put("policy", JSONObject().put("levels", JSONObject().put("0", JSONObject().put("connIdle", 300).put("handshake", 4).put("uplinkOnly", 2).put("downlinkOnly", 5))))
            .put("inbounds", inbounds)
            .put("outbounds", allOutbounds)
            .put("routing", JSONObject().put("domainStrategy", "IPIfNonMatch").put("domainMatcher", "linear").put("rules", rules))

        return config.toString()
    }
}

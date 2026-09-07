package com.allion.skyray.core

import android.net.Uri
import android.util.Base64
import com.allion.skyray.data.ServerProfile
import org.json.JSONObject
import java.net.URLDecoder

/**
 * Turns pasted text (share links, a subscription body, Clash YAML, or raw
 * Xray JSON) into [ServerProfile]s using the Go core for protocol details.
 * Port of Shared/ShareLinkParser.swift.
 */
object ShareLinkParser {
    val supportedSchemes = listOf("vmess://", "vless://", "trojan://", "ss://", "socks://", "hysteria2://", "hy2://") +
        SingboxLinkParser.schemes

    data class Failure(val line: String, val reason: String)
    data class Outcome(val profiles: MutableList<ServerProfile> = mutableListOf(), val failures: MutableList<Failure> = mutableListOf())

    fun parse(rawText: String, subscriptionUrl: String? = null): Outcome {
        var text = rawText.trim()
        if (!containsShareLink(text) && !text.startsWith("{") && !isClashYaml(text)) {
            decodeBase64(text)?.let { text = it }
        }

        if (text.startsWith("{")) return parseRawJson(text)
        if (isClashYaml(text)) return parseWholeTextWithCore(text, subscriptionUrl)

        val outcome = Outcome()
        val lines = text.split(Regex("\\r?\\n")).map { it.trim() }
            .filter { line -> supportedSchemes.any { line.lowercase().startsWith(it) } }

        for (line in lines) {
            if (SingboxLinkParser.handles(line)) {
                try {
                    val profile = SingboxLinkParser.parse(line).also { it.subscriptionUrl = subscriptionUrl }
                    outcome.profiles.add(profile)
                } catch (e: Exception) {
                    outcome.failures.add(Failure(line, e.message ?: "parse error"))
                }
                continue
            }
            try {
                val outbounds = RaycoreBridge.parseShareLinks(line)
                val outbound = outbounds.firstOrNull()
                if (outbound == null) {
                    outcome.failures.add(Failure(line, "No outbound produced"))
                    continue
                }
                applyLinkExtras(line, outbound)
                val profile = makeProfile(outbound, null)
                profile.name = displayName(line) ?: profile.name
                profile.shareLink = line
                profile.subscriptionUrl = subscriptionUrl
                outcome.profiles.add(profile)
            } catch (e: Exception) {
                outcome.failures.add(Failure(line, e.message ?: "parse error"))
            }
        }
        return outcome
    }

    private fun parseWholeTextWithCore(text: String, subscriptionUrl: String?): Outcome {
        val outcome = Outcome()
        try {
            for (outbound in RaycoreBridge.parseShareLinks(text)) {
                val name = outbound.optString("sendThrough", null.toString()).takeIf { outbound.has("sendThrough") }
                    ?: outbound.optString("tag", null.toString()).takeIf { outbound.has("tag") }
                val profile = makeProfile(outbound, name)
                profile.subscriptionUrl = subscriptionUrl
                outcome.profiles.add(profile)
            }
        } catch (e: Exception) {
            outcome.failures.add(Failure(text.take(80), e.message ?: "parse error"))
        }
        return outcome
    }

    private fun parseRawJson(text: String): Outcome {
        val outcome = Outcome()
        val obj = runCatching { JSONObject(text) }.getOrNull()
        if (obj == null) {
            outcome.failures.add(Failure(text.take(80), "Invalid JSON"))
            return outcome
        }
        val outbounds = mutableListOf<JSONObject>()
        val list = obj.optJSONArray("outbounds")
        if (list != null) {
            for (i in 0 until list.length()) {
                val o = list.getJSONObject(i)
                val proto = o.optString("protocol", "")
                if (proto !in listOf("freedom", "blackhole", "dns", "loopback")) outbounds.add(o)
            }
        } else {
            outbounds.add(obj)
        }
        for (outbound in outbounds) {
            try {
                outcome.profiles.add(makeProfile(outbound, outbound.optString("tag", null.toString()).takeIf { outbound.has("tag") }))
            } catch (e: Exception) {
                outcome.failures.add(Failure(outbound.optString("tag", "outbound"), e.message ?: "parse error"))
            }
        }
        return outcome
    }

    /** Options the share-link converter drops but users rely on, e.g. `allowInsecure=1`. */
    fun applyLinkExtras(link: String, outbound: JSONObject) {
        val uri = runCatching { Uri.parse(link) }.getOrNull() ?: return
        val flags = uri.queryParameterNames.associateWith { (uri.getQueryParameter(it) ?: "") }.mapKeys { it.key.lowercase() }
        val insecure = (flags["allowinsecure"] ?: flags["insecure"] ?: "").lowercase() in listOf("1", "true")
        if (!insecure) return
        val stream = outbound.optJSONObject("streamSettings") ?: return
        if (stream.optString("security") != "tls") return
        val tls = stream.optJSONObject("tlsSettings") ?: JSONObject()
        tls.put("allowInsecure", true)
        stream.put("tlsSettings", tls)
        outbound.put("streamSettings", stream)
    }

    @Throws(XrayCoreException::class)
    fun makeProfile(outbound: JSONObject, fallbackName: String?): ServerProfile {
        val protocolName = outbound.optString("protocol", "unknown")
        val settings = outbound.optJSONObject("settings") ?: JSONObject()
        var address = settings.optString("address", "")
        var port = settings.optInt("port", 0)
        if (address.isEmpty()) {
            val list = settings.optJSONArray("vnext") ?: settings.optJSONArray("servers")
            val first = list?.optJSONObject(0)
            if (first != null) {
                address = first.optString("address", "")
                port = first.optInt("port", 0)
            }
        }
        if (address.isEmpty() || port <= 0) throw XrayCoreException("Missing server address or port")
        val clean = JSONObject(outbound.toString())
        clean.remove("sendThrough")
        clean.remove("tag")
        val name = fallbackName?.takeIf { it.isNotEmpty() && it != "proxy" } ?: "$address:$port"
        return ServerProfile(name = name, protocolName = protocolName, address = address, port = port, outboundJson = clean.toString())
    }

    /** Human-readable name: the `#fragment` of a link, or `ps` for vmess links. */
    fun displayName(link: String): String? {
        val hashIndex = link.indexOf('#')
        if (hashIndex >= 0) {
            val fragment = link.substring(hashIndex + 1)
            val name = runCatching { URLDecoder.decode(fragment, "UTF-8") }.getOrDefault(fragment).trim()
            if (name.isNotEmpty()) return name
        }
        if (link.lowercase().startsWith("vmess://")) {
            val body = link.substring("vmess://".length)
            val json = decodeBase64(body)
            if (json != null) {
                val dict = runCatching { JSONObject(json) }.getOrNull()
                val ps = dict?.optString("ps", "")
                if (!ps.isNullOrEmpty()) return ps
            }
        }
        return null
    }

    fun containsShareLink(text: String): Boolean {
        val lower = text.lowercase()
        return supportedSchemes.any { lower.contains(it) }
    }

    fun isClashYaml(text: String): Boolean =
        Regex("(?m)^proxies:\\s*$").containsMatchIn(text) || Regex("(?m)^proxies:\\s*\\[").containsMatchIn(text)

    fun decodeBase64(text: String): String? {
        val s = text.replace("-", "+").replace("_", "/").replace(Regex("\\s"), "")
        return try {
            val padded = s + "=".repeat((4 - s.length % 4) % 4)
            String(Base64.decode(padded, Base64.DEFAULT), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }
}

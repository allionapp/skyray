package com.allion.skyray.core

import android.net.Uri
import java.net.URLDecoder

/**
 * Understands the "launcher" deep links VPN panels hand out for other clients
 * (hiddify://import/<url>, v2box://install-sub?url=…, clash://install-config?url=…,
 * sub://<base64 url>, skyray://import/<url>) and extracts the real http(s) URL.
 * Port of Shared/SubscriptionLinkResolver.swift.
 */
object SubscriptionLinkResolver {
    data class Resolved(val url: String, val title: String? = null)

    private val pathPrefixes = listOf(
        "hiddify://import/", "hiddifynext://import/", "streisand://import/", "happ://add/",
        "skyray://import/", "shadowrocket://add/", "v2rayng://install-sub/",
    )

    private val querySchemes = setOf(
        "v2box", "v2rayng", "clash", "clashmeta", "clashx", "stash", "sing-box", "singbox",
        "nekobox", "nekoray", "surge", "loon", "quantumult-x", "hiddify", "skyray", "shadowrocket",
    )

    fun resolve(raw: String): Resolved? {
        val text = raw.trim()
        if (text.isEmpty()) return null
        val lower = text.lowercase()

        if (lower.startsWith("http://") || lower.startsWith("https://")) {
            return Resolved(stripFragment(text), fragmentOf(text))
        }

        for (prefix in pathPrefixes) {
            if (lower.startsWith(prefix)) return unwrap(text.substring(prefix.length))
        }

        if (querySchemes.contains(lower.substringBefore("://"))) {
            val uri = runCatching { Uri.parse(text) }.getOrNull()
            if (uri != null) {
                for (key in listOf("url", "link", "config", "sub")) {
                    val value = uri.getQueryParameter(key) ?: continue
                    val resolved = unwrap(value) ?: continue
                    val name = listOf("name", "title", "remark").firstNotNullOfOrNull { uri.getQueryParameter(it) }
                    return resolved.copy(title = name ?: resolved.title ?: fragmentOf(text))
                }
            }
        }

        if (lower.startsWith("sub://")) {
            val payload = text.substring("sub://".length)
            val decoded = ShareLinkParser.decodeBase64(stripFragment(payload)) ?: return null
            val resolved = unwrap(decoded) ?: return null
            return fragmentOf(payload)?.let { resolved.copy(title = it) } ?: resolved
        }
        return null
    }

    private fun unwrap(payload: String): Resolved? {
        var value = payload
        runCatching { URLDecoder.decode(payload, "UTF-8") }.getOrNull()?.let {
            if (it.lowercase().startsWith("http")) value = it
        }
        val lower = value.lowercase()
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) return null
        return Resolved(stripFragment(value), fragmentOf(value))
    }

    private fun stripFragment(s: String): String = s.substringBefore('#')

    private fun fragmentOf(s: String): String? {
        val hash = s.indexOf('#')
        if (hash < 0) return null
        val raw = s.substring(hash + 1)
        val decoded = runCatching { URLDecoder.decode(raw, "UTF-8") }.getOrNull() ?: raw
        return decoded.ifEmpty { null }
    }
}

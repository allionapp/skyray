package com.allion.skyray.core

import android.net.Uri
import com.allion.skyray.data.CoreKind
import com.allion.skyray.data.ServerProfile
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLDecoder

/**
 * Parses share links for protocols only sing-box provides: `ssh://` and TUIC v5
 * `tuic://uuid:password@host:port?...`. Port of Shared/SingboxLinkParser.swift.
 */
object SingboxLinkParser {
    val schemes = listOf("ssh://", "tuic://")

    fun handles(line: String): Boolean = schemes.any { line.lowercase().startsWith(it) }

    private fun decode(s: String?): String? = s?.let { runCatching { URLDecoder.decode(it, "UTF-8") }.getOrDefault(it) }

    @Throws(XrayCoreException::class)
    fun parse(line: String): ServerProfile {
        val trimmed = line.trim()
        val uri = runCatching { Uri.parse(trimmed) }.getOrNull()
            ?: throw XrayCoreException("Invalid link")
        val scheme = uri.scheme?.lowercase() ?: throw XrayCoreException("Invalid link")
        val host = uri.host?.takeIf { it.isNotEmpty() } ?: throw XrayCoreException("Invalid link")
        val query = uri.queryParameterNames.associateWith { name -> uri.getQueryParameter(name) ?: "" }
            .mapKeys { it.key.lowercase() }
        val userInfo = trimmed.substringAfter("://").substringBefore("@", "").takeIf { trimmed.contains("@") }
        val (user, pass) = userInfo?.split(":", limit = 2)?.let { it.getOrNull(0) to it.getOrNull(1) } ?: (null to null)
        val name = uri.fragment?.let { decode(it)?.trim() }

        val outbound = JSONObject()
        outbound.put("server", host)
        var protocolName = scheme
        val port: Int

        when (scheme) {
            "ssh" -> {
                port = if (uri.port > 0) uri.port else 22
                outbound.put("type", "ssh")
                outbound.put("server_port", port)
                outbound.put("user", decode(user) ?: "root")
                decode(pass)?.takeIf { it.isNotEmpty() }?.let { outbound.put("password", it) }
                (query["privatekey"] ?: query["private_key"] ?: query["key"])?.takeIf { it.isNotEmpty() }?.let {
                    outbound.put("private_key", ShareLinkParser.decodeBase64(it) ?: decode(it) ?: it)
                }
                query["passphrase"]?.takeIf { it.isNotEmpty() }?.let { outbound.put("private_key_passphrase", it) }
                (query["hostkey"] ?: query["host_key"])?.takeIf { it.isNotEmpty() }?.let {
                    outbound.put("host_key", JSONArray().put(it))
                }
                protocolName = "ssh"
            }
            "tuic" -> {
                port = if (uri.port > 0) uri.port else 443
                outbound.put("type", "tuic")
                outbound.put("server_port", port)
                outbound.put("uuid", decode(user) ?: "")
                outbound.put("password", decode(pass) ?: "")
                outbound.put("congestion_control", query["congestion_control"] ?: query["congestion_controller"] ?: "bbr")
                outbound.put("udp_relay_mode", query["udp_relay_mode"] ?: "native")
                if ((query["zero_rtt_handshake"] ?: "") in listOf("1", "true")) outbound.put("zero_rtt_handshake", true)
                val tls = JSONObject().put("enabled", true)
                (query["sni"] ?: query["peer"])?.takeIf { it.isNotEmpty() }?.let { tls.put("server_name", it) }
                query["alpn"]?.takeIf { it.isNotEmpty() }?.let { tls.put("alpn", JSONArray(it.split(","))) }
                if ((query["allow_insecure"] ?: query["allowinsecure"] ?: query["insecure"] ?: "").lowercase() in listOf("1", "true")) {
                    tls.put("insecure", true)
                }
                if ((query["disable_sni"] ?: "") in listOf("1", "true")) tls.put("disable_sni", true)
                outbound.put("tls", tls)
                protocolName = "tuic"
            }
            else -> throw XrayCoreException("Unsupported scheme $scheme")
        }

        return ServerProfile(
            name = name?.takeIf { it.isNotEmpty() } ?: "$host:$port",
            protocolName = protocolName, address = host, port = port, shareLink = line,
            outboundJson = outbound.toString(), core = CoreKind.singbox,
        )
    }
}

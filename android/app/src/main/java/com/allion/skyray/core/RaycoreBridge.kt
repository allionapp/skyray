package com.allion.skyray.core

import org.json.JSONArray
import org.json.JSONObject
import raycore.Raycore

class XrayCoreException(message: String) : Exception(message)

data class PingResult(val success: Boolean, val delayMs: Int, val error: String)

/**
 * Thin Kotlin wrapper over the gomobile Android bindings in raycore.aar
 * (github.com/ehsan/rayclient/raycore), mirroring Shared/XrayCore.swift and
 * Shared/SingboxCore.swift on iOS so the two apps share one mental model.
 */
object RaycoreBridge {
    private const val API_VERSION = 2

    /** See raycore.SetEnv's doc comment: Os.setenv() from Kotlin doesn't
     * reach the Go runtime embedded in raycore.aar, so XRAY_LOCATION_ASSET
     * (and any other env xray-core/sing-box read) must be set through here. */
    fun setEnv(key: String, value: String) = Raycore.setEnv(key, value)

    @Throws(XrayCoreException::class)
    fun xrayInvoke(method: String, payload: JSONObject? = null): Any? {
        val request = JSONObject().apply {
            put("apiVersion", API_VERSION)
            put("method", method)
            if (payload != null) put("payload", payload)
        }
        val responseJson = Raycore.xrayInvoke(request.toString())
        val response = runCatching { JSONObject(responseJson) }.getOrNull()
            ?: throw XrayCoreException("Unexpected response from Xray core")
        if (response.optBoolean("success", false)) return response.opt("data")
        throw XrayCoreException(response.optString("error", "unknown error"))
    }

    fun xrayVersion(): String =
        runCatching { (xrayInvoke("xrayVersion") as? JSONObject)?.optString("version") }.getOrNull() ?: "unknown"

    /** Converts share link(s)/Clash YAML into Xray outbound objects. */
    @Throws(XrayCoreException::class)
    fun parseShareLinks(text: String): List<JSONObject> {
        val data = xrayInvoke("convertShareLinksToXrayJson", JSONObject().put("text", text)) as? JSONObject
        val arr = data?.optJSONArray("outbounds") ?: JSONArray()
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    @Throws(XrayCoreException::class)
    fun testXrayConfig(configJson: String) {
        xrayInvoke("testXray", JSONObject().put("xrayJson", configJson))
    }

    @Throws(XrayCoreException::class)
    fun runXray(configJson: String) {
        xrayInvoke("runXray", JSONObject().put("xrayJson", configJson))
    }

    fun stopXray() {
        runCatching { xrayInvoke("stopXray") }
    }

    fun isXrayRunning(): Boolean =
        runCatching { (xrayInvoke("getXrayState") as? JSONObject)?.optBoolean("running") }.getOrDefault(false) ?: false

    /** libXray accepts at most five configs per call. */
    @Throws(XrayCoreException::class)
    fun pingBatch(outbounds: List<JSONObject>, timeoutSeconds: Int, url: String): List<PingResult> {
        val configs = JSONArray()
        outbounds.forEach { outbound ->
            val tagged = JSONObject(outbound.toString()).put("tag", "proxy")
            val json = JSONObject().put("outbounds", JSONArray().put(tagged))
            configs.put(JSONObject().put("xrayJson", json.toString()).put("outboundTag", "proxy"))
        }
        val data = xrayInvoke(
            "pingBatch",
            JSONObject().put("configs", configs).put("timeout", timeoutSeconds).put("url", url)
        ) as? JSONObject
        val results = data?.optJSONArray("results") ?: JSONArray()
        return (0 until results.length()).map {
            val r = results.getJSONObject(it)
            PingResult(r.optBoolean("success", false), r.optInt("delay", -1), r.optString("error", ""))
        }
    }

    // MARK: sing-box (SSH, TUIC)

    fun singboxVersion(): String = runCatching { Raycore.singboxVersion() }.getOrDefault("unknown")

    @Throws(Exception::class)
    fun singboxStart(configJson: String) = Raycore.singboxStart(configJson)

    fun singboxStop() {
        runCatching { Raycore.singboxStop() }
    }

    fun isSingboxRunning(): Boolean = runCatching { Raycore.singboxRunning() }.getOrDefault(false)

    @Throws(Exception::class)
    fun testSingboxConfig(configJson: String) = Raycore.singboxTest(configJson)

    fun singboxPing(outboundJson: String, url: String, timeoutMs: Int): PingResult = try {
        val delay = Raycore.singboxPing(outboundJson, url, timeoutMs.toLong())
        PingResult(true, delay.toInt(), "")
    } catch (e: Exception) {
        PingResult(false, -1, e.message ?: "ping failed")
    }
}

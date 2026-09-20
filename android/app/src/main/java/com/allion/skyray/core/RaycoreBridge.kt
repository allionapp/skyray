package com.allion.skyray.core

import org.json.JSONArray
import org.json.JSONObject
import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.CoreKind
import com.allion.skyray.data.ServerProfile
import raycore.Raycore

class XrayCoreException(message: String) : Exception(message)


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

    // MARK: probes (both cores)

    /**
     * One HTTP request through each server, inside the Go runtime: delay and
     * where the traffic comes out. Results come back in the order given.
     */
    fun probeBatch(profiles: List<ServerProfile>, timeoutSeconds: Int = AppConstants.PING_TIMEOUT_SECONDS): List<ProbeResult> {
        val items = JSONArray()
        profiles.forEach { p ->
            items.put(JSONObject().put("core", if (p.core == CoreKind.singbox) "singbox" else "xray").put("outbound", JSONObject(p.outboundJson)))
        }
        val reply = runCatching { Raycore.probeBatch(items.toString(), AppConstants.PROBE_URL, timeoutSeconds * 1000L) }
            .getOrElse { return profiles.map { ProbeResult.FAILED } }
        val results = runCatching { JSONArray(reply) }.getOrElse { return profiles.map { ProbeResult.FAILED } }
        return profiles.indices.map { i ->
            val r = results.optJSONObject(i) ?: return@map ProbeResult.FAILED
            ProbeResult(
                delayMs = r.optInt("delay", -1),
                exitIp = r.optString("ip", "").ifEmpty { null },
                country = r.optString("country", "").ifEmpty { null },
                error = r.optString("error", ""),
            )
        }
    }
}

/** What one probe found about a server; [delayMs] is -1 when it failed. */
data class ProbeResult(val delayMs: Int, val exitIp: String?, val country: String?, val error: String) {
    val success: Boolean get() = delayMs >= 0

    companion object {
        val FAILED = ProbeResult(-1, null, null, "")
    }
}

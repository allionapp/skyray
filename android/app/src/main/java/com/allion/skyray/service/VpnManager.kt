package com.allion.skyray.service

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.activity.result.ActivityResultLauncher
import com.allion.skyray.R
import com.allion.skyray.core.AdSignalOverride
import com.allion.skyray.core.AdsManager
import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.AppSettings
import com.allion.skyray.data.ProfileStore
import com.allion.skyray.data.ServerProfile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class TunnelStats(
    val txBytes: Long,
    val rxBytes: Long,
    /** Bytes per second over the last poll, for the live Up/Down readout. */
    val upSpeed: Long = 0,
    val downSpeed: Long = 0,
)

/**
 * App-side controller: starts/stops [SkyRayVpnService] and mirrors its status
 * for Compose, the same role VPNManager.swift plays for the Network Extension
 * on iOS (there the polling is NEVPNStatus notifications; here it's the
 * service's own companion state, since everything runs in one process).
 */
class VpnManager(private val context: Context) {
    private val store = ProfileStore.get(context)
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()
    private val _connectedSinceMillis = MutableStateFlow(0L)
    val connectedSinceMillis: StateFlow<Long> = _connectedSinceMillis.asStateFlow()
    /**
     * Where the tunnel's traffic comes out, asked through the running core
     * once it is up: the proof that traffic really flows, and through where.
     */
    private val _exitInfo = MutableStateFlow<ExitInfo?>(null)
    val exitInfo: StateFlow<ExitInfo?> = _exitInfo.asStateFlow()
    private var exitJob: Job? = null
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()
    private val _stats = MutableStateFlow(TunnelStats(0, 0))
    val stats: StateFlow<TunnelStats> = _stats.asStateFlow()

    /** Why the tunnel stopped itself, when it wasn't an error: the ad was skipped. */
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    var settings: AppSettings = store.loadSettings()
        set(value) {
            field = value
            store.saveSettings(value)
        }

    private var lastTx = 0L
    private var lastRx = 0L
    private var pollJob: Job? = null

    init {
        startPolling()
    }

    private fun startPolling() {
        pollJob?.cancel()
        pollJob = scope.launch {
            var wasRunning = false
            while (isActive) {
                val running = SkyRayVpnService.isRunning
                _isConnected.value = running
                _connectedSinceMillis.value = if (running) SkyRayVpnService.connectedAtMillis else 0L
                _lastError.value = SkyRayVpnService.lastError

                if (running) {
                    val tx = SkyRayVpnService.txBytes
                    val rx = SkyRayVpnService.rxBytes
                    // The loop ticks once a second, so a delta is already a rate.
                    _stats.value = TunnelStats(
                        txBytes = tx,
                        rxBytes = rx,
                        upSpeed = (tx - lastTx).coerceAtLeast(0),
                        downSpeed = (rx - lastRx).coerceAtLeast(0),
                    )
                    lastTx = tx
                    lastRx = rx
                } else {
                    _stats.value = TunnelStats(0, 0)
                    lastTx = 0
                    lastRx = 0
                }
                if (!running && wasRunning) {
                    exitJob?.cancel()
                    _exitInfo.value = null
                    // Put the device's real locale/time zone back once the tunnel
                    // is no longer carrying the traffic. No-op if never applied.
                    AdSignalOverride.restore()
                }
                if (running && !wasRunning) {
                    fetchExitInfo(SkyRayVpnService.activeSocksPort)
                    // On an xray connection the app's traffic rides the tunnel, so
                    // the ad request leaves from the exit node: match the locale to
                    // it (neutral until the probe resolves the country, refined in
                    // fetchExitInfo), never the device's fa/Tehran.
                    if (SkyRayVpnService.adsUseTunnel) {
                        AdSignalOverride.apply(_exitInfo.value?.country)
                    }
                    (context as? Activity)?.let { activity ->
                        // Start the ads SDK now — over the tunnel — rather than at
                        // launch on the real network.
                        AdsManager.start(activity)
                        AdsManager.showAfterConnect(activity) {
                            // The ad was closed early: the free connection ends with it.
                            store.appendTunnelLog("[ad] closed before the reward; disconnecting")
                            _notice.value = context.getString(R.string.ad_required_notice)
                            disconnect()
                        }
                    }
                }
                wasRunning = running
                kotlinx.coroutines.delay(1000)
            }
        }
    }

    /**
     * Asks Cloudflare where this connection comes out. The app is excluded
     * from its own VPN (so the core can dial out), so the request goes through
     * the core's local SOCKS port rather than the tunnel interface. Retried a
     * few times: the service reports connected a moment before bytes flow.
     */
    private fun fetchExitInfo(socksPort: Int) {
        exitJob?.cancel()
        if (socksPort <= 0) return
        exitJob = scope.launch(Dispatchers.IO) {
            val proxy = java.net.Proxy(java.net.Proxy.Type.SOCKS, java.net.InetSocketAddress("127.0.0.1", socksPort))
            repeat(4) { attempt ->
                val found = runCatching {
                    val connection = java.net.URL(AppConstants.PROBE_URL).openConnection(proxy) as java.net.HttpURLConnection
                    connection.connectTimeout = 8000
                    connection.readTimeout = 8000
                    connection.useCaches = false
                    try {
                        val lines = connection.inputStream.bufferedReader().use { it.readText() }.lines()
                        val fields = lines.mapNotNull { line -> line.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }.toMap()
                        fields["ip"]?.let { ExitInfo(it, fields["loc"]) }
                    } finally {
                        connection.disconnect()
                    }
                }.getOrNull()
                if (found != null) {
                    _exitInfo.value = found
                    // Refine the ad-signal override to the exact exit country now
                    // that the probe resolved it (only when the app tunnels).
                    if (SkyRayVpnService.adsUseTunnel) AdSignalOverride.apply(found.country)
                    return@launch
                }
                kotlinx.coroutines.delay((1 + attempt) * 1000L)
            }
        }
    }

    /** Call from an Activity's registerForActivityResult(StartActivityForResult()). */
    fun prepareIntent(): Intent? = VpnService.prepare(context)

    fun connect(profile: ServerProfile, launcher: ActivityResultLauncher<Intent>) {
        _notice.value = null
        val prepare = VpnService.prepare(context)
        if (prepare != null) {
            launcher.launch(prepare)
        } else {
            startService(profile)
        }
    }

    fun startService(profile: ServerProfile) {
        store.selectedProfileId = profile.id
        val intent = Intent(context, SkyRayVpnService::class.java).apply {
            action = AppConstants.VPN_ACTION_CONNECT
            putExtra(AppConstants.EXTRA_OUTBOUND_JSON, profile.outboundJson)
            putExtra(AppConstants.EXTRA_CORE, profile.core.name)
        }
        context.startService(intent)
    }

    fun disconnect() {
        val intent = Intent(context, SkyRayVpnService::class.java).apply { action = AppConstants.VPN_ACTION_DISCONNECT }
        context.startService(intent)
    }

    fun toggle(profile: ServerProfile?, launcher: ActivityResultLauncher<Intent>) {
        if (_isConnected.value) {
            disconnect()
        } else if (profile != null) {
            connect(profile, launcher)
        }
    }
}

/** The tunnel's exit as Cloudflare saw it: the address and, when known, its country code. */
data class ExitInfo(val ip: String, val country: String?)

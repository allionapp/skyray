package com.allion.skyray.service

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.activity.result.ActivityResultLauncher
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

data class TunnelStats(val txBytes: Long, val rxBytes: Long)

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
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()
    private val _stats = MutableStateFlow(TunnelStats(0, 0))
    val stats: StateFlow<TunnelStats> = _stats.asStateFlow()

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
                if (running && !wasRunning) {
                    (context as? Activity)?.let { AdsManager.showAfterConnect(it) }
                }
                wasRunning = running
                kotlinx.coroutines.delay(1000)
            }
        }
    }

    /** Call from an Activity's registerForActivityResult(StartActivityForResult()). */
    fun prepareIntent(): Intent? = VpnService.prepare(context)

    fun connect(profile: ServerProfile, launcher: ActivityResultLauncher<Intent>) {
        val prepare = VpnService.prepare(context)
        if (prepare != null) {
            launcher.launch(prepare)
        } else {
            startService(profile)
        }
    }

    fun startService(profile: ServerProfile) {
        settings.selectedProfileId = profile.id
        store.saveSettings(settings)
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

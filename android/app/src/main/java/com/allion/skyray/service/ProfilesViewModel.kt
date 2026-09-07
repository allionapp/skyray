package com.allion.skyray.service

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.allion.skyray.core.RaycoreBridge
import com.allion.skyray.core.ShareLinkParser
import com.allion.skyray.core.SingboxConfigBuilder
import com.allion.skyray.core.XrayConfigBuilder
import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.CoreKind
import com.allion.skyray.data.ProfileStore
import com.allion.skyray.data.ServerProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Result of checking one pasted link end to end, mirroring AddConfigFlow.CheckRunner on iOS. */
sealed class CheckStep {
    object Parsing : CheckStep()
    data class LinkRead(val profile: ServerProfile) : CheckStep()
    data class Testing(val profile: ServerProfile) : CheckStep()
    data class Reached(val profile: ServerProfile, val latencyMs: Int?) : CheckStep()
    data class Failed(val reason: String) : CheckStep()
}

class ProfilesViewModel(private val store: ProfileStore) : ViewModel() {
    private val _profiles = MutableStateFlow(store.loadProfiles())
    val profiles: StateFlow<List<ServerProfile>> = _profiles.asStateFlow()

    private val _isPinging = MutableStateFlow(false)
    val isPinging: StateFlow<Boolean> = _isPinging.asStateFlow()

    var message: String? = null

    fun selectedProfile(settings: com.allion.skyray.data.AppSettings): ServerProfile? =
        profiles.value.firstOrNull { it.id == settings.selectedProfileId } ?: profiles.value.firstOrNull()

    private fun persist() = store.saveProfiles(_profiles.value)

    fun add(profile: ServerProfile) {
        _profiles.value = _profiles.value.filterNot {
            it.address == profile.address && it.port == profile.port && it.protocolName == profile.protocolName
        } + profile
        persist()
    }

    fun delete(profile: ServerProfile) {
        _profiles.value = _profiles.value.filterNot { it.id == profile.id }
        persist()
    }

    fun deleteAll() {
        _profiles.value = emptyList()
        persist()
    }

    fun deleteUnreachable() {
        _profiles.value = _profiles.value.filterNot { (it.latencyMs ?: 0) < 0 }
        persist()
    }

    fun update(profile: ServerProfile) {
        _profiles.value = _profiles.value.map { if (it.id == profile.id) profile else it }
        persist()
    }

    fun sortByLatency() {
        _profiles.value = _profiles.value.sortedBy { it.latencyMs ?: Int.MAX_VALUE }
        persist()
    }

    fun selectFastest(): ServerProfile? {
        val fastest = _profiles.value.filter { (it.latencyMs ?: -1) >= 0 }.minByOrNull { it.latencyMs!! }
        return fastest
    }

    /** Runs the same real, narrated check the iOS add-config flow shows: parse -> reach -> measure. */
    fun checkLink(text: String, onStep: (CheckStep) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            onStep(CheckStep.Parsing)
            val outcome = ShareLinkParser.parse(text)
            val profile = outcome.profiles.firstOrNull()
            if (profile == null) {
                onStep(CheckStep.Failed(outcome.failures.firstOrNull()?.reason ?: "Could not read this link"))
                return@launch
            }
            onStep(CheckStep.LinkRead(profile))
            onStep(CheckStep.Testing(profile))
            try {
                if (profile.core == CoreKind.xray) {
                    val config = XrayConfigBuilder.runtimeConfig(profile.outboundJson, hasGeoData = true)
                    RaycoreBridge.testXrayConfig(config)
                    val ping = RaycoreBridge.pingBatch(listOf(JSONObject(profile.outboundJson)), AppConstants.PING_TIMEOUT_SECONDS, AppConstants.PING_URL).firstOrNull()
                    val latency = if (ping?.success == true) ping.delayMs else null
                    profile.latencyMs = latency
                    onStep(CheckStep.Reached(profile, latency))
                } else {
                    val config = SingboxConfigBuilder.runtimeConfig(profile.outboundJson)
                    RaycoreBridge.testSingboxConfig(config)
                    val ping = RaycoreBridge.singboxPing(profile.outboundJson, AppConstants.PING_URL_PLAIN, AppConstants.PING_TIMEOUT_SECONDS * 1000)
                    profile.latencyMs = if (ping.success) ping.delayMs else null
                    onStep(CheckStep.Reached(profile, profile.latencyMs))
                }
            } catch (e: Exception) {
                onStep(CheckStep.Reached(profile, null))
            }
            add(profile)
        }
    }

    fun tcpPing(profile: ServerProfile) {
        viewModelScope.launch(Dispatchers.IO) {
            val result = runCatching {
                java.net.Socket().use { socket ->
                    val start = System.currentTimeMillis()
                    socket.connect(java.net.InetSocketAddress(profile.address, profile.port), AppConstants.PING_TIMEOUT_SECONDS * 1000)
                    (System.currentTimeMillis() - start).toInt()
                }
            }.getOrNull()
            val updated = profile.copy(latencyMs = result ?: -1)
            update(updated)
        }
    }

    fun pingAll() {
        viewModelScope.launch(Dispatchers.IO) {
            _isPinging.value = true
            val current = _profiles.value
            for (p in current) {
                withContext(Dispatchers.IO) { tcpPingSync(p) }
            }
            _isPinging.value = false
        }
    }

    private fun tcpPingSync(profile: ServerProfile) {
        val result = runCatching {
            java.net.Socket().use { socket ->
                val start = System.currentTimeMillis()
                socket.connect(java.net.InetSocketAddress(profile.address, profile.port), AppConstants.PING_TIMEOUT_SECONDS * 1000)
                (System.currentTimeMillis() - start).toInt()
            }
        }.getOrNull()
        update(profile.copy(latencyMs = result ?: -1))
    }
}

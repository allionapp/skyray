package com.allion.skyray.service

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.allion.skyray.core.RaycoreBridge
import com.allion.skyray.core.ShareLinkParser
import com.allion.skyray.core.SingboxConfigBuilder
import com.allion.skyray.core.SubscriptionFetcher
import com.allion.skyray.core.SubscriptionLinkResolver
import com.allion.skyray.core.XrayConfigBuilder
import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.CoreKind
import com.allion.skyray.data.ProfileStore
import com.allion.skyray.data.ServerProfile
import com.allion.skyray.data.SubscriptionInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Result of checking one pasted link end to end, mirroring AddConfigFlow.CheckRunner on iOS. */
sealed class CheckStep {
    object Downloading : CheckStep()
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

    private val _subscriptions = MutableStateFlow(store.loadSubscriptions())
    val subscriptions: StateFlow<List<SubscriptionInfo>> = _subscriptions.asStateFlow()

    private val _isRefreshingSubscription = MutableStateFlow(false)
    val isRefreshingSubscription: StateFlow<Boolean> = _isRefreshingSubscription.asStateFlow()

    /** The plan a given server was imported from, so Home can show its quota. */
    fun subscriptionFor(profile: ServerProfile?): SubscriptionInfo? =
        profile?.subscriptionUrl?.let { url -> _subscriptions.value.firstOrNull { it.url == url } }

    var message: String? = null

    fun selectedProfile(settings: com.allion.skyray.data.AppSettings): ServerProfile? =
        profiles.value.firstOrNull { it.id == settings.selectedProfileId } ?: profiles.value.firstOrNull()

    private fun persist() = store.saveProfiles(_profiles.value)

    fun add(profile: ServerProfile) {
        // Identity is the outbound itself: one subscription often carries several
        // servers on the same host and port that differ only by transport.
        _profiles.value = _profiles.value.filterNot { it.outboundJson == profile.outboundJson } + profile
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
            // A subscription URL (or a panel's launcher deep link) has to be
            // downloaded first; its body is what actually holds the share links.
            val subscription = if (ShareLinkParser.containsShareLink(text)) null else SubscriptionLinkResolver.resolve(text)
            val body: String
            if (subscription != null) {
                onStep(CheckStep.Downloading)
                try {
                    val response = SubscriptionFetcher.fetch(subscription.url)
                    body = response.body
                    // The plan's quota and expiry ride along in the response headers.
                    updateSubscriptionInfo(subscription.url, response.headers)
                } catch (e: Exception) {
                    onStep(CheckStep.Failed(e.message ?: "Download failed"))
                    return@launch
                }
            } else {
                body = text
            }

            onStep(CheckStep.Parsing)
            val outcome = ShareLinkParser.parse(body, subscription?.url)
            val profile = outcome.profiles.firstOrNull()
            if (profile == null) {
                onStep(CheckStep.Failed(outcome.failures.firstOrNull()?.reason ?: "Could not read this link"))
                return@launch
            }
            // A subscription carries the provider's whole server list, not one server.
            outcome.profiles.drop(1).forEach { add(it) }
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

    /**
     * Reads the plan's state out of the panel's response headers
     * (`subscription-userinfo`, `profile-title`, `announce`, ...), the same set
     * ProfilesViewModel.updateSubscriptionInfo reads on iOS.
     */
    private fun updateSubscriptionInfo(url: String, headers: Map<String, String>) {
        val info = _subscriptions.value.firstOrNull { it.url == url }?.copy() ?: SubscriptionInfo(url = url)
        info.lastUpdated = System.currentTimeMillis()

        headers["subscription-userinfo"]?.let { raw ->
            val values = raw.split(";").mapNotNull { part ->
                val kv = part.split("=", limit = 2)
                if (kv.size == 2) kv[0].trim().lowercase() to kv[1].trim().toLongOrNull() else null
            }.toMap()
            val upload = values["upload"]
            val download = values["download"]
            if (upload != null || download != null) info.used = (upload ?: 0) + (download ?: 0)
            values["total"]?.let { info.total = it }
            values["expire"]?.let { info.expireEpochSeconds = it.takeIf { s -> s > 0 } }
        }
        headers["profile-title"]?.let { info.title = decodeHeader(it) }
        headers["profile-update-interval"]?.trim()?.toIntOrNull()?.let { info.updateIntervalHours = it }
        headers["profile-web-page-url"]?.trim()?.let { info.webPageUrl = it }
        headers["support-url"]?.trim()?.let { info.supportUrl = it }
        headers["announce"]?.let { info.announce = decodeHeader(it) }

        _subscriptions.value = _subscriptions.value.filterNot { it.url == url } + info
        store.saveSubscriptions(_subscriptions.value)
    }

    private fun decodeHeader(value: String): String =
        if (value.startsWith("base64:")) ShareLinkParser.decodeBase64(value.removePrefix("base64:")) ?: value else value

    /** Re-reads usage and expiry from the provider, and re-imports the server list. */
    fun refreshSubscription(url: String, onDone: (String?) -> Unit = {}) {
        viewModelScope.launch(Dispatchers.IO) {
            _isRefreshingSubscription.value = true
            try {
                val response = SubscriptionFetcher.fetch(url)
                updateSubscriptionInfo(url, response.headers)
                ShareLinkParser.parse(response.body, url).profiles.forEach { add(it) }
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message ?: "Update failed")
            } finally {
                _isRefreshingSubscription.value = false
            }
        }
    }

    /** Refreshes plans whose own interval (or the app-wide one) has elapsed. */
    fun refreshStaleSubscriptions(defaultHours: Int) {
        val now = System.currentTimeMillis()
        _subscriptions.value.forEach { sub ->
            val hours = sub.updateIntervalHours ?: defaultHours
            if (hours > 0 && now - sub.lastUpdated > hours * 3600_000L) refreshSubscription(sub.url)
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

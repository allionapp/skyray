package com.allion.skyray.service

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.allion.skyray.core.ProbeResult
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
    /** A subscription went in whole; the result screen tests its servers itself. */
    data class SubscriptionAdded(val url: String, val count: Int) : CheckStep()
}

class ProfilesViewModel(private val store: ProfileStore) : ViewModel() {
    private val _profiles = MutableStateFlow(store.loadProfiles())
    val profiles: StateFlow<List<ServerProfile>> = _profiles.asStateFlow()

    private val _isPinging = MutableStateFlow(false)
    val isPinging: StateFlow<Boolean> = _isPinging.asStateFlow()

    private val _subscriptions = MutableStateFlow(store.loadSubscriptions())
    val subscriptions: StateFlow<List<SubscriptionInfo>> = _subscriptions.asStateFlow()

    /** The subscription being downloaded right now, so only its row says so. */
    private val _updatingSubscriptionUrl = MutableStateFlow<String?>(null)
    val updatingSubscriptionUrl: StateFlow<String?> = _updatingSubscriptionUrl.asStateFlow()

    private val _selectedId = MutableStateFlow(store.selectedProfileId)
    val selectedId: StateFlow<String?> = _selectedId.asStateFlow()

    /** Connect to whichever server tests fastest instead of a fixed choice. */
    private val _isAutomatic = MutableStateFlow(store.automaticSelection)
    val isAutomatic: StateFlow<Boolean> = _isAutomatic.asStateFlow()

    private val _pingProgress = MutableStateFlow(0 to 0)
    val pingProgress: StateFlow<Pair<Int, Int>> = _pingProgress.asStateFlow()
    private var lastPingAll = 0L

    init {
        // Self-heal state left behind by bulk server deletes in older builds.
        dropEmptySubscriptions()
    }

    var message: String? = null

    fun selectedProfile(): ServerProfile? =
        profiles.value.firstOrNull { it.id == _selectedId.value } ?: profiles.value.firstOrNull()

    fun select(profile: ServerProfile) {
        _selectedId.value = profile.id
        store.selectedProfileId = profile.id
    }

    /** The free Cloudflare WARP entry, added once and kept like any other server. */
    fun addWarp(name: String): ServerProfile {
        _profiles.value.firstOrNull { it.core == CoreKind.warp }?.let { return it }
        val profile = ServerProfile(
            name = name,
            protocolName = "warp",
            address = "cloudflare",
            port = 443,
            outboundJson = "{}",
            core = CoreKind.warp,
        )
        _profiles.value = _profiles.value + profile
        persist()
        return profile
    }

    fun hasWarp(): Boolean = _profiles.value.any { it.core == CoreKind.warp }

    /** A server the user picked by hand, which ends automatic selection. */
    fun choose(profile: ServerProfile) {
        setAutomatic(false)
        select(profile)
    }

    fun setAutomatic(on: Boolean) {
        _isAutomatic.value = on
        store.automaticSelection = on
    }

    /** Latencies go stale as networks change; older than this they are retested. */
    val latenciesAreFresh: Boolean
        get() = System.currentTimeMillis() - lastPingAll < 10 * 60_000L

    /**
     * The server to connect to. In automatic mode that is the fastest one,
     * retesting first unless a test ran in the last few minutes.
     */
    suspend fun connectionTarget(): ServerProfile? {
        val selected = selectedProfile()
        // WARP is a deliberate choice, not something automatic mode overrides.
        if (selected?.core == CoreKind.warp) return selected
        if (!_isAutomatic.value || _profiles.value.count { it.core != CoreKind.warp } < 2) return selected
        if (!latenciesAreFresh) pingAll()
        return selectFastest()?.also { select(it) } ?: selected
    }

    data class Group(val title: String, val url: String?, val servers: List<ServerProfile>)

    companion object {
        /** Stands in for a subscription URL so WARP gets its own group. */
        const val WARP_GROUP = "warp://free"
    }

    /** Servers grouped by the subscription they came from; hand-added ones last. */
    fun groups(profiles: List<ServerProfile>, subscriptions: List<SubscriptionInfo>): List<Group> {
        val byUrl = profiles.groupBy { if (it.core == CoreKind.warp) WARP_GROUP else it.subscriptionUrl }
        // WARP first, then the subscriptions, then whatever was added by hand.
        return byUrl.keys.sortedBy { if (it == WARP_GROUP) 0 else if (it != null) 1 else 2 }.map { url ->
            val title = when {
                url == null || url == WARP_GROUP -> ""
                else -> subscriptions.firstOrNull { it.url == url }?.title ?: android.net.Uri.parse(url).host ?: url
            }
            Group(title, url, byUrl[url].orEmpty())
        }
    }

    private fun persist() = store.saveProfiles(_profiles.value)

    fun add(profile: ServerProfile) {
        // Identity is the outbound itself: one subscription often carries several
        // servers on the same host and port that differ only by transport. A
        // refresh brings the same server back; what the probes learnt stays.
        val existing = _profiles.value.firstOrNull { it.outboundJson == profile.outboundJson }
        val merged = if (existing == null) profile else profile.copy(
            id = existing.id,
            latencyMs = profile.latencyMs ?: existing.latencyMs,
            exitIp = profile.exitIp ?: existing.exitIp,
            country = profile.country ?: existing.country,
        )
        _profiles.value = _profiles.value.filterNot { it.outboundJson == profile.outboundJson } + merged
        persist()
    }

    fun delete(profile: ServerProfile) {
        _profiles.value = _profiles.value.filterNot { it.id == profile.id }
        persist()
        dropEmptySubscriptions()
    }

    fun deleteAll() {
        _profiles.value = emptyList()
        persist()
        dropEmptySubscriptions()
    }

    fun deleteUnreachable() {
        _profiles.value = _profiles.value.filterNot { (it.latencyMs ?: 0) < 0 }
        persist()
        dropEmptySubscriptions()
    }

    /** A link whose servers are all gone is dead weight, and reads as "0 servers". */
    private fun dropEmptySubscriptions() {
        val live = _profiles.value.mapNotNull { it.subscriptionUrl }.toSet()
        val kept = _subscriptions.value.filter { it.url in live }
        if (kept.size != _subscriptions.value.size) {
            _subscriptions.value = kept
            store.saveSubscriptions(kept)
        }
    }

    fun update(profile: ServerProfile) {
        _profiles.value = _profiles.value.map { if (it.id == profile.id) profile else it }
        persist()
    }

    fun sortByLatency() {
        _profiles.value = _profiles.value.sortedBy { it.latencyMs ?: Int.MAX_VALUE }
        persist()
    }

    fun selectFastest(): ServerProfile? =
        _profiles.value.filter { (it.latencyMs ?: -1) > 0 }.minByOrNull { it.latencyMs!! }

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
            if (subscription != null) {
                outcome.profiles.forEach { add(it) }
                onStep(CheckStep.SubscriptionAdded(subscription.url, outcome.profiles.size))
                return@launch
            }
            onStep(CheckStep.LinkRead(profile))
            onStep(CheckStep.Testing(profile))
            try {
                if (profile.core == CoreKind.xray) {
                    RaycoreBridge.testXrayConfig(XrayConfigBuilder.runtimeConfig(profile.outboundJson, hasGeoData = true))
                } else {
                    RaycoreBridge.testSingboxConfig(SingboxConfigBuilder.runtimeConfig(profile.outboundJson))
                }
                val probe = RaycoreBridge.probeBatch(listOf(profile)).first()
                profile.latencyMs = if (probe.success) probe.delayMs else null
                if (probe.success) {
                    profile.exitIp = probe.exitIp
                    profile.country = probe.country
                }
                onStep(CheckStep.Reached(profile, profile.latencyMs))
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
            _updatingSubscriptionUrl.value = url
            try {
                val response = SubscriptionFetcher.fetch(url)
                updateSubscriptionInfo(url, response.headers)
                ShareLinkParser.parse(response.body, url).profiles.forEach { add(it) }
                onDone(null)
            } catch (e: Exception) {
                onDone(e.message ?: "Update failed")
            } finally {
                _updatingSubscriptionUrl.value = null
            }
        }
    }

    /** Drops a subscription along with every server it brought in. */
    fun removeSubscription(url: String) {
        _subscriptions.value = _subscriptions.value.filterNot { it.url == url }
        store.saveSubscriptions(_subscriptions.value)
        _profiles.value = _profiles.value.filterNot { it.subscriptionUrl == url }
        persist()
    }

    /** TCP handshake time to the server itself, or -1. */
    suspend fun tcpLatency(profile: ServerProfile): Int = withContext(Dispatchers.IO) {
        // A DNS tunnel answers no TCP handshake; only a probe can test it.
        if (!profile.hasDialableEndpoint) return@withContext 0
        runCatching {
            java.net.Socket().use { socket ->
                val start = System.currentTimeMillis()
                socket.connect(java.net.InetSocketAddress(profile.address, profile.port), 5000)
                (System.currentTimeMillis() - start).toInt()
            }
        }.getOrDefault(-1)
    }

    fun refreshAllSubscriptions() {
        _subscriptions.value.forEach { refreshSubscription(it.url) }
    }

    /** How many servers a given subscription contributed. */
    fun serverCount(url: String): Int = _profiles.value.count { it.subscriptionUrl == url }

    /** Refreshes plans whose own interval (or the app-wide one) has elapsed. */
    fun refreshStaleSubscriptions(defaultHours: Int) {
        val now = System.currentTimeMillis()
        _subscriptions.value.forEach { sub ->
            val hours = sub.updateIntervalHours ?: defaultHours
            if (hours > 0 && now - sub.lastUpdated > hours * 3600_000L) refreshSubscription(sub.url)
        }
    }

    /**
     * Probes every server, five per core instance and three instances at a
     * time. Each probe records the delay and where the traffic comes out.
     * [subset] limits the test, e.g. to the servers a subscription just brought in.
     */
    suspend fun pingAll(subset: List<ServerProfile>? = null) {
        // WARP has no outbound of its own, so neither core can test it.
        val snapshot = (subset ?: _profiles.value).filterNot { it.core == CoreKind.warp }
        if (_isPinging.value || snapshot.isEmpty()) return
        _isPinging.value = true
        _pingProgress.value = 0 to snapshot.size
        try {
            val gate = kotlinx.coroutines.sync.Semaphore(3)
            kotlinx.coroutines.coroutineScope {
                snapshot.chunked(AppConstants.PING_BATCH_SIZE).forEach { chunk ->
                    launch(Dispatchers.IO) {
                        gate.acquire()
                        try {
                            record(chunk.map { it.id }.zip(RaycoreBridge.probeBatch(chunk)))
                        } finally {
                            gate.release()
                        }
                    }
                }
            }
            if (subset == null) lastPingAll = System.currentTimeMillis()
            persist()
        } finally {
            _isPinging.value = false
        }
    }

    /**
     * Writes the probes' findings onto their servers. A failed probe keeps the
     * last known exit: the server is down now, not somewhere else.
     */
    @Synchronized
    private fun record(results: List<Pair<String, ProbeResult>>) {
        val byId = results.toMap()
        _profiles.value = _profiles.value.map { p ->
            val r = byId[p.id] ?: return@map p
            if (r.success) p.copy(latencyMs = r.delayMs, exitIp = r.exitIp ?: p.exitIp, country = r.country ?: p.country)
            else p.copy(latencyMs = -1)
        }
        val (done, total) = _pingProgress.value
        _pingProgress.value = (done + results.size) to total
    }

    /** Clears latencies so a fresh test shows as pending rather than stale numbers. */
    fun clearLatencies(ids: Set<String>) {
        _profiles.value = _profiles.value.map { if (it.id in ids) it.copy(latencyMs = null) else it }
    }
}

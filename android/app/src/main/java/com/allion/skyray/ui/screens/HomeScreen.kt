package com.allion.skyray.ui.screens

import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
import com.allion.skyray.data.CountryLabel
import com.allion.skyray.data.SubscriptionInfo
import com.allion.skyray.service.ProfilesViewModel
import com.allion.skyray.service.VpnManager
import com.allion.skyray.ui.theme.Sky
import com.allion.skyray.ui.theme.SkyRule
import com.allion.skyray.ui.theme.skyBody
import com.allion.skyray.ui.theme.skyHeading
import com.allion.skyray.ui.theme.skyMono
import com.allion.skyray.ui.theme.skySemibold
import kotlinx.coroutines.launch

/**
 * Home: one button and one choice. The big button turns the tunnel on and off;
 * the card under it says which server that will use and opens the picker.
 */
@Composable
fun HomeScreen(
    vpnManager: VpnManager,
    profilesViewModel: ProfilesViewModel,
    vpnPermissionLauncher: ActivityResultLauncher<Intent>,
    onAddConfig: () -> Unit,
    onServers: () -> Unit,
    onSettings: () -> Unit,
) {
    val isConnected by vpnManager.isConnected.collectAsState()
    val lastError by vpnManager.lastError.collectAsState()
    val notice by vpnManager.notice.collectAsState()
    val profiles by profilesViewModel.profiles.collectAsState()
    val scope = rememberCoroutineScope()
    // The service reports only running or not, so the wait in between is tracked here.
    var connecting by remember { mutableStateOf(false) }
    var findingFastest by remember { mutableStateOf(false) }
    LaunchedEffect(isConnected, lastError) { if (isConnected || lastError != null) connecting = false }
    LaunchedEffect(connecting) {
        if (connecting) { kotlinx.coroutines.delay(30_000); connecting = false }
    }

    val onField = isConnected
    Column(Modifier.fillMaxSize().background(if (onField) Sky.accent else Sky.ground)) {
        Row(
            Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("SkyRay", style = skyHeading(17), color = if (onField) Sky.onField else Sky.ink)
            Spacer(Modifier.weight(1f))
            val tint = if (onField) Sky.onField.copy(alpha = 0.9f) else Sky.ink.copy(alpha = 0.75f)
            IconButton(onClick = onAddConfig) { Icon(Icons.Filled.Add, stringResource(R.string.home_add_config), tint = tint) }
            IconButton(onClick = onSettings) { Icon(Icons.Filled.Settings, stringResource(R.string.settings_title), tint = tint) }
        }
        SkyRule(onField = onField)

        Column(
            Modifier.weight(1f).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            PowerButton(
                onField = onField,
                working = findingFastest || connecting,
                empty = profiles.isEmpty(),
                onClick = {
                    when {
                        isConnected || connecting -> { vpnManager.disconnect(); connecting = false }
                        profiles.isEmpty() -> onAddConfig()
                        else -> scope.launch {
                            findingFastest = profilesViewModel.isAutomatic.value && profiles.size > 1 && !profilesViewModel.latenciesAreFresh
                            val target = profilesViewModel.connectionTarget()
                            findingFastest = false
                            if (target != null) {
                                connecting = true
                                vpnManager.connect(target, vpnPermissionLauncher)
                            }
                        }
                    }
                },
            )
            Spacer(Modifier.height(28.dp))
            val status = when {
                findingFastest -> stringResource(R.string.home_finding_fastest)
                connecting -> stringResource(R.string.home_connecting)
                isConnected -> stringResource(R.string.home_connected)
                profiles.isEmpty() -> stringResource(R.string.home_add_to_start)
                else -> stringResource(R.string.home_tap_to_connect)
            }
            Text(status, style = skyHeading(22), color = if (onField) Sky.onField else Sky.ink, textAlign = TextAlign.Center)
            if (isConnected) {
                SessionTimer(vpnManager)
                ExitLine(vpnManager)
                LiveSpeeds(vpnManager)
            } else if (profiles.isEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text(stringResource(R.string.home_provider_hint), style = skyBody(14), color = Sky.muted(0.6f), textAlign = TextAlign.Center)
            } else if (!connecting && !findingFastest) {
                // Play requires the ad to be announced before it interrupts anything.
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.home_ad_hint), style = skyBody(13), color = Sky.muted(0.55f), textAlign = TextAlign.Center)
            }
            if (!isConnected && !connecting) {
                (notice ?: lastError)?.let {
                    Spacer(Modifier.height(14.dp))
                    Text(it, style = skyBody(13), color = Sky.accentDeep, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
                }
            }
        }

        if (profiles.isNotEmpty()) {
            ServerCard(profilesViewModel, onField, onServers, Modifier.padding(24.dp))
        }
    }
}

@Composable
private fun PowerButton(onField: Boolean, working: Boolean, empty: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.95f else 1f, label = "press")
    Box(
        Modifier
            .size(204.dp)
            .scale(scale)
            .border(10.dp, if (onField) Sky.onField.copy(alpha = 0.35f) else Sky.ink.copy(alpha = 0.12f), CircleShape)
            .padding(10.dp)
            .shadow(if (onField) 18.dp else 10.dp, CircleShape)
            .background(if (onField) Sky.onField else Sky.paper, CircleShape)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        val tint = if (onField) Sky.accent else Sky.primary
        if (working) {
            CircularProgressIndicator(Modifier.size(52.dp), color = tint, strokeWidth = 4.dp)
        } else {
            Icon(
                if (empty) Icons.Filled.Add else Icons.Filled.PowerSettingsNew,
                contentDescription = stringResource(if (onField) R.string.home_disconnect else R.string.home_connect),
                tint = tint,
                modifier = Modifier.size(76.dp),
            )
        }
    }
}

@Composable
private fun SessionTimer(vpnManager: VpnManager) {
    val since by vpnManager.connectedSinceMillis.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(since) {
        while (since > 0L) { now = System.currentTimeMillis(); kotlinx.coroutines.delay(1000) }
    }
    if (since > 0L) {
        Spacer(Modifier.height(6.dp))
        Text(formatDuration(now - since), style = skyMono(14, medium = true), color = Sky.onField.copy(alpha = 0.9f))
    }
}

/** The exit as Cloudflare saw it through the tunnel: proof the traffic flows, and where. */
@Composable
private fun ExitLine(vpnManager: VpnManager) {
    val exit by vpnManager.exitInfo.collectAsState()
    exit?.let { info ->
        val code = info.country
        val flag = code?.let { CountryLabel.flag(it) }
        val line = if (code != null && flag != null) "$flag ${CountryLabel.name(code)} · ${info.ip}" else info.ip
        Spacer(Modifier.height(4.dp))
        Text(ltr(line), style = skyMono(12), color = Sky.onField.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun LiveSpeeds(vpnManager: VpnManager) {
    val stats by vpnManager.stats.collectAsState()
    Spacer(Modifier.height(16.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
        listOf(Icons.Filled.ArrowDownward to stats.downSpeed, Icons.Filled.ArrowUpward to stats.upSpeed).forEach { (icon, speed) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, tint = Sky.onField, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(4.dp))
                Text(ltr(formatSpeed(speed)), style = skyMono(13, medium = true), color = Sky.onField)
            }
        }
    }
}

@Composable
private fun ServerCard(profilesViewModel: ProfilesViewModel, onField: Boolean, onOpen: () -> Unit, modifier: Modifier) {
    val profiles by profilesViewModel.profiles.collectAsState()
    val subscriptions by profilesViewModel.subscriptions.collectAsState()
    val automatic by profilesViewModel.isAutomatic.collectAsState()
    val selectedId by profilesViewModel.selectedId.collectAsState()
    val selected = profiles.firstOrNull { it.id == selectedId } ?: profiles.firstOrNull()
    // With a single server there is nothing to choose between.
    val showAutomatic = automatic && !onField && profiles.size > 1
    val ink = if (onField) Sky.onField else Sky.ink
    val accent = if (onField) Sky.onField else Sky.primary

    Column(
        modifier
            .fillMaxWidth()
            .background(if (onField) Sky.onField.copy(alpha = 0.12f) else Sky.paper)
            .border(BorderStroke(1.dp, if (onField) Sky.onField.copy(alpha = 0.4f) else Sky.dividerLight))
            .clickable(onClick = onOpen)
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).background(accent.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                Icon(if (showAutomatic) Icons.Filled.Bolt else Icons.Filled.Dns, null, tint = accent, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    if (showAutomatic) stringResource(R.string.servers_automatic) else selected?.name.orEmpty().middleTrim(26),
                    style = skySemibold(16), color = ink, maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val detail = if (showAutomatic) stringResource(R.string.home_picks_best_of, profiles.size)
                else listOfNotNull(selected?.protocolName?.uppercase(), selected?.latencyMs?.let { if (it < 0) "—" else ltr("$it ms") }).joinToString(" · ")
                Text(detail, style = skyMono(11), color = if (onField) Sky.onField.copy(alpha = 0.8f) else Sky.muted(0.55f), maxLines = 1)
            }
            Icon(Icons.Filled.UnfoldMore, null, tint = if (onField) Sky.onField.copy(alpha = 0.8f) else Sky.muted(0.5f))
        }
        // In automatic mode no server is chosen yet, so the first plan stands in;
        // a hand-picked server (WARP included) shows only its own plan.
        val subUrl = if (showAutomatic) profiles.firstOrNull { it.subscriptionUrl != null }?.subscriptionUrl else selected?.subscriptionUrl
        subscriptions.firstOrNull { it.url == subUrl }?.let { sub ->
            if (sub.hasQuota || sub.expireEpochSeconds != null) {
                Spacer(Modifier.height(14.dp))
                QuotaLine(sub, onField)
            }
        }
    }
}

@Composable
private fun QuotaLine(sub: SubscriptionInfo, onField: Boolean) {
    if (sub.hasQuota) {
        val fraction = ((sub.used ?: 0).toFloat() / (sub.total ?: 1).toFloat()).coerceIn(0f, 1f)
        Box(Modifier.fillMaxWidth().height(4.dp).background((if (onField) Sky.onField else Sky.ink).copy(alpha = 0.15f))) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(fraction).background(if (onField) Sky.onField else Sky.accent))
        }
        Spacer(Modifier.height(6.dp))
    }
    val parts = mutableListOf<String>()
    if (sub.hasQuota) sub.remaining?.let { parts += stringResource(R.string.home_plan_remaining, formatBytes(it)) }
    sub.expireEpochSeconds?.let { seconds ->
        val date = java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(seconds * 1000))
        parts += if (sub.isExpired) stringResource(R.string.home_plan_expired, date) else stringResource(R.string.home_plan_expires, date)
    }
    Text(
        parts.joinToString(" · "),
        style = skyMono(11), maxLines = 1,
        color = when {
            onField -> Sky.onField.copy(alpha = 0.85f)
            sub.isExpired || sub.expiresSoon -> Sky.accentDeep
            else -> Sky.muted(0.6f)
        },
    )
}

internal fun formatDuration(millis: Long): String {
    val total = (millis / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(java.util.Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(java.util.Locale.US, "%d:%02d", m, s)
}

internal fun formatSpeed(bytesPerSecond: Long): String =
    if (bytesPerSecond >= 1024 * 1024) String.format(java.util.Locale.US, "%.1f MB/s", bytesPerSecond / 1048576.0)
    else String.format(java.util.Locale.US, "%d KB/s", bytesPerSecond / 1024)

internal fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    val units = listOf("KB", "MB", "GB", "TB")
    var value = bytes.toDouble() / 1024
    var unit = 0
    while (value >= 1024 && unit < units.lastIndex) {
        value /= 1024
        unit++
    }
    return String.format(java.util.Locale.US, if (value >= 100) "%.0f %s" else "%.1f %s", value, units[unit])
}

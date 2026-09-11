package com.allion.skyray.ui.screens

import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Power
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
import com.allion.skyray.data.SubscriptionInfo
import com.allion.skyray.service.ProfilesViewModel
import com.allion.skyray.service.VpnManager
import com.allion.skyray.ui.theme.Sky
import com.allion.skyray.ui.theme.SkyRule
import com.allion.skyray.ui.theme.skyBody
import com.allion.skyray.ui.theme.skyHeading
import com.allion.skyray.ui.theme.skyMono
import com.allion.skyray.ui.theme.skySemibold

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
    val profiles by profilesViewModel.profiles.collectAsState()
    val selected = profilesViewModel.selectedProfile(vpnManager.settings)
    val background = if (isConnected) Sky.accent else Sky.ground

    Column(Modifier.fillMaxSize().background(background)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("SkyRay", style = skyHeading(17), color = if (isConnected) Sky.onField else Sky.ink)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onSettings) {
                Icon(Icons.Filled.Settings, contentDescription = stringResourceCompat(R.string.settings_title), tint = if (isConnected) Sky.onField.copy(alpha = 0.85f) else Sky.muted(0.6f))
            }
        }
        SkyRule(onField = isConnected)

        if (isConnected) {
            ConnectedBody(vpnManager, profilesViewModel, selected?.name ?: "")
        } else if (profiles.isEmpty()) {
            EmptyBody(onAddConfig)
        } else {
            OffBody(vpnManager, profilesViewModel, vpnPermissionLauncher, onAddConfig, onServers)
        }
    }
}

@Composable
private fun EmptyBody(onAddConfig: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.SpaceBetween) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Box(
                Modifier.size(132.dp).border(2.dp, Sky.ink.copy(alpha = 0.25f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Power, contentDescription = null, tint = Sky.ink.copy(alpha = 0.3f), modifier = Modifier.size(42.dp))
            }
            Spacer(Modifier.height(28.dp))
            Text(stringResourceCompat(R.string.home_no_server_title), style = skyHeading(32), color = Sky.ink)
            Spacer(Modifier.height(12.dp))
            Text(
                stringResourceCompat(R.string.home_no_server_body),
                style = skyBody(15), color = Sky.muted(0.65f), modifier = Modifier.widthIn(max = 300.dp),
            )
        }
        SkyRule()
        Spacer(Modifier.height(16.dp))
        OutlinedButton(
            onClick = onAddConfig,
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RectangleShape,
            border = androidx.compose.foundation.BorderStroke(1.dp, Sky.divider),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = Sky.ink)
            Spacer(Modifier.width(8.dp))
            Text(stringResourceCompat(R.string.home_add_config), style = skyHeading(15), color = Sky.ink)
        }
    }
}

@Composable
private fun OffBody(
    vpnManager: VpnManager,
    profilesViewModel: ProfilesViewModel,
    launcher: ActivityResultLauncher<Intent>,
    onAddConfig: () -> Unit,
    onServers: () -> Unit,
) {
    val selected = profilesViewModel.selectedProfile(vpnManager.settings)
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 24.dp).padding(top = 34.dp)) {
            Text(stringResourceCompat(R.string.home_not_connected).uppercase(), style = skySemibold(11), color = Sky.muted(0.5f))
            Spacer(Modifier.height(14.dp))
            Text(stringResourceCompat(R.string.home_off), style = skyHeading(44), color = Sky.ink)
            Spacer(Modifier.height(14.dp))
            Text(stringResourceCompat(R.string.home_off_body), style = skyBody(15), color = Sky.muted(0.65f), modifier = Modifier.widthIn(max = 300.dp))
        }
        Spacer(Modifier.height(34.dp))
        SkyRule()
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(4.dp).height(48.dp).background(Sky.ink))
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(stringResourceCompat(R.string.home_selected_server).uppercase(), style = skySemibold(10), color = Sky.muted(0.5f))
                Text(selected?.name ?: "", style = skySemibold(16), color = Sky.ink, maxLines = 1)
                Text(selected?.let { "${it.address}:${it.port}" } ?: "", style = skyMono(11), color = Sky.muted(0.55f), maxLines = 1)
            }
            OutlinedButton(onClick = onServers, shape = RectangleShape, border = androidx.compose.foundation.BorderStroke(1.dp, Sky.divider)) {
                Text(stringResourceCompat(R.string.home_change), style = skyHeading(12), color = Sky.ink)
            }
        }
        SkyRule()
        profilesViewModel.subscriptionFor(selected)?.let { subscription ->
            QuotaRow(subscription, profilesViewModel)
            SkyRule()
        }
        Box(Modifier.weight(1f))
        Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                onClick = { selected?.let { vpnManager.connect(it, launcher) } },
                modifier = Modifier.fillMaxWidth().height(64.dp),
                shape = RectangleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResourceCompat(R.string.home_connect), style = skyHeading(15))
                    Icon(Icons.Filled.Power, contentDescription = null)
                }
            }
            OutlinedButton(
                onClick = onAddConfig, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RectangleShape,
                border = androidx.compose.foundation.BorderStroke(1.dp, Sky.divider),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Start, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Add, contentDescription = null, tint = Sky.ink)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResourceCompat(R.string.home_add_config), style = skyHeading(15), color = Sky.ink)
                }
            }
        }
    }
}

/** The plan's remaining data and expiry, as the provider last reported them. */
@Composable
private fun QuotaRow(subscription: SubscriptionInfo, profilesViewModel: ProfilesViewModel) {
    val isRefreshing by profilesViewModel.isRefreshingSubscription.collectAsState()
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResourceCompat(R.string.home_plan).uppercase(),
                style = skySemibold(10),
                color = Sky.muted(0.5f),
                modifier = Modifier.weight(1f),
            )
            Text(
                if (isRefreshing) stringResourceCompat(R.string.home_plan_updating)
                else stringResourceCompat(R.string.home_plan_update),
                style = skySemibold(10),
                color = if (isRefreshing) Sky.muted(0.4f) else Sky.primary,
                modifier = Modifier
                    .clickable(enabled = !isRefreshing) { profilesViewModel.refreshSubscription(subscription.url) }
                    .padding(start = 12.dp),
            )
        }
        if (subscription.hasQuota) {
            val total = subscription.total ?: 0
            val used = subscription.used ?: 0
            Spacer(Modifier.height(10.dp))
            Box(Modifier.fillMaxWidth().height(6.dp).background(Sky.ink.copy(alpha = 0.15f))) {
                Box(
                    Modifier
                        .fillMaxHeight()
                        .fillMaxWidth((used.toFloat() / total.toFloat()).coerceIn(0f, 1f))
                        .background(Sky.accent),
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.home_plan_used, formatBytes(used), formatBytes(total)),
                style = skyMono(11),
                color = Sky.muted(0.6f),
            )
            subscription.remaining?.let {
                Text(
                    stringResource(R.string.home_plan_remaining, formatBytes(it)),
                    style = skyMono(11),
                    color = Sky.muted(0.6f),
                )
            }
        } else if (subscription.used != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                stringResource(R.string.home_plan_used_unlimited, formatBytes(subscription.used ?: 0)),
                style = skyMono(11),
                color = Sky.muted(0.6f),
            )
        }
        subscription.expireEpochSeconds?.let { seconds ->
            val date = java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM)
                .format(java.util.Date(seconds * 1000))
            Spacer(Modifier.height(4.dp))
            Text(
                if (subscription.isExpired) stringResource(R.string.home_plan_expired, date)
                else stringResource(R.string.home_plan_expires, date),
                style = skyMono(11),
                color = if (subscription.isExpired || subscription.expiresSoon) Sky.accent else Sky.muted(0.6f),
            )
        }
        subscription.announce?.takeIf { it.isNotBlank() }?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, style = skyBody(13), color = Sky.muted(0.7f))
        }
    }
}

private fun formatBytes(bytes: Long): String {
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

@Composable
private fun ConnectedBody(vpnManager: VpnManager, profilesViewModel: ProfilesViewModel, name: String) {
    val connectedSince by vpnManager.connectedSinceMillis.collectAsState()
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 24.dp).padding(top = 34.dp)) {
            Text(stringResourceCompat(R.string.home_connected).uppercase(), style = skySemibold(11), color = Sky.onField)
            Spacer(Modifier.height(14.dp))
            Text(name, style = skyHeading(40), color = Sky.onField, maxLines = 2)
        }
        Spacer(Modifier.height(30.dp))
        SkyRule(onField = true)
        Box(Modifier.weight(1f))
        Column(Modifier.padding(24.dp)) {
            Button(
                onClick = { vpnManager.disconnect() },
                modifier = Modifier.fillMaxWidth().height(64.dp),
                shape = RectangleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Sky.onField, contentColor = Sky.fieldInk),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResourceCompat(R.string.home_disconnect), style = skyHeading(15))
                }
            }
        }
    }
}

@Composable
private fun stringResourceCompat(id: Int): String = androidx.compose.ui.res.stringResource(id)

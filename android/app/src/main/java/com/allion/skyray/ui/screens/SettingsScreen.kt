package com.allion.skyray.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
import com.allion.skyray.core.RaycoreBridge
import com.allion.skyray.data.AppConstants
import com.allion.skyray.data.SubscriptionInfo
import com.allion.skyray.data.RoutingMode
import com.allion.skyray.service.ProfilesViewModel
import com.allion.skyray.service.VpnManager
import com.allion.skyray.ui.theme.Sky
import com.allion.skyray.ui.theme.SkyRule
import com.allion.skyray.ui.theme.skyBody
import com.allion.skyray.ui.theme.skyHeading
import com.allion.skyray.ui.theme.skyMono
import com.allion.skyray.ui.theme.skySemibold

@Composable
fun SettingsScreen(vpnManager: VpnManager, profilesViewModel: ProfilesViewModel, onClose: () -> Unit) {
    var settings by remember { mutableStateOf(vpnManager.settings) }
    val context = LocalContext.current

    fun update(block: (com.allion.skyray.data.AppSettings) -> com.allion.skyray.data.AppSettings) {
        settings = block(settings)
        vpnManager.settings = settings
    }

    Column(Modifier.fillMaxSize().background(Sky.ground)) {
        Row(Modifier.fillMaxWidth().padding(24.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.settings_title), style = skyHeading(32), color = Sky.ink)
            }
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.common_close), tint = Sky.ink) }
        }
        SkyRule()
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            SubscriptionsSection(profilesViewModel, settings.subscriptionAutoUpdateHours) { hours ->
                update { it.copy(subscriptionAutoUpdateHours = hours) }
            }

            SectionHeader(stringResource(R.string.settings_routing))
            RadioRow(stringResource(R.string.settings_routing_proxy_all), settings.routingMode == RoutingMode.proxyAll) {
                update { it.copy(routingMode = RoutingMode.proxyAll) }
            }
            RadioRow(stringResource(R.string.settings_routing_bypass_iran), settings.routingMode == RoutingMode.bypassIran) {
                update { it.copy(routingMode = RoutingMode.bypassIran) }
            }
            RadioRow(stringResource(R.string.settings_routing_global), settings.routingMode == RoutingMode.global) {
                update { it.copy(routingMode = RoutingMode.global) }
            }
            ToggleRow(stringResource(R.string.settings_block_ads), settings.blockAds) { update { s -> s.copy(blockAds = it) } }

            SectionHeader(stringResource(R.string.settings_dns))
            LabeledField(stringResource(R.string.settings_remote_dns), settings.remoteDns) { update { s -> s.copy(remoteDns = it) } }
            LabeledField(stringResource(R.string.settings_direct_dns), settings.directDns) { update { s -> s.copy(directDns = it) } }

            SectionHeader(stringResource(R.string.settings_anti_censorship))
            ToggleRow(stringResource(R.string.settings_fragment), settings.fragmentEnabled) { update { s -> s.copy(fragmentEnabled = it) } }
            ToggleRow(stringResource(R.string.settings_mux), settings.muxEnabled) { update { s -> s.copy(muxEnabled = it) } }

            SectionHeader(stringResource(R.string.settings_connection))
            ToggleRow(stringResource(R.string.settings_connect_on_demand), settings.connectOnDemand) { update { s -> s.copy(connectOnDemand = it) } }
            ToggleRow(stringResource(R.string.settings_allow_lan), settings.allowLan) { update { s -> s.copy(allowLan = it) } }

            SectionHeader(stringResource(R.string.settings_core))
            ValueRow("Xray core", RaycoreBridge.xrayVersion())
            ValueRow("sing-box core", RaycoreBridge.singboxVersion())
            ValueRow("Local SOCKS port", AppConstants.SOCKS_PORT.toString())

            SectionHeader(stringResource(R.string.settings_privacy))
            LinkRow(stringResource(R.string.settings_privacy_policy), AppConstants.PRIVACY_POLICY_URL, context)
            LinkRow(stringResource(R.string.settings_support), AppConstants.SUPPORT_URL, context)
            LinkRow(stringResource(R.string.settings_terms), AppConstants.TERMS_URL, context)
            Spacer(Modifier.height(40.dp))
        }
    }
}

/** Every link the user has added, so several can coexist and be told apart. */
@Composable
private fun SubscriptionsSection(
    profilesViewModel: ProfilesViewModel,
    autoUpdateHours: Int,
    onAutoUpdateChange: (Int) -> Unit,
) {
    val subscriptions by profilesViewModel.subscriptions.collectAsState()
    val isRefreshing by profilesViewModel.isRefreshingSubscription.collectAsState()
    var pendingRemoval by remember { mutableStateOf<SubscriptionInfo?>(null) }

    SectionHeader(
        if (subscriptions.isEmpty()) stringResource(R.string.settings_subscriptions)
        else stringResource(R.string.settings_subscriptions) + " (${subscriptions.size})",
    )

    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 14.dp)) {
        Text(stringResource(R.string.settings_subscriptions_auto_update).uppercase(), style = skySemibold(10), color = Sky.muted(0.5f))
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                0 to stringResource(R.string.settings_interval_off),
                1 to "1h", 6 to "6h", 12 to "12h",
                24 to stringResource(R.string.settings_interval_daily),
            ).forEach { (hours, label) ->
                val active = autoUpdateHours == hours
                Text(
                    label,
                    style = skySemibold(12),
                    color = if (active) Sky.onField else Sky.ink,
                    modifier = Modifier
                        .background(if (active) Sky.ink else Sky.ground)
                        .border(1.dp, Sky.divider)
                        .clickable { onAutoUpdateChange(hours) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
        }
    }
    SkyRule()

    if (subscriptions.isEmpty()) {
        Text(
            stringResource(R.string.settings_subscriptions_empty),
            style = skyBody(13), color = Sky.muted(0.6f),
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 18.dp),
        )
    } else {
        subscriptions.forEach { sub ->
            SubscriptionRow(
                sub = sub,
                serverCount = profilesViewModel.serverCount(sub.url),
                isRefreshing = isRefreshing,
                onUpdate = { profilesViewModel.refreshSubscription(sub.url) },
                onRemove = { pendingRemoval = sub },
            )
            SkyRule()
        }
    }

    pendingRemoval?.let { sub ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            title = { Text(stringResource(R.string.settings_subscription_remove_title, sub.title ?: sub.url)) },
            text = { Text(stringResource(R.string.settings_subscription_remove_body, profilesViewModel.serverCount(sub.url))) },
            confirmButton = {
                TextButton(onClick = { profilesViewModel.removeSubscription(sub.url); pendingRemoval = null }) {
                    Text(stringResource(R.string.action_delete), color = Sky.accent)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingRemoval = null }) { Text(stringResource(R.string.common_cancel), color = Sky.ink) }
            },
        )
    }
}

/** Host plus the tail of the path: enough to tell two links from one provider apart. */
private fun shortUrl(url: String): String {
    val bare = url.removePrefix("https://").removePrefix("http://")
    val host = bare.substringBefore('/')
    val rest = bare.substringAfter('/', "")
    return if (rest.isEmpty()) host else host + "/…" + rest.takeLast(8)
}

@Composable
private fun SubscriptionRow(
    sub: SubscriptionInfo,
    serverCount: Int,
    isRefreshing: Boolean,
    onUpdate: () -> Unit,
    onRemove: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(sub.title ?: sub.url, style = skySemibold(15), color = Sky.ink, maxLines = 1)
                // Keep the tail: it holds the token that tells two links from
                // the same provider apart.
                Text(shortUrl(sub.url), style = skyMono(10), color = Sky.muted(0.5f), maxLines = 1)
            }
            Text(
                if (isRefreshing) stringResource(R.string.home_plan_updating) else stringResource(R.string.home_plan_update),
                style = skySemibold(11),
                color = if (isRefreshing) Sky.muted(0.4f) else Sky.primary,
                modifier = Modifier.clickable(enabled = !isRefreshing) { onUpdate() }.padding(horizontal = 10.dp, vertical = 4.dp),
            )
            Text(
                stringResource(R.string.action_delete),
                style = skySemibold(11),
                color = Sky.accent,
                modifier = Modifier.clickable { onRemove() }.padding(horizontal = 6.dp, vertical = 4.dp),
            )
        }
        Spacer(Modifier.height(8.dp))
        Text(
            stringResource(R.string.settings_subscription_servers, serverCount),
            style = skyMono(11), color = Sky.muted(0.6f),
        )
        if (sub.hasQuota) {
            val used = sub.used ?: 0
            val total = sub.total ?: 1
            Spacer(Modifier.height(8.dp))
            androidx.compose.foundation.layout.Box(
                Modifier.fillMaxWidth().height(6.dp).background(Sky.ink.copy(alpha = 0.15f)),
            ) {
                androidx.compose.foundation.layout.Box(
                    Modifier.fillMaxWidth((used.toFloat() / total.toFloat()).coerceIn(0f, 1f))
                        .height(6.dp).background(Sky.accent),
                )
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Column(Modifier.fillMaxWidth()) {
        Text(title.uppercase(), style = skySemibold(11), color = Sky.muted(0.55f), modifier = Modifier.padding(horizontal = 24.dp, vertical = 14.dp))
        SkyRule()
    }
}

@Composable
private fun RadioRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onClick, colors = androidx.compose.material3.RadioButtonDefaults.colors(selectedColor = Sky.accent))
        Text(title, style = skySemibold(15), color = Sky.ink)
    }
}

@Composable
private fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = skySemibold(15), color = Sky.ink, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, colors = SwitchDefaults.colors(checkedTrackColor = Sky.accent))
    }
    SkyRule(strong = false)
}

@Composable
private fun LabeledField(label: String, value: String, onChange: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp)) {
        Text(label.uppercase(), style = skySemibold(10), color = Sky.muted(0.5f))
        Spacer(Modifier.height(4.dp))
        OutlinedTextField(value = value, onValueChange = onChange, modifier = Modifier.fillMaxWidth(), shape = RectangleShape, textStyle = skyMono(13), singleLine = true)
    }
}

@Composable
private fun ValueRow(label: String, value: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = skyBody(15), color = Sky.ink)
        Text(value, style = skyMono(13), color = Sky.muted(0.6f))
    }
    SkyRule(strong = false)
}

@Composable
private fun LinkRow(label: String, url: String, context: android.content.Context) {
    Row(
        Modifier.fillMaxWidth()
            .clickable { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
            .padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = skySemibold(15), color = Sky.ink)
    }
    SkyRule(strong = false)
}

package com.allion.skyray.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
import com.allion.skyray.data.ServerProfile
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
 * The server picker, opened from the card on Home. "Automatic" sits on top;
 * below it the servers are grouped by the link they came from, with their
 * latency. One tap chooses and closes; delete and copy are behind a long press.
 */
@Composable
fun ServersScreen(
    profilesViewModel: ProfilesViewModel,
    vpnManager: VpnManager,
    onBack: () -> Unit,
    onReconnect: (ServerProfile) -> Unit,
) {
    val profiles by profilesViewModel.profiles.collectAsState()
    val subscriptions by profilesViewModel.subscriptions.collectAsState()
    val automatic by profilesViewModel.isAutomatic.collectAsState()
    val selectedId by profilesViewModel.selectedId.collectAsState()
    val isPinging by profilesViewModel.isPinging.collectAsState()
    val progress by profilesViewModel.pingProgress.collectAsState()
    val updatingUrl by profilesViewModel.updatingSubscriptionUrl.collectAsState()
    val isConnected by vpnManager.isConnected.collectAsState()
    val scope = rememberCoroutineScope()
    var search by remember { mutableStateOf("") }
    var menuOpen by remember { mutableStateOf(false) }
    var toDelete by remember { mutableStateOf<ServerProfile?>(null) }
    var confirmUnreachable by remember { mutableStateOf(false) }

    // Latency is what the choice rests on, so have it ready without asking.
    // While connected the test would run through the tunnel and mislead.
    LaunchedEffect(Unit) {
        if (!isConnected && !profilesViewModel.latenciesAreFresh) profilesViewModel.pingAll()
    }

    val query = search.trim()
    val groups = profilesViewModel.groups(
        profiles.filter { query.isEmpty() || it.name.contains(query, true) || it.address.contains(query, true) },
        subscriptions,
    )
    val fastest = profiles.filter { (it.latencyMs ?: -1) > 0 }.minByOrNull { it.latencyMs!! }

    Column(Modifier.fillMaxSize().background(Sky.ground)) {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp, top = 10.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.servers_title), style = skyHeading(28), color = Sky.ink, modifier = Modifier.weight(1f))
            Box {
                IconButton(onClick = { menuOpen = true }) { Icon(Icons.Filled.MoreVert, stringResource(R.string.servers_more), tint = Sky.ink) }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.servers_test_again)) }, enabled = !isPinging,
                        onClick = { menuOpen = false; scope.launch { profilesViewModel.pingAll() } })
                    DropdownMenuItem(text = { Text(stringResource(R.string.servers_update_subscriptions)) }, enabled = subscriptions.isNotEmpty(),
                        onClick = { menuOpen = false; profilesViewModel.refreshAllSubscriptions() })
                    DropdownMenuItem(text = { Text(stringResource(R.string.servers_delete_unreachable)) },
                        onClick = { menuOpen = false; confirmUnreachable = true })
                }
            }
            IconButton(onClick = onBack) { Icon(Icons.Filled.Close, stringResource(R.string.common_close), tint = Sky.ink) }
        }
        SkyRule()
        if (isPinging) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Sky.primary)
                Spacer(Modifier.width(10.dp))
                Text(stringResource(R.string.servers_testing_progress, progress.first, progress.second), style = skyBody(13), color = Sky.muted(0.6f))
            }
            SkyRule(strong = false)
        }

        LazyColumn(Modifier.weight(1f)) {
            if (profiles.size > 20) {
                item {
                    OutlinedTextField(
                        value = search, onValueChange = { search = it },
                        placeholder = { Text(stringResource(R.string.servers_search)) },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
                        shape = RectangleShape, singleLine = true,
                    )
                }
            }
            if (query.isEmpty()) {
                item {
                    AutomaticRow(automatic, fastest) {
                        profilesViewModel.setAutomatic(true)
                        onBack()
                    }
                    SkyRule()
                }
            }
            groups.forEach { group ->
                item(key = "group-${group.url}") {
                    Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 22.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        val label = when (group.url) {
                            ProfilesViewModel.WARP_GROUP -> stringResource(R.string.servers_free_group)
                            null -> stringResource(R.string.servers_added_by_hand)
                            else -> group.title
                        }
                        Text(
                            label.uppercase(),
                            style = skySemibold(11), color = Sky.muted(0.55f), maxLines = 1,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(group.servers.size.toString(), style = skyMono(11, medium = true), color = Sky.muted(0.4f))
                        Spacer(Modifier.weight(1f))
                        if (group.url != null && updatingUrl == group.url) {
                            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = Sky.muted(0.5f))
                        }
                    }
                    SkyRule(strong = false)
                }
                items(group.servers, key = { it.id }) { profile ->
                    ServerRow(
                        profile = profile,
                        selected = !automatic && profile.id == selectedId,
                        pending = isPinging,
                        onChoose = {
                            profilesViewModel.choose(profile)
                            if (isConnected) onReconnect(profile)
                            onBack()
                        },
                        onDelete = { toDelete = profile },
                    )
                    SkyRule(strong = false)
                }
            }
            item {
                Text(stringResource(R.string.servers_long_press_hint), style = skyBody(12), color = Sky.muted(0.5f), modifier = Modifier.padding(24.dp))
            }
        }
    }

    toDelete?.let { profile ->
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text(stringResource(R.string.servers_delete_confirm_title, profile.name)) },
            confirmButton = { TextButton(onClick = { profilesViewModel.delete(profile); toDelete = null }) { Text(stringResource(R.string.action_delete), color = Sky.accent) } },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text(stringResource(R.string.common_cancel), color = Sky.ink) } },
        )
    }
    if (confirmUnreachable) {
        AlertDialog(
            onDismissRequest = { confirmUnreachable = false },
            title = { Text(stringResource(R.string.servers_delete_unreachable_confirm)) },
            confirmButton = { TextButton(onClick = { profilesViewModel.deleteUnreachable(); confirmUnreachable = false }) { Text(stringResource(R.string.action_delete), color = Sky.accent) } },
            dismissButton = { TextButton(onClick = { confirmUnreachable = false }) { Text(stringResource(R.string.common_cancel), color = Sky.ink) } },
        )
    }
}

@Composable
private fun AutomaticRow(active: Boolean, fastest: ServerProfile?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .background(if (active) Sky.surface else Sky.ground)
            .combinedClickableCompat(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(40.dp).background(Sky.primary.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Bolt, null, tint = Sky.primary, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.servers_automatic), style = skyHeading(16), color = Sky.ink)
            Text(
                fastest?.let { stringResource(R.string.servers_right_now, ltr(it.name.middleTrim(26))) } ?: stringResource(R.string.servers_automatic_body),
                style = skyBody(12), color = Sky.muted(0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(Modifier.width(8.dp))
        fastest?.let { LatencyLabel(it.latencyMs) }
        Spacer(Modifier.width(8.dp))
        CheckMark(active)
    }
}

@Composable
private fun ServerRow(profile: ServerProfile, selected: Boolean, pending: Boolean, onChoose: () -> Unit, onDelete: () -> Unit) {
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth()
                .background(if (selected) Sky.surface else Sky.ground)
                .combinedClickableCompat(onClick = onChoose, onLongClick = { menu = true })
                .padding(start = 20.dp, end = 24.dp, top = 12.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.width(4.dp).height(36.dp).background(if (selected) Sky.accent else Sky.ground))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(profile.name.middleTrim(), style = if (selected) skyHeading(15) else skySemibold(15), color = Sky.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val flag = profile.flag
                    val code = profile.country
                    if (flag != null && code != null) {
                        // The exit country: where this server's traffic really comes out.
                        Text(ltr("$flag ${code.uppercase()}"), style = skyMono(11, medium = true), color = Sky.muted(0.7f), maxLines = 1)
                    }
                    Text(profile.kindLabel, style = skyMono(11), color = Sky.muted(0.5f), maxLines = 1)
                }
            }
            Spacer(Modifier.width(8.dp))
            LatencyLabel(profile.latencyMs, pending)
            Spacer(Modifier.width(8.dp))
            CheckMark(selected)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            profile.shareLink?.let { link ->
                DropdownMenuItem(text = { Text(stringResource(R.string.servers_copy_link)) }, onClick = {
                    menu = false
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("link", link))
                })
            }
            DropdownMenuItem(text = { Text(stringResource(R.string.action_delete), color = Sky.accent) }, onClick = { menu = false; onDelete() })
        }
    }
}

@Composable
private fun CheckMark(on: Boolean) {
    Icon(Icons.Filled.Check, null, tint = if (on) Sky.accent else androidx.compose.ui.graphics.Color.Transparent, modifier = Modifier.size(18.dp))
}

@OptIn(ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableCompat(onClick: () -> Unit, onLongClick: (() -> Unit)? = null): Modifier =
    combinedClickable(onClick = onClick, onLongClick = onLongClick)

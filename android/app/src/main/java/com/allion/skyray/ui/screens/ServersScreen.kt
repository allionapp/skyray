package com.allion.skyray.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
import com.allion.skyray.data.ServerProfile
import com.allion.skyray.service.ProfilesViewModel
import com.allion.skyray.service.VpnManager
import com.allion.skyray.ui.theme.Sky
import com.allion.skyray.ui.theme.SkyRule
import com.allion.skyray.ui.theme.skyHeading
import com.allion.skyray.ui.theme.skyMono
import com.allion.skyray.ui.theme.skySemibold

@Composable
fun ServersScreen(
    profilesViewModel: ProfilesViewModel,
    vpnManager: VpnManager,
    onBack: () -> Unit,
    onAddConfig: () -> Unit,
) {
    val profiles by profilesViewModel.profiles.collectAsState()
    var search by remember { mutableStateOf("") }
    var menuOpen by remember { mutableStateOf(false) }
    val filtered = profiles.filter {
        search.isBlank() || it.name.contains(search, true) || it.address.contains(search, true)
    }

    Column(Modifier.fillMaxSize().background(Sky.ground)) {
        Column(Modifier.padding(horizontal = 24.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, contentDescription = null, tint = Sky.accent) }
                Box(Modifier.weight(1f))
                Box {
                    IconButton(onClick = { menuOpen = true }) { Icon(Icons.Filled.MoreVert, contentDescription = null, tint = Sky.ink) }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.servers_test_all)) }, onClick = { menuOpen = false; profilesViewModel.pingAll() })
                        DropdownMenuItem(text = { Text(stringResource(R.string.servers_sort_latency)) }, onClick = { menuOpen = false; profilesViewModel.sortByLatency() })
                        DropdownMenuItem(text = { Text(stringResource(R.string.servers_select_fastest)) }, onClick = { menuOpen = false; profilesViewModel.selectFastest() })
                        DropdownMenuItem(text = { Text(stringResource(R.string.servers_delete_unreachable)) }, onClick = { menuOpen = false; profilesViewModel.deleteUnreachable() })
                        DropdownMenuItem(text = { Text(stringResource(R.string.servers_delete_all)) }, onClick = { menuOpen = false; profilesViewModel.deleteAll() })
                    }
                }
            }
            Text(stringResource(R.string.servers_title), style = skyHeading(34), color = Sky.ink)
            Spacer(Modifier.height(14.dp))
            OutlinedTextField(
                value = search, onValueChange = { search = it },
                placeholder = { Text(stringResource(R.string.servers_search)) },
                modifier = Modifier.fillMaxWidth(), shape = RectangleShape, singleLine = true,
            )
        }
        SkyRule()
        LazyColumn(Modifier.weight(1f)) {
            items(filtered, key = { it.id }) { profile ->
                ServerRow(
                    profile,
                    selected = profile.id == vpnManager.settings.selectedProfileId,
                    onSelect = { vpnManager.settings = vpnManager.settings.copy(selectedProfileId = profile.id) },
                    onDelete = { profilesViewModel.delete(profile) },
                )
                SkyRule(strong = false)
            }
        }
        SkyRule()
        OutlinedButton(
            onClick = onAddConfig, modifier = Modifier.fillMaxWidth().padding(24.dp).height(54.dp), shape = RectangleShape,
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = Sky.ink)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.home_add_config), style = skyHeading(15), color = Sky.ink)
        }
    }
}

@Composable
private fun ServerRow(profile: ServerProfile, selected: Boolean, onSelect: () -> Unit, onDelete: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .background(if (selected) Sky.surface else Sky.ground)
            .clickable(onClick = onSelect)
            .padding(horizontal = 24.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(4.dp).height(36.dp).background(if (selected) Sky.accent else Sky.ink.copy(alpha = 0.15f)))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(profile.name, style = skySemibold(15), color = Sky.ink, maxLines = 1)
            Text(profile.subtitle, style = skyMono(11), color = Sky.muted(0.55f), maxLines = 1)
        }
        val ms = profile.latencyMs
        if (ms != null) {
            Text(
                if (ms < 0) "—" else "$ms ms",
                style = skyMono(11, medium = true),
                color = if (ms < 0) Sky.accentTintInk else Sky.muted(0.6f),
            )
            Spacer(Modifier.width(8.dp))
        }
        IconButton(onClick = onDelete) {
            Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.action_delete), tint = Sky.muted(0.5f))
        }
    }
}

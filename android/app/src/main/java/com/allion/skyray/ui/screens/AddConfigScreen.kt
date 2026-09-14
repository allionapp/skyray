package com.allion.skyray.ui.screens

import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
import com.allion.skyray.core.ShareLinkParser
import com.allion.skyray.core.SubscriptionLinkResolver
import com.allion.skyray.data.ServerProfile
import com.allion.skyray.service.CheckStep
import com.allion.skyray.service.ProfilesViewModel
import com.allion.skyray.service.VpnManager
import com.allion.skyray.ui.theme.Sky
import com.allion.skyray.ui.theme.SkyRule
import com.allion.skyray.ui.theme.skyBody
import com.allion.skyray.ui.theme.skyHeading
import com.allion.skyray.ui.theme.skyMono
import com.allion.skyray.ui.theme.skySemibold
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

private enum class AddStage { CHOOSE, TYPE, SCAN, CHECKING, ADDED, SUBSCRIPTION, FAILED }

/**
 * Adding a config: three ways in (clipboard, QR code, typing), one check that
 * tells single servers from subscriptions itself, and a result to connect from.
 */
@Composable
fun AddConfigScreen(
    profilesViewModel: ProfilesViewModel,
    vpnManager: VpnManager,
    vpnPermissionLauncher: ActivityResultLauncher<Intent>,
    onDone: () -> Unit,
) {
    var stage by remember { mutableStateOf(AddStage.CHOOSE) }
    var text by remember { mutableStateOf("") }
    var step by remember { mutableStateOf<CheckStep>(CheckStep.Parsing) }
    var added by remember { mutableStateOf<ServerProfile?>(null) }
    var addedLatency by remember { mutableStateOf<Int?>(null) }
    var subscriptionUrl by remember { mutableStateOf("") }
    var failureReason by remember { mutableStateOf("") }
    var clipboardEmpty by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current

    fun check(input: String) {
        stage = AddStage.CHECKING
        profilesViewModel.checkLink(input.trim()) { s ->
            step = s
            when (s) {
                is CheckStep.Reached -> {
                    added = s.profile; addedLatency = s.latencyMs
                    profilesViewModel.choose(s.profile)
                    stage = AddStage.ADDED
                }
                is CheckStep.SubscriptionAdded -> { subscriptionUrl = s.url; stage = AddStage.SUBSCRIPTION }
                is CheckStep.Failed -> { failureReason = s.reason; stage = AddStage.FAILED }
                else -> {}
            }
        }
    }

    fun connect(profile: ServerProfile) {
        vpnManager.connect(profile, vpnPermissionLauncher)
        onDone()
    }

    Box(Modifier.fillMaxSize().background(Sky.ground)) {
        when (stage) {
            AddStage.CHOOSE -> Column(Modifier.fillMaxSize()) {
                Column(Modifier.padding(start = 24.dp, end = 8.dp, top = 8.dp, bottom = 20.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.add_title), style = skyHeading(30), color = Sky.ink, modifier = Modifier.weight(1f))
                        IconButton(onClick = onDone) { Icon(Icons.Filled.Close, stringResource(R.string.common_close), tint = Sky.ink) }
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(R.string.add_chooser_subtitle), style = skyBody(14), color = Sky.muted(0.65f), modifier = Modifier.padding(end = 16.dp))
                }
                SkyRule()
                OptionRow(Icons.Filled.ContentPaste, stringResource(R.string.add_from_clipboard), stringResource(R.string.add_from_clipboard_body), highlighted = true) {
                    val copied = clipboard.getText()?.text?.trim().orEmpty()
                    if (ShareLinkParser.containsShareLink(copied) || SubscriptionLinkResolver.resolve(copied) != null) {
                        clipboardEmpty = false
                        text = copied
                        check(copied)
                    } else {
                        clipboardEmpty = true
                    }
                }
                if (clipboardEmpty) {
                    Text(stringResource(R.string.add_clipboard_empty), style = skyBody(13), color = Sky.accentDeep, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 16.dp))
                }
                SkyRule(strong = false)
                OptionRow(Icons.Filled.QrCodeScanner, stringResource(R.string.add_scan_title), stringResource(R.string.add_scan_body)) { stage = AddStage.SCAN }
                SkyRule(strong = false)
                OptionRow(Icons.Filled.Keyboard, stringResource(R.string.add_type_title), stringResource(R.string.add_type_body)) { stage = AddStage.TYPE }
                SkyRule()
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.add_subtitle), style = skyBody(12), color = Sky.muted(0.6f), modifier = Modifier.padding(24.dp))
            }

            AddStage.TYPE -> Column(Modifier.fillMaxSize().padding(24.dp)) {
                Text(stringResource(R.string.add_type_heading), style = skyHeading(28), color = Sky.ink)
                Spacer(Modifier.height(10.dp))
                Text(stringResource(R.string.add_type_hint), style = skyBody(14), color = Sky.muted(0.65f))
                Spacer(Modifier.height(20.dp))
                OutlinedTextField(
                    value = text, onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth().height(140.dp),
                    shape = RectangleShape,
                    textStyle = skyMono(12),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { clipboard.getText()?.text?.let { text = it } }, shape = RectangleShape) { Text(stringResource(R.string.add_paste)) }
                    if (text.isNotEmpty()) OutlinedButton(onClick = { text = "" }, shape = RectangleShape) { Text(stringResource(R.string.add_clear)) }
                }
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = { check(text) },
                    enabled = text.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(54.dp), shape = RectangleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
                ) { Text(stringResource(R.string.add_add), style = skyHeading(15)) }
                Spacer(Modifier.height(10.dp))
                OutlinedButton(onClick = { stage = AddStage.CHOOSE }, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RectangleShape) {
                    Text(stringResource(R.string.common_back))
                }
            }

            AddStage.SCAN -> QrScannerScreen(
                onResult = { scanned -> text = scanned; check(scanned) },
                onCancel = { stage = AddStage.CHOOSE },
            )

            AddStage.CHECKING -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
                CircularProgressIndicator(color = Sky.accent)
                Spacer(Modifier.height(20.dp))
                Text(stringResource(R.string.add_checking), style = skyHeading(22), color = Sky.ink)
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.add_checking_body), style = skyBody(13), color = Sky.muted(0.6f))
                Spacer(Modifier.height(16.dp))
                Text(stepLabel(step), style = skyMono(12), color = Sky.muted(0.6f))
            }

            AddStage.ADDED -> added?.let { profile ->
                Column(Modifier.fillMaxSize()) {
                    ResultHeader(stringResource(R.string.add_added_title), profile.name, "${profile.address}:${profile.port}" + (addedLatency?.let { " · " + ltr("$it ms") } ?: ""), onDone)
                    Column(Modifier.padding(24.dp)) {
                        Text(stringResource(R.string.add_added_body), style = skyBody(15), color = Sky.muted(0.75f))
                        Spacer(Modifier.height(22.dp))
                        PrimaryButton(stringResource(R.string.add_connect_now)) { connect(profile) }
                    }
                }
            }

            AddStage.SUBSCRIPTION -> SubscriptionResult(subscriptionUrl, profilesViewModel, onClose = onDone, onConnect = ::connect)

            AddStage.FAILED -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
                Text(stringResource(R.string.add_could_not_read), style = skyHeading(24), color = Sky.ink)
                Spacer(Modifier.height(8.dp))
                Text(failureReason, style = skyBody(14), color = Sky.accentDeep)
                Spacer(Modifier.height(24.dp))
                OutlinedButton(onClick = { stage = AddStage.CHOOSE }, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RectangleShape) {
                    Text(stringResource(R.string.common_back))
                }
            }
        }
    }
}

/**
 * What a subscription brought in: every server with its ping and real delay,
 * each with its own Connect, plus a shortcut to whichever tests fastest.
 */
@Composable
private fun SubscriptionResult(
    url: String,
    profilesViewModel: ProfilesViewModel,
    onClose: () -> Unit,
    onConnect: (ServerProfile) -> Unit,
) {
    val profiles by profilesViewModel.profiles.collectAsState()
    val subscriptions by profilesViewModel.subscriptions.collectAsState()
    val progress by profilesViewModel.pingProgress.collectAsState()
    val scope = rememberCoroutineScope()
    val tcp = remember { mutableStateMapOf<String, Int>() }
    var testing by remember { mutableStateOf(true) }
    var connectingFastest by remember { mutableStateOf(false) }

    val list = profiles.filter { it.subscriptionUrl == url }
    // Reordering while results arrive would move rows under the finger.
    val shown = if (testing) list else list.sortedBy { p -> p.latencyMs?.let { if (it < 0) Int.MAX_VALUE - 1 else it } ?: Int.MAX_VALUE }
    val title = subscriptions.firstOrNull { it.url == url }?.title

    LaunchedEffect(url) {
        val servers = profilesViewModel.profiles.value.filter { it.subscriptionUrl == url }
        profilesViewModel.clearLatencies(servers.map { it.id }.toSet())
        val delays = async { profilesViewModel.pingAll(servers) }
        val gate = Semaphore(8)
        servers.map { p -> async { gate.withPermit { tcp[p.id] = profilesViewModel.tcpLatency(p) } } }.awaitAll()
        delays.await()
        // A test started elsewhere makes ours a no-op; its results still land here.
        while (profilesViewModel.isPinging.value) kotlinx.coroutines.delay(200)
        testing = false
    }

    Column(Modifier.fillMaxSize()) {
        ResultHeader(stringResource(R.string.add_subscription_added), stringResource(R.string.settings_subscription_servers, list.size), title, onClose)
        Column(Modifier.padding(24.dp)) {
            Button(
                onClick = {
                    connectingFastest = true
                    scope.launch {
                        while (testing) kotlinx.coroutines.delay(200)
                        profilesViewModel.setAutomatic(true)
                        val best = profilesViewModel.profiles.value
                            .filter { it.subscriptionUrl == url && (it.latencyMs ?: -1) > 0 }
                            .minByOrNull { it.latencyMs!! }
                        (best ?: list.firstOrNull())?.let { profilesViewModel.select(it); onConnect(it) }
                    }
                },
                enabled = !connectingFastest,
                modifier = Modifier.fillMaxWidth().height(54.dp), shape = RectangleShape,
                colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        stringResource(if (connectingFastest) R.string.home_finding_fastest else R.string.add_connect_fastest),
                        style = skyHeading(15), modifier = Modifier.weight(1f),
                    )
                    if (connectingFastest) CircularProgressIndicator(Modifier.size(18.dp), color = Sky.onField, strokeWidth = 2.dp)
                    else Icon(Icons.Filled.Bolt, null)
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (testing) {
                    CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = Sky.muted(0.5f))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.servers_testing_progress, progress.first, progress.second), style = skyBody(12), color = Sky.muted(0.6f))
                } else {
                    Text(stringResource(R.string.add_pick_yourself), style = skyBody(12), color = Sky.muted(0.6f))
                }
            }
        }
        SkyRule()
        LazyColumn(Modifier.weight(1f)) {
            items(shown, key = { it.id }) { p ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(p.name.middleTrim(), style = skySemibold(15), color = Sky.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(p.kindLabel, style = skyMono(10), color = Sky.muted(0.5f), maxLines = 1)
                        Spacer(Modifier.height(4.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Metric(stringResource(R.string.home_ping), tcp[p.id])
                            Metric(stringResource(R.string.add_delay), if (testing && p.latencyMs == null) null else (p.latencyMs ?: -1))
                        }
                    }
                    Spacer(Modifier.width(8.dp))
                    Button(
                        onClick = { profilesViewModel.choose(p); onConnect(p) },
                        enabled = !connectingFastest,
                        shape = RectangleShape,
                        colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
                    ) { Text(stringResource(R.string.home_connect), style = skyHeading(13)) }
                }
                SkyRule(strong = false)
            }
        }
    }
}

@Composable
private fun Metric(label: String, ms: Int?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = skySemibold(10), color = Sky.muted(0.5f))
        Spacer(Modifier.width(5.dp))
        LatencyLabel(ms, pending = ms == null)
    }
}

@Composable
private fun ResultHeader(kicker: String, title: String, detail: String?, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Sky.accent).padding(start = 24.dp, end = 12.dp, top = 12.dp, bottom = 22.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(kicker.uppercase(), style = skySemibold(11), color = Sky.onField, modifier = Modifier.weight(1f))
            IconButton(onClick = onClose, modifier = Modifier.border(1.dp, Sky.onField.copy(alpha = 0.6f))) {
                Icon(Icons.Filled.Close, stringResource(R.string.common_close), tint = Sky.onField)
            }
        }
        Text(title, style = skyHeading(38), color = Sky.onField, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(end = 12.dp))
        detail?.let {
            Spacer(Modifier.height(10.dp))
            Text(it, style = skyMono(12, medium = true), color = Sky.onField)
        }
    }
}

@Composable
private fun OptionRow(icon: ImageVector, title: String, body: String, highlighted: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .background(if (highlighted) Sky.surface else Sky.ground)
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = if (highlighted) Sky.accent else Sky.ink, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = skyHeading(17), color = Sky.ink)
            Spacer(Modifier.height(4.dp))
            Text(body, style = skyBody(13), color = Sky.muted(0.65f))
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Sky.muted(0.45f))
    }
}

@Composable
private fun PrimaryButton(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().height(54.dp), shape = RectangleShape,
        colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
    ) { Text(label, style = skyHeading(15)) }
}

@Composable
private fun stepLabel(step: CheckStep): String = when (step) {
    is CheckStep.Downloading -> stringResource(R.string.add_step_downloading)
    is CheckStep.Parsing -> stringResource(R.string.add_step_reading)
    is CheckStep.LinkRead -> stringResource(R.string.add_link_read)
    is CheckStep.Testing -> stringResource(R.string.add_testing_connection)
    is CheckStep.Reached -> stringResource(R.string.add_server_reached)
    is CheckStep.SubscriptionAdded -> stringResource(R.string.add_subscription_added)
    is CheckStep.Failed -> step.reason
}

package com.allion.skyray.ui.screens

import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.allion.skyray.R
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

private enum class AddStage { PASTE, CHECKING, ADDED, FAILED }

@Composable
fun AddConfigScreen(
    profilesViewModel: ProfilesViewModel,
    vpnManager: VpnManager,
    vpnPermissionLauncher: ActivityResultLauncher<Intent>,
    onDone: () -> Unit,
) {
    var text by remember { mutableStateOf("") }
    var stage by remember { mutableStateOf(AddStage.PASTE) }
    var step by remember { mutableStateOf<CheckStep>(CheckStep.Parsing) }
    var addedProfile by remember { mutableStateOf<ServerProfile?>(null) }
    var failureReason by remember { mutableStateOf("") }
    val clipboard = LocalClipboardManager.current

    Column(Modifier.fillMaxSize().background(Sky.ground).padding(24.dp)) {
        when (stage) {
            AddStage.PASTE -> {
                Text(stringResource(R.string.add_title), style = skyHeading(28), color = Sky.ink)
                Spacer(Modifier.height(10.dp))
                Text(stringResource(R.string.add_subtitle), style = skyBody(14), color = Sky.muted(0.65f))
                Spacer(Modifier.height(20.dp))
                Text(stringResource(R.string.add_config_link).uppercase(), style = skySemibold(10), color = Sky.muted(0.5f))
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = text, onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth().height(140.dp),
                    shape = RectangleShape,
                    textStyle = skyMono(12),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { clipboard.getText()?.text?.let { text = it } }, shape = RectangleShape) {
                        Text(stringResource(R.string.add_paste))
                    }
                    if (text.isNotEmpty()) {
                        OutlinedButton(onClick = { text = "" }, shape = RectangleShape) { Text(stringResource(R.string.add_clear)) }
                    }
                }
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = {
                        stage = AddStage.CHECKING
                        profilesViewModel.checkLink(text) { s ->
                            step = s
                            when (s) {
                                is CheckStep.Reached -> { addedProfile = s.profile; stage = AddStage.ADDED }
                                is CheckStep.Failed -> { failureReason = s.reason; stage = AddStage.FAILED }
                                else -> {}
                            }
                        }
                    },
                    enabled = text.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().height(54.dp),
                    shape = RectangleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
                ) { Text(stringResource(R.string.add_check_link), style = skyHeading(15)) }
            }
            AddStage.CHECKING -> {
                Spacer(Modifier.weight(1f))
                CircularProgressIndicator(color = Sky.accent)
                Spacer(Modifier.height(20.dp))
                Text(stringResource(R.string.add_checking), style = skyHeading(22), color = Sky.ink)
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.add_checking_body), style = skyBody(13), color = Sky.muted(0.6f))
                Spacer(Modifier.height(16.dp))
                Text(stepLabel(step), style = skyMono(12), color = Sky.muted(0.6f))
                Spacer(Modifier.weight(1f))
            }
            AddStage.ADDED -> {
                Spacer(Modifier.weight(1f))
                Text("✓", style = skyHeading(48), color = Sky.accent)
                Spacer(Modifier.height(12.dp))
                Text(stringResource(R.string.add_added_title), style = skyHeading(28), color = Sky.ink)
                Spacer(Modifier.height(8.dp))
                Text(addedProfile?.name ?: "", style = skySemibold(18), color = Sky.ink)
                Text(addedProfile?.let { "${it.address}:${it.port}" } ?: "", style = skyMono(12), color = Sky.muted(0.55f))
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.add_added_body), style = skyBody(14), color = Sky.muted(0.65f))
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = { addedProfile?.let { vpnManager.connect(it, vpnPermissionLauncher) }; onDone() },
                    modifier = Modifier.fillMaxWidth().height(54.dp), shape = RectangleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = Sky.primary, contentColor = Sky.onField),
                ) { Text(stringResource(R.string.add_connect_now), style = skyHeading(15)) }
                Spacer(Modifier.height(10.dp))
                OutlinedButton(onClick = onDone, modifier = Modifier.fillMaxWidth().height(48.dp), shape = RectangleShape) {
                    Text(stringResource(R.string.add_not_now))
                }
            }
            AddStage.FAILED -> {
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.add_could_not_read), style = skyHeading(24), color = Sky.ink)
                Spacer(Modifier.height(8.dp))
                Text(failureReason, style = skyBody(14), color = Sky.accentDeep)
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = { stage = AddStage.PASTE }, modifier = Modifier.fillMaxWidth().height(50.dp), shape = RectangleShape) {
                    Text(stringResource(R.string.common_back))
                }
            }
        }
        if (stage == AddStage.PASTE) {
            Spacer(Modifier.height(8.dp))
        }
    }
}

private fun stepLabel(step: CheckStep): String = when (step) {
    is CheckStep.Downloading -> "Downloading the subscription…"
    is CheckStep.Parsing -> "Reading the link…"
    is CheckStep.LinkRead -> "Link read correctly"
    is CheckStep.Testing -> "Testing the connection…"
    is CheckStep.Reached -> "Server reached"
    is CheckStep.Failed -> step.reason
}

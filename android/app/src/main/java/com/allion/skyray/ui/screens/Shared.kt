package com.allion.skyray.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.allion.skyray.ui.theme.Sky
import com.allion.skyray.ui.theme.skyMono

/**
 * Provider names share a long prefix and differ in the tail ("…-CleanIP3-8443"),
 * so a long one loses its middle rather than its end. This Compose version has
 * no middle-ellipsis overflow of its own.
 */
fun String.middleTrim(max: Int = 36): String =
    if (length <= max) this else take(max / 2 - 1) + "…" + takeLast(max / 2)

/** Keeps "504 ms" in that order inside right-to-left text, where it would read "ms 504". */
fun ltr(text: String): String = "\u2066$text\u2069"

/** Green under 700 ms, amber under 1.5 s, red beyond or when the server didn't answer. */
fun latencyColor(ms: Int): Color = when {
    ms < 0 -> Sky.accentDeep
    ms < 700 -> Color(0xFF1E9E5A)
    ms < 1500 -> Color(0xFFE0A100)
    else -> Sky.accent
}

/** A latency with its colored dot; a spinner while [pending], nothing when never tested. */
@Composable
fun LatencyLabel(ms: Int?, pending: Boolean = false) {
    if (ms != null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).background(latencyColor(ms), CircleShape))
            Spacer(Modifier.width(5.dp))
            Text(if (ms < 0) "—" else ltr("$ms ms"), style = skyMono(12, medium = true), color = if (ms < 0) Sky.muted(0.45f) else Sky.ink)
        }
    } else if (pending) {
        CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = Sky.muted(0.5f))
    }
}

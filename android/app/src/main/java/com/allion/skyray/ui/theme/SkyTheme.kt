package com.allion.skyray.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Surface
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.allion.skyray.R

/** Modernist palette + type, matching App/Theme/SkyTheme.swift on iOS. */
object Sky {
    val ground = Color(0xFFF3F2F2)
    val surface = Color(0xFFEAE9E9)
    val ink = Color(0xFF201E1D)
    val paper = Color(0xFFFFFFFF)
    val accent = Color(0xFFEC3013)
    val accentDeep = Color(0xFFAE1800)
    val accentTint = Color(0xFFFFE0D9)
    val accentTintInk = Color(0xFF7C1405)
    val primary = Color(0xFF8013EC)
    val onField = Color(0xFFF3F2F2)
    val fieldInk = Color(0xFF201E1D)
    val divider = ink.copy(alpha = 0.4f)
    val dividerLight = ink.copy(alpha = 0.18f)

    fun muted(level: Float = 0.6f) = ink.copy(alpha = level)
}

// Archivo is a variable font; without per-weight named instances wired up here,
// weight is approximated via FontWeight on the one variable file (readable,
// though not pixel-identical to iOS's named ArchivoRoman-* instances).
private val archivoFamily = FontFamily(Font(R.font.archivo))
private val monoRegular = FontFamily(Font(R.font.ibm_plex_mono_regular))
private val monoMedium = FontFamily(Font(R.font.ibm_plex_mono_medium))

fun skyHeading(sizeSp: Int): TextStyle = TextStyle(fontFamily = archivoFamily, fontWeight = FontWeight.Black, fontSize = sizeSp.sp)

fun skySemibold(sizeSp: Int): TextStyle = TextStyle(fontFamily = archivoFamily, fontWeight = FontWeight.SemiBold, fontSize = sizeSp.sp)

fun skyBody(sizeSp: Int): TextStyle = TextStyle(fontFamily = archivoFamily, fontWeight = FontWeight.Normal, fontSize = sizeSp.sp)

fun skyMono(sizeSp: Int, medium: Boolean = false): TextStyle =
    TextStyle(fontFamily = if (medium) monoMedium else monoRegular, fontSize = sizeSp.sp)

private val skyColorScheme = lightColorScheme(
    primary = Sky.primary,
    background = Sky.ground,
    surface = Sky.surface,
    onBackground = Sky.ink,
    onSurface = Sky.ink,
    error = Sky.accent,
)

@Composable
fun SkyRayTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = skyColorScheme,
        typography = Typography(),
        shapes = Shapes(), // zero-radius look is applied per component
        content = content,
    )
}

/** A 2px (strong) or 1px (light) horizontal rule, matching iOS's `Rule`. */
@Composable
fun SkyRule(strong: Boolean = true, onField: Boolean = false, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth().height(if (strong) 2.dp else 1.dp),
        color = if (onField) Sky.onField.copy(alpha = 0.55f) else if (strong) Sky.divider else Sky.dividerLight,
        shape = RectangleShape,
    ) {}
}

package com.finix.omniverse.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/// Palette ported from the Flutter LiquidColors.
object LiquidColors {
    val Ink = Color(0xFF0B0A12)
    val Dusk = Color(0xFF24152B)
    val DeepTeal = Color(0xFF082C2E)
    val Cyan = Color(0xFF8DEBE6)
    val Rose = Color(0xFFFF8EA8)
    val Gold = Color(0xFFFFD36E)
}

private val OmniverseColorScheme = darkColorScheme(
    primary = LiquidColors.Cyan,
    secondary = LiquidColors.Rose,
    tertiary = LiquidColors.Gold,
    background = LiquidColors.Ink,
    surface = Color(0x14FFFFFF),
    onPrimary = LiquidColors.Ink,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun OmniverseTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = OmniverseColorScheme,
        typography = MaterialTheme.typography,
        content = content
    )
}

/// Ambient diagonal backdrop — the canvas the glass panels float over.
@Composable
fun LiquidBackdrop(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    0f to Color.Black,
                    0.38f to LiquidColors.Ink,
                    0.68f to Color(0xFF050A0B),
                    1f to Color(0xFF061715),
                )
            )
    )
}

/// Sleek, minimal glass surface (Android leans cleaner than iOS per the brief,
/// so blur is replaced by a crisp translucent fill + hairline border).
fun Modifier.glassPanel(corner: Int = 20, fillAlpha: Float = 0.10f, borderAlpha: Float = 0.16f): Modifier =
    this
        .clip(RoundedCornerShape(corner.dp))
        .background(Color.White.copy(alpha = fillAlpha))
        .border(1.dp, Color.White.copy(alpha = borderAlpha), RoundedCornerShape(corner.dp))
        .padding(0.dp)

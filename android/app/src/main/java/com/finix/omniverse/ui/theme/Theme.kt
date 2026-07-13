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

/// Palette aligned with the desktop (Lordflix) crimson-on-black visual system.
object LiquidColors {
    val Ink = Color(0xFF070707)
    val Dusk = Color(0xFF141414)
    val DeepTeal = Color(0xFF1C0B0D)
    val Cyan = Color(0xFFFF1E27)
    val Rose = Color(0xFFB20710)
    val Gold = Color(0xFFFF6A72)
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
                    0.38f to Color(0xFF0B0B0B),
                    0.68f to Color(0xFF140708),
                    1f to Color(0xFF24090D),
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

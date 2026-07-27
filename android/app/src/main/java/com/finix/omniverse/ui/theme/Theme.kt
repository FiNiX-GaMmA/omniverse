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

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.runtime.getValue

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

/// Ambient diagonal backdrop — the canvas the glass panels float over with desktop-style drifting aurora glows.
@Composable
fun LiquidBackdrop(modifier: Modifier = Modifier) {
    val infiniteTransition = rememberInfiniteTransition(label = "aurora")
    val pulse by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(18000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "auroraPulse"
    )

    Box(
        modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        Color(0xFF2E0507).copy(alpha = 0.25f + pulse * 0.12f),
                        Color(0xFF180507).copy(alpha = 0.15f + (1f - pulse) * 0.10f),
                        Color(0xFF050505),
                    ),
                    center = androidx.compose.ui.geometry.Offset(
                        x = 300f + pulse * 200f,
                        y = 400f + (1f - pulse) * 300f
                    ),
                    radius = 1200f
                )
            )
            .background(
                Brush.linearGradient(
                    0f to Color.Black,
                    0.38f to Color(0xFF080808),
                    0.72f to Color(0xFF130708),
                    1f to Color(0xFF22080C),
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

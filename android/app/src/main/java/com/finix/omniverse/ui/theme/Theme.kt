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

/// Palette aligned with Apple liquid glass space-black and electric cyan visual system.
object LiquidColors {
    val Ink = Color(0xFF05070C)
    val Dusk = Color(0xFF0F141C)
    val DeepTeal = Color(0xFF0A192F)
    val Cyan = Color(0xFF38BDF8)
    val Rose = Color(0xFF0284C7)
    val Gold = Color(0xFF94A3B8)
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

/// Ambient diagonal backdrop — space black canvas with Apple cyan & deep slate blue drifting aurora glows.
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
                        Color(0xFF0284C7).copy(alpha = 0.20f + pulse * 0.10f),
                        Color(0xFF0A192F).copy(alpha = 0.15f + (1f - pulse) * 0.10f),
                        Color(0xFF05070C),
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
                    0.38f to Color(0xFF060911),
                    0.72f to Color(0xFF0A111E),
                    1f to Color(0xFF0F1B2E),
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

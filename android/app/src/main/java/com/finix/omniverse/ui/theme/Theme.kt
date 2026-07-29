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

/// Cinematic palette shared with the Lordflix-inspired desktop shell.
/// Crimson is intentionally reserved for focus, progress and primary emphasis;
/// the rest of the interface stays quiet so artwork remains the visual lead.
object LiquidColors {
    val Ink = Color(0xFF050507)
    val Dusk = Color(0xFF11121A)
    val DeepTeal = Color(0xFF171020)
    val Cyan = Color(0xFFFF1E27)
    val Rose = Color(0xFFFF5A67)
    val Gold = Color(0xFFF3C969)
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

/// Ambient space-black canvas with slow crimson and indigo aurora glows.
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
                Brush.linearGradient(
                    0f to Color.Black,
                    0.42f to LiquidColors.Ink,
                    0.72f to Color(0xFF0C0C14),
                    1f to Color(0xFF151020),
                )
            )
    ) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.radialGradient(
                    colors = listOf(
                        LiquidColors.Cyan.copy(alpha = 0.16f + pulse * 0.07f),
                        Color.Transparent,
                    ),
                    center = androidx.compose.ui.geometry.Offset(
                        x = 120f + pulse * 180f,
                        y = 80f + (1f - pulse) * 260f,
                    ),
                    radius = 920f,
                )
            )
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.radialGradient(
                    colors = listOf(
                        Color(0xFF4F46E5).copy(alpha = 0.11f + (1f - pulse) * 0.06f),
                        Color.Transparent,
                    ),
                    center = androidx.compose.ui.geometry.Offset(900f, 1200f - pulse * 180f),
                    radius = 1050f,
                )
            )
        )
    }
}

/// Sleek, minimal glass surface (Android leans cleaner than iOS per the brief,
/// so blur is replaced by a crisp translucent fill + hairline border).
fun Modifier.glassPanel(corner: Int = 20, fillAlpha: Float = 0.08f, borderAlpha: Float = 0.14f): Modifier =
    this
        .clip(RoundedCornerShape(corner.dp))
        .background(Color.White.copy(alpha = fillAlpha))
        .border(1.dp, Color.White.copy(alpha = borderAlpha), RoundedCornerShape(corner.dp))
        .padding(0.dp)

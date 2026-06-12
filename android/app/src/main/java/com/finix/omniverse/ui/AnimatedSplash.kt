package com.finix.omniverse.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.finix.omniverse.R
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/// Cinematic, Netflix-style splash: accent light-beams sweep up and converge to
/// center, a bloom flash fires as the logo scales in with a glow, then the
/// OMNIVERSE wordmark fades in. ~2.3s, then [onDone].
@Composable
fun AnimatedSplash(onDone: () -> Unit) {
    val accents = listOf(
        LiquidColors.Cyan, LiquidColors.Rose, LiquidColors.Gold,
        LiquidColors.Cyan, LiquidColors.Rose, LiquidColors.Gold, LiquidColors.Cyan,
    )
    val beam = remember { Animatable(0f) }
    val converge = remember { Animatable(0f) }
    val logoScale = remember { Animatable(0.5f) }
    val logoAlpha = remember { Animatable(0f) }
    val flash = remember { Animatable(0f) }
    val wordAlpha = remember { Animatable(0f) }

    LaunchedEffectOnce {
        launch { beam.animateTo(1f, tween(600, easing = EaseOut)) }
        delay(550)
        launch { converge.animateTo(1f, tween(450)) }
        launch { logoScale.animateTo(1f, spring(dampingRatio = 0.58f, stiffness = Spring.StiffnessLow)) }
        launch { logoAlpha.animateTo(1f, tween(350)) }
        launch { flash.snapTo(0.9f); flash.animateTo(0f, tween(750)) }
        delay(650)
        launch { wordAlpha.animateTo(1f, tween(400)) }
        delay(1150)
        onDone()
    }

    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width; val h = size.height
            val n = (accents.size - 1).coerceAtLeast(1)
            val spread = w * 0.64f
            accents.forEachIndexed { i, c ->
                val baseX = -spread / 2 + spread * i / n
                val x = w / 2f + baseX * (1f - converge.value)
                val bh = h * 0.72f * beam.value
                val a = 0.9f * (1f - converge.value)
                if (a > 0.01f && bh > 0f) {
                    drawRoundRect(
                        color = c.copy(alpha = a),
                        topLeft = Offset(x - 3.5f, h / 2f - bh / 2f),
                        size = Size(7f, bh),
                        cornerRadius = CornerRadius(4f, 4f),
                    )
                }
            }
            if (flash.value > 0.01f) {
                val r = 300f
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            Color.White.copy(alpha = flash.value),
                            LiquidColors.Cyan.copy(alpha = flash.value * 0.4f),
                            Color.Transparent,
                        ),
                        center = center, radius = r,
                    ),
                    radius = r, center = center,
                )
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Image(
                painter = painterResource(R.mipmap.ic_launcher_foreground),
                contentDescription = null,
                modifier = Modifier.size(150.dp).scale(logoScale.value).alpha(logoAlpha.value),
            )
            Spacer(Modifier.height(18.dp))
            Text(
                "OMNIVERSE", color = Color.White, fontSize = 26.sp,
                fontWeight = FontWeight.Black, letterSpacing = 8.sp,
                modifier = Modifier.alpha(wordAlpha.value),
            )
        }
    }
}

/// Run a coroutine block exactly once for the composable's lifetime.
@Composable
private fun LaunchedEffectOnce(block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit) {
    androidx.compose.runtime.LaunchedEffect(Unit) { block() }
}

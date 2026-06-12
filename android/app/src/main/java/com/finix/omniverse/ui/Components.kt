package com.finix.omniverse.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter
import com.finix.omniverse.MediaCategory
import com.finix.omniverse.MediaItem
import com.finix.omniverse.WatchProgress
import com.finix.omniverse.ui.theme.LiquidColors

/// D-pad / touch focusable helper: grows the card on focus and draws a cyan
/// focus ring. Returns a Modifier carrying a clickable + focus visual.
///
/// `clickable` is itself focusable, so DPAD_CENTER / Enter activates the element
/// and arrow keys traverse between siblings with no extra wiring. Pass a
/// [focusRequester] to make an element a screen's initial-focus target (request
/// focus from a LaunchedEffect on first composition) so a TV remote has somewhere
/// to land when a screen opens.
@Composable
fun Modifier.tvFocusable(
    onClick: () -> Unit,
    corner: Int = 12,
    focusScale: Float = 1.06f,
    focusRequester: FocusRequester? = null,
): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val scale by animateFloatAsState(if (focused) focusScale else 1f, tween(140), label = "focusScale")
    return this
        .scale(scale)
        .clip(RoundedCornerShape(corner.dp))
        .border(
            width = if (focused) 2.5.dp else 0.dp,
            color = if (focused) LiquidColors.Cyan else Color.Transparent,
            shape = RoundedCornerShape(corner.dp),
        )
        .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
        .clickable(interactionSource = interaction, indication = null, onClick = onClick)
}

/// True on Android TV / leanback devices. Used to opt into TV-only tweaks such as
/// requesting initial D-pad focus (a focus grab on a touch phone would be jarring).
@Composable
fun isTvDevice(): Boolean {
    val context = androidx.compose.ui.platform.LocalContext.current
    return remember(context) {
        val uiModeManager = context.getSystemService(android.content.Context.UI_MODE_SERVICE) as? android.app.UiModeManager
        uiModeManager?.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
            context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK)
    }
}

/// Cached async network image with a glassy gradient placeholder + fallback icon.
@Composable
fun PosterImage(
    url: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
) {
    Box(modifier.background(placeholderBrush())) {
        if (!url.isNullOrEmpty()) {
            val painter = rememberAsyncImagePainter(url)
            androidx.compose.foundation.Image(
                painter = painter,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = contentScale,
            )
            when (painter.state) {
                is AsyncImagePainter.State.Loading ->
                    CircularProgressIndicator(
                        color = LiquidColors.Cyan,
                        modifier = Modifier.align(Alignment.Center).size(28.dp),
                    )
                is AsyncImagePainter.State.Error ->
                    Icon(
                        Icons.Filled.PlayArrow, null,
                        tint = Color.White.copy(alpha = 0.4f),
                        modifier = Modifier.align(Alignment.Center).size(38.dp),
                    )
                else -> {}
            }
        } else {
            Icon(
                Icons.Filled.PlayArrow, null,
                tint = Color.White.copy(alpha = 0.4f),
                modifier = Modifier.align(Alignment.Center).size(38.dp),
            )
        }
    }
}

private fun placeholderBrush() = Brush.linearGradient(
    listOf(LiquidColors.DeepTeal.copy(alpha = 0.86f), LiquidColors.Dusk.copy(alpha = 0.92f))
)

/// Small glass pill used for chips/badges.
@Composable
fun GlassChip(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White.copy(alpha = 0.1f))
            .border(0.5.dp, Color.White.copy(alpha = 0.24f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(text, color = Color.White.copy(alpha = 0.9f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

/// 2:3 poster card used in rows + grids.
@Composable
fun MediaPosterCard(item: MediaItem, wide: Boolean = false, onTap: (MediaItem) -> Unit) {
    val width = if (wide) 168.dp else 140.dp
    Column(Modifier.width(width)) {
        Box(
            Modifier
                .width(width)
                .height(width * 1.5f)
                .tvFocusable(onClick = { onTap(item) })
                .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
        ) {
            PosterImage(item.posterUrl ?: item.backdropUrl, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
        }
        Spacer(Modifier.height(8.dp))
        Text(item.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(subtitleFor(item), color = Color.White.copy(alpha = 0.6f), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun subtitleFor(item: MediaItem): String {
    val g = item.genres.take(2).joinToString(" • ")
    return if (g.isEmpty()) item.type.label else "${item.type.label} • $g"
}

/// Top-10 card with the giant translucent rank number behind the poster.
@Composable
fun Top10MediaCard(item: MediaItem, rank: Int, wide: Boolean = false, onTap: (MediaItem) -> Unit) {
    val cardWidth = if (wide) 168.dp else 140.dp
    val total = cardWidth + (if (wide) 50.dp else 40.dp)
    Box(Modifier.width(total), contentAlignment = Alignment.BottomEnd) {
        Text(
            "$rank",
            modifier = Modifier.align(Alignment.BottomStart),
            fontSize = if (wide) 170.sp else 138.sp,
            fontWeight = FontWeight.Black,
            color = Color.White.copy(alpha = 0.18f),
        )
        MediaPosterCard(item = item, wide = wide, onTap = onTap)
    }
}

/// Horizontal category rail with a tappable header.
@Composable
fun CategoryRow(
    category: MediaCategory,
    wide: Boolean = false,
    onItem: (MediaItem) -> Unit,
) {
    val isTop10 = category.title.lowercase().let { it.contains("top 10") || it.contains("top10") }
    Column(Modifier.padding(top = 18.dp)) {
        Row(Modifier.padding(horizontal = if (wide) 54.dp else 28.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(category.title, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Black)
        }
        if (category.description.isNotEmpty()) {
            Text(
                category.description, color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = if (wide) 54.dp else 28.dp, vertical = 4.dp),
            )
        }
        category.error?.takeIf { it.isNotEmpty() }?.let {
            Text(it, color = LiquidColors.Rose.copy(alpha = 0.9f), fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = if (wide) 54.dp else 28.dp))
        }
        LazyRow(
            modifier = Modifier.padding(top = 8.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = if (wide) 54.dp else 28.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(14.dp),
        ) {
            itemsIndexed(category.items, key = { _, it -> it.id }) { i, item ->
                if (isTop10) Top10MediaCard(item, i + 1, wide, onItem)
                else MediaPosterCard(item, wide, onItem)
            }
        }
    }
}

/// Continue Watching rail.
@Composable
fun ContinueWatchingRow(
    entries: List<WatchProgress>,
    onItem: (WatchProgress) -> Unit,
) {
    if (entries.isEmpty()) return
    Column(Modifier.padding(top = 18.dp)) {
        Text("Continue Watching", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Black,
            modifier = Modifier.padding(horizontal = 28.dp))
        LazyRow(
            modifier = Modifier.padding(top = 8.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 28.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(14.dp),
        ) {
            items(entries, key = { it.progressKey }) { entry ->
                Column(Modifier.width(270.dp)) {
                    Box(
                        Modifier
                            .width(270.dp).height(152.dp)
                            .tvFocusable(onClick = { onItem(entry) })
                    ) {
                        PosterImage(entry.backdropUrl ?: entry.posterUrl, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
                        Box(
                            Modifier
                                .align(Alignment.BottomStart)
                                .fillMaxWidth(entry.fraction.toFloat().coerceIn(0f, 1f))
                                .height(4.dp)
                                .background(LiquidColors.Cyan)
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(entry.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val sub = if (entry.seasonNumber != null && entry.episodeNumber != null)
                        "S${entry.seasonNumber}E${entry.episodeNumber}" else entry.type.label
                    Text(sub, color = Color.White.copy(alpha = 0.6f), fontSize = 11.sp, maxLines = 1)
                }
            }
        }
    }
}

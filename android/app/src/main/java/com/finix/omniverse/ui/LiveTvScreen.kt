package com.finix.omniverse.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.finix.omniverse.AppGraph
import com.finix.omniverse.LiveTvEntry
import com.finix.omniverse.ui.theme.LiquidColors

@Composable
fun LiveTvScreen(nav: NavController) {
    val state = AppGraph.appState
    val entries = remember(state.liveTv.toList()) {
        state.liveTv.filter { it.url.lowercase().contains(".m3u8") || it.url.contains("tv247.biz") }
    }

    fun openPlayer(entry: LiveTvEntry) {
        if (entry.url.contains("embed") || entry.url.contains("tv247.biz")) {
            val referer = entry.headers["Referer"] ?: "https://tv247.biz/"
            RouteArgs.web = WebArgs(entry.title, entry.url, mapOf("Referer" to referer)); nav.navigate("web")
        } else {
            RouteArgs.player = PlayerArgs(entry.title, entry.url, entry.headers); nav.navigate("player")
        }
    }

    Box(Modifier.fillMaxSize().statusBarsPadding()) {
        when {
            state.isScanningLiveTv -> ScanningView(state.liveTvScanProgress) { state.cancelLiveTvScan() }
            !state.hasScannedLiveTv || entries.isEmpty() -> ScanPrompt(state.settings.liveTvCountry) { state.startLiveTvScan() }
            else -> {
                val grouped = remember(entries) { groupByCategory(entries) }
                LazyColumn(Modifier.fillMaxSize()) {
                    item { Spacer(Modifier.height(16.dp)) }
                    grouped.forEach { (title, list) ->
                        item(key = title) { LiveTvCategoryRow(title, list, ::openPlayer) }
                    }
                    item { Spacer(Modifier.height(54.dp)) }
                }
            }
        }
    }
}

@Composable
private fun ScanPrompt(country: String, onScan: () -> Unit) {
    val name = if (country.lowercase() == "all") "Global" else country.uppercase()
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Box(Modifier.size(120.dp).clip(RoundedCornerShape(60.dp)).background(LiquidColors.Cyan.copy(alpha = 0.12f))
            .border(2.dp, LiquidColors.Cyan.copy(alpha = 0.28f), RoundedCornerShape(60.dp)), Alignment.Center) {
            Icon(Icons.Filled.LiveTv, null, tint = LiquidColors.Cyan, modifier = Modifier.size(64.dp))
        }
        Spacer(Modifier.height(24.dp))
        Text("IPTV Channel Scanner", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(8.dp))
        Text("Scan and verify active Live TV streams for country: $name\n(Configurable in Settings)",
            color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp)
        Spacer(Modifier.height(28.dp))
        Box(Modifier.clip(RoundedCornerShape(16.dp)).background(LiquidColors.Cyan.copy(alpha = 0.24f))
            .tvFocusable(onClick = onScan, corner = 16).padding(horizontal = 24.dp, vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.PlayArrow, null, tint = Color.White)
                Text("Start Channel Scan", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }
    }
}

@Composable
private fun ScanningView(progress: Double, onCancel: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        CircularProgressIndicator(color = LiquidColors.Cyan)
        Spacer(Modifier.height(28.dp))
        Text("Scanning Frequencies...", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(10.dp))
        Text("Probing stream links in parallel with high-speed HEAD checks.\nFiltering active, responsive, and working feeds...",
            color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp)
        Spacer(Modifier.height(28.dp))
        LinearProgressIndicator(progress = { progress.toFloat().coerceIn(0f, 1f) }, color = LiquidColors.Cyan, modifier = Modifier.width(320.dp))
        Spacer(Modifier.height(12.dp))
        Text("${(progress * 100).toInt()}% Complete", color = LiquidColors.Cyan, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(28.dp))
        Text("Cancel Scan", color = Color(0xFFE53935), fontWeight = FontWeight.SemiBold,
            modifier = Modifier.tvFocusable(onClick = onCancel, corner = 8).padding(8.dp))
    }
}

@Composable
private fun LiveTvCategoryRow(title: String, entries: List<LiveTvEntry>, onSelected: (LiveTvEntry) -> Unit) {
    Column(Modifier.padding(top = 18.dp, start = 28.dp)) {
        Row(Modifier.fillMaxWidth().padding(end = 28.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.weight(1f))
            Text("${entries.size}", color = Color.White.copy(alpha = 0.58f), fontSize = 15.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(12.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(end = 28.dp)) {
            items(entries, key = { it.url }) { entry ->
                Column(Modifier.width(176.dp)) {
                    Box(Modifier.width(176.dp).height(130.dp).tvFocusable(onClick = { onSelected(entry) }, corner = 18)
                        .clip(RoundedCornerShape(18.dp))
                        .background(Brush.linearGradient(listOf(Color.White.copy(alpha = 0.12f), LiquidColors.DeepTeal.copy(alpha = 0.2f), Color.Black.copy(alpha = 0.5f))))) {
                        if (!entry.logoUrl.isNullOrEmpty()) {
                            PosterImage(entry.logoUrl, Modifier.size(92.dp).align(Alignment.Center), ContentScale.Fit)
                        } else {
                            Icon(Icons.Filled.LiveTv, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(48.dp).align(Alignment.Center))
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(entry.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(categoriesFor(entry).joinToString(" • "), color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

// MARK: - Category grouping (parity with the Swift / Dart helpers)

private fun groupByCategory(list: List<LiveTvEntry>): List<Pair<String, List<LiveTvEntry>>> {
    val grouped = LinkedHashMap<String, MutableList<LiveTvEntry>>()
    for (entry in list) for (cat in categoriesFor(entry)) grouped.getOrPut(cat) { ArrayList() }.add(entry)
    val preferred = listOf("News", "Entertainment", "Movies", "Sports", "Music")
    val keys = grouped.keys.sortedWith(Comparator { a, b ->
        val ai = preferred.indexOf(a); val bi = preferred.indexOf(b)
        if (ai != -1 || bi != -1) (if (ai == -1) 999 else ai).compareTo(if (bi == -1) 999 else bi)
        else a.compareTo(b)
    })
    return keys.map { it to grouped[it]!!.sortedBy { e -> e.title } }
}

private fun categoriesFor(entry: LiveTvEntry): List<String> {
    val values = entry.region.split(";").map { it.trim() }.filter { it.isNotEmpty() }.map(::formatCategory).toSortedSet()
    return if (values.isEmpty()) listOf("Unknown") else values.toList()
}

private fun formatCategory(value: String): String {
    val normalized = if (value.lowercase() == "undefined") "unknown" else value
    return normalized.split(' ', '_', '-').filter { it.isNotEmpty() }
        .joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }
}

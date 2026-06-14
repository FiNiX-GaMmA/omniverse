package com.finix.omniverse.ui

import androidx.compose.animation.animateContentSize
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateListOf
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
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.MediaSeason
import com.finix.omniverse.MediaType
import com.finix.omniverse.PlaybackSource
import com.finix.omniverse.VidsrcExtractor
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.launch
import kotlin.math.ceil

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaDetailScreen(item: MediaItem, nav: NavController) {
    val state = AppGraph.appState
    val scope = rememberCoroutineScope()

    var detailed by remember { mutableStateOf<MediaItem?>(null) }
    var selectedSeason by remember { mutableStateOf(1) }
    val episodes = remember { mutableStateListOf<MediaEpisode>() }
    var loadingEpisodes by remember { mutableStateOf(false) }
    var loadingStreams by remember { mutableStateOf(false) }
    var seasonMenu by remember { mutableStateOf(false) }

    // Source sheet state
    var sheetSources by remember { mutableStateOf<List<PlaybackSource>>(emptyList()) }
    var sheetTitle by remember { mutableStateOf("") }
    var pendingEpisode by remember { mutableStateOf<MediaEpisode?>(null) }
    var showSheet by remember { mutableStateOf(false) }

    val current = detailed ?: item
    val isSeries = current.type == MediaType.SERIES || current.type == MediaType.ANIME

    fun expandedSeasons(c: MediaItem): List<MediaSeason> {
        val out = ArrayList<MediaSeason>()
        for (s in c.seasons) {
            val total = maxOf(s.episodeCount, c.episodes.count { it.seasonNumber == s.seasonNumber })
            if (total > 50) {
                val chunks = ceil(total / 50.0).toInt()
                for (i in 0 until chunks) {
                    val startE = i * 50 + 1; val endE = minOf(total, (i + 1) * 50)
                    out.add(MediaSeason(s.seasonNumber * 1000 + i, "${s.name} (Part ${i + 1})", endE - startE + 1))
                }
            } else out.add(s)
        }
        return out
    }

    suspend fun loadEpisodes(c: MediaItem, season: Int) {
        loadingEpisodes = true
        val result = if (season >= 1000) {
            val original = season / 1000; val chunk = season % 1000
            var full = if (c.episodes.firstOrNull()?.seasonNumber == original) c.episodes
                else state.seasonEpisodesFor(c, original)
            val startI = chunk * 50; val endI = minOf(full.size, (chunk + 1) * 50)
            full = if (startI < endI) full.subList(startI, endI) else emptyList()
            full.map { it.copy(seasonNumber = season) }
        } else state.seasonEpisodesFor(c, season)
        episodes.clear(); episodes.addAll(result)
        loadingEpisodes = false
    }

    LaunchedEffect(item.id) {
        val d = state.detailsFor(item)
        detailed = d
        if (d.type == MediaType.SERIES || d.type == MediaType.ANIME) {
            val seasons = expandedSeasons(d)
            selectedSeason = seasons.firstOrNull { it.seasonNumber > 0 }?.seasonNumber ?: seasons.firstOrNull()?.seasonNumber ?: 1
            loadEpisodes(d, selectedSeason)
        }
    }

    fun dispatch(source: PlaybackSource, episode: MediaEpisode?) {
        if (current.type != MediaType.ANIME && current.title != "One Pace") {
            scope.launch { state.recordProgress(current, 10000, 3600000, episode) }
        }
        val resume = state.continueWatching.firstOrNull { it.itemId == current.id && it.episodeNumber == episode?.episodeNumber }?.positionMs
        when {
            source.isEmbed && source.provider == "VidSrc" -> {
                val urls = VidsrcExtractor().embedUrlsFor(
                    current, episode, state.settings.vidsrcDomain,
                    state.settings.subtitleUrl, state.settings.subtitleLanguage,
                )
                if (urls.isEmpty()) {
                    RouteArgs.web = WebArgs(source.title, source.url, source.headers); nav.navigate("web")
                } else {
                    RouteArgs.vidsrc = VidsrcArgs(current, source.title, urls, episode); nav.navigate("vidsrc")
                }
            }
            source.isEmbed -> { RouteArgs.web = WebArgs(source.title, source.url, source.headers); nav.navigate("web") }
            else -> {
                RouteArgs.player = PlayerArgs(
                    "${current.title} • ${source.title}", source.url, source.headers, current, episode,
                    source.subtitleUrl, resume, null,
                )
                nav.navigate("player")
            }
        }
    }

    suspend fun openSources(episode: MediaEpisode?) {
        loadingStreams = true
        try {
            val s = state.playbackSourcesFor(current, episode)
            if (s.isEmpty()) { state.message = "No playable sources found."; return }
            sheetSources = s
            sheetTitle = if (episode != null) "${current.title} S${episode.seasonNumber}E${episode.episodeNumber}" else current.title
            pendingEpisode = episode
            // one-click preferred-server bypass + single direct anime auto-open
            val domain = state.settings.vidsrcDomain.trim()
            val match = if (domain.isNotEmpty()) s.firstOrNull { it.url.contains(domain) } else null
            when {
                match != null -> dispatch(match, episode)
                current.type == MediaType.ANIME && s.size == 1 && s[0].isDirect -> dispatch(s[0], episode)
                else -> showSheet = true
            }
        } catch (t: Throwable) { state.message = "Could not load sources: $t" } finally { loadingStreams = false }
    }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                androidx.compose.foundation.layout.BoxWithConstraints {
                    val wide = maxWidth >= 900.dp
                    DetailHero(current, wide, loadingStreams, isSeries,
                        onPlay = {
                            scope.launch {
                                if (isSeries) {
                                    val target = episodes.firstOrNull() ?: current.episodes.firstOrNull()
                                    if (target != null) openSources(target)
                                } else openSources(null)
                            }
                        },
                        onWatchlist = { scope.launch { state.toggleWatchlist(current) } },
                    )
                }
            }
            if (isSeries) {
                item {
                    val seasons = expandedSeasons(current)
                    Box(Modifier.padding(horizontal = 26.dp, vertical = 10.dp)) {
                        Box(
                            Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.1f))
                                .tvFocusable(onClick = { seasonMenu = true }, corner = 50)
                                .padding(horizontal = 16.dp, vertical = 10.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(seasons.firstOrNull { it.seasonNumber == selectedSeason }?.name ?: "Season",
                                    color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Icon(Icons.Filled.KeyboardArrowDown, null, tint = Color.White.copy(alpha = 0.7f))
                            }
                        }
                        DropdownMenu(seasonMenu, { seasonMenu = false }) {
                            seasons.forEach { s ->
                                DropdownMenuItem(text = { Text(s.name) }, onClick = {
                                    seasonMenu = false; selectedSeason = s.seasonNumber
                                    scope.launch { loadEpisodes(current, s.seasonNumber) }
                                })
                            }
                        }
                    }
                }
                item {
                    when {
                        loadingEpisodes -> Box(Modifier.fillMaxWidth().height(150.dp), Alignment.Center) {
                            CircularProgressIndicator(color = LiquidColors.Cyan)
                        }
                        episodes.isEmpty() -> Text("No episodes loaded for this season.",
                            color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, modifier = Modifier.padding(26.dp))
                        else -> LazyRow(
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 26.dp),
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                            modifier = Modifier.padding(top = 14.dp),
                        ) {
                            items(episodes, key = { "${it.seasonNumber}-${it.episodeNumber}" }) { ep ->
                                EpisodeCard(ep) { scope.launch { openSources(ep) } }
                            }
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(80.dp)) }
        }
        // Back button
        Box(
            Modifier.align(Alignment.TopStart).padding(start = 16.dp, top = 8.dp)
                .size(44.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f))
                .tvFocusable(onClick = { nav.popBackStack() }, corner = 22),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White) }
    }

    if (showSheet) {
        ModalBottomSheet(onDismissRequest = { showSheet = false }, containerColor = Color(0xFF14141A)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(sheetTitle, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black)
                sheetSources.forEach { src ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .tvFocusable(onClick = { showSheet = false; dispatch(src, pendingEpisode) }, corner = 16)
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(Icons.Filled.PlayArrow, null, tint = LiquidColors.Cyan)
                        Column(Modifier.weight(1f)) {
                            Text(src.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            Text("${src.provider} • ${src.quality}", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
        }
    }
}

@Composable
private fun DetailHero(
    current: MediaItem, wide: Boolean, loadingStreams: Boolean, isSeries: Boolean,
    onPlay: () -> Unit, onWatchlist: () -> Unit,
) {
    val state = AppGraph.appState
    val resume = state.continueWatching.firstOrNull { it.itemId == current.id }
    val playLabel = when {
        resume != null && resume.seasonNumber != null && resume.episodeNumber != null -> "Resume S${resume.seasonNumber}E${resume.episodeNumber}"
        resume != null -> "Resume"
        isSeries -> "Play First Episode"
        else -> "Play"
    }
    Box(Modifier.fillMaxWidth().height(720.dp)) {
        PosterImage(current.heroBackdropUrl ?: current.backdropUrl ?: current.posterUrl, Modifier.fillMaxSize(), ContentScale.Crop)
        Box(Modifier.fillMaxSize().background(
            Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.6f), Color.Black.copy(alpha = 0.08f), Color.Black.copy(alpha = 0.93f)))
        ))
        Column(
            Modifier.align(Alignment.BottomStart).widthIn(max = 720.dp)
                .padding(horizontal = if (wide) 54.dp else 26.dp).padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(current.title, color = Color.White, fontSize = if (wide) 44.sp else 30.sp, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(current.type.label + (if (current.genres.isEmpty()) "" else " • " + current.genres.take(3).joinToString(" • ")),
                color = Color.White.copy(alpha = 0.72f), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            if (current.overview.isNotEmpty()) {
                var expanded by remember { mutableStateOf(false) }
                Column(Modifier.fillMaxWidth().animateContentSize()) {
                    Text(
                        current.overview,
                        color = Color.White.copy(alpha = 0.82f),
                        fontSize = 14.sp,
                        maxLines = if (expanded) 20 else 3,
                        overflow = TextOverflow.Ellipsis,
                        lineHeight = 20.sp
                    )
                    if (current.overview.length > 150) {
                        Text(
                            text = if (expanded) "Read Less" else "Read More",
                            color = LiquidColors.Cyan,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .tvFocusable(onClick = { expanded = !expanded }, corner = 4)
                                .padding(vertical = 4.dp, horizontal = 8.dp)
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GlassChip(current.releaseDate.split("-").firstOrNull()?.ifEmpty { "2025" } ?: "2025")
                current.runtimeMinutes?.let { GlassChip("$it min") }
                if (current.rating > 0) GlassChip("★ ${"%.1f".format(current.rating)}")
                GlassChip("CC"); GlassChip("AD")
            }
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(Color.White)
                        .tvFocusable(onClick = onPlay, corner = 50).padding(vertical = 14.dp, horizontal = 26.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (loadingStreams) CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Filled.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(20.dp))
                        Text(playLabel, color = Color.Black, fontWeight = FontWeight.Black, fontSize = 16.sp)
                    }
                }
                Box(
                    Modifier.size(56.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f))
                        .border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape)
                        .tvFocusable(onClick = onWatchlist, corner = 28),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(if (state.isInWatchlist(current)) Icons.Filled.Check else Icons.Filled.Add, null, tint = Color.White, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}

@Composable
private fun EpisodeCard(ep: MediaEpisode, onTap: () -> Unit) {
    Column(Modifier.width(280.dp)) {
        Box(
            Modifier.width(280.dp).height(158.dp).tvFocusable(onClick = onTap)
        ) {
            PosterImage(ep.stillUrl, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
        }
        Spacer(Modifier.height(6.dp))
        Text("EPISODE ${ep.episodeNumber}", color = Color.White.copy(alpha = 0.5f), fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Text(ep.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (ep.overview.isNotEmpty()) Text(ep.overview, color = Color.White.copy(alpha = 0.6f), fontSize = 11.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

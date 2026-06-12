package com.finix.omniverse.ui

import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.finix.omniverse.AppGraph
import com.finix.omniverse.MediaCategory
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.MediaType
import com.finix.omniverse.VidsrcExtractor
import com.finix.omniverse.WatchProgress
import com.finix.omniverse.imageUrl
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun HomeScreen(nav: NavController) {
    val state = AppGraph.appState

    fun openDetail(item: MediaItem) {
        RouteArgs.detailItem = item
        nav.navigate("detail")
    }

    val scope = rememberCoroutineScope()

    fun mediaItemFor(entry: WatchProgress): MediaItem {
        val parts = entry.itemId.split(":")
        var item = MediaItem(id = entry.itemId, type = entry.type, title = entry.title,
            posterPath = entry.posterPath, backdropPath = entry.backdropPath)
        if (parts.size >= 3) when (parts[0]) {
            "tmdb" -> item = item.copy(tmdbId = parts[2].toIntOrNull())
            "trakt" -> item = item.copy(traktId = parts[2].toIntOrNull())
        }
        return item
    }

    /// Resolve a Continue Watching entry and navigate to the player at [startPositionMs].
    /// Returns true on a successful resolve+navigate, false if it fell back to detail.
    suspend fun resolveAndPlay(entry: WatchProgress, startPositionMs: Int): Boolean {
        val item = mediaItemFor(entry)
        // One Pace: resolve the arc/episode and resume playback directly.
        if (entry.title == "One Pace" || entry.itemId.startsWith("onepace:") || entry.itemId.startsWith("anilist:anime:21")) {
            val season = entry.seasonNumber
            val epNum = entry.episodeNumber
            if (season == null || epNum == null) { openDetail(item); return false }
            val resume = runCatching { resolveOnePaceResume(season, epNum, state.credentials.pixeldrainApiKey) }.getOrNull()
            if (resume == null) { openDetail(item); return false }
            RouteArgs.player = PlayerArgs(resume.title, resume.url, emptyMap(),
                resume.item, resume.episode, resume.subtitleUrl, startPositionMs, resume.aniSkipEpisode)
            nav.navigate("player")
            return true
        }
        val episode = if (entry.seasonNumber != null && entry.episodeNumber != null)
            MediaEpisode(entry.seasonNumber!!, entry.episodeNumber!!, entry.episodeTitle ?: "Episode") else null
        return try {
            val s = state.playbackSourcesFor(item, episode)
            val src = s.firstOrNull { it.isDirect || it.provider == "VidSrc" } ?: s.firstOrNull()
            if (src == null) { openDetail(item); return false }
            when {
                src.isEmbed && src.provider == "VidSrc" -> {
                    val urls = VidsrcExtractor().embedUrlsFor(item, episode, state.settings.vidsrcDomain,
                        state.settings.subtitleUrl, state.settings.subtitleLanguage)
                    if (urls.isEmpty()) { RouteArgs.web = WebArgs(src.title, src.url, src.headers); nav.navigate("web") }
                    else { RouteArgs.vidsrc = VidsrcArgs(item, src.title, urls, episode); nav.navigate("vidsrc") }
                }
                src.isEmbed -> { RouteArgs.web = WebArgs(src.title, src.url, src.headers); nav.navigate("web") }
                else -> {
                    RouteArgs.player = PlayerArgs(item.title, src.url, src.headers, item, episode, src.subtitleUrl, startPositionMs, null)
                    nav.navigate("player")
                }
            }
            true
        } catch (t: Throwable) { openDetail(item); false }
    }

    // Tapping a Continue Watching card shows an intuitive popup (Resume / Play from
    // beginning / Details) rather than silently resolving + navigating.
    var sheetEntry by remember { mutableStateOf<WatchProgress?>(null) }

    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 900.dp
        val landscape = maxWidth > maxHeight
        // Hero banner enlarged by 20% over the previous sizing.
        val heroH: Dp =
            if (landscape) minOf(maxWidth * 9f / 16f, maxHeight * 0.86f) * 1.2f   // 16:9 widescreen banner
            else minOf(maxWidth * 1.5f, maxHeight * 0.72f) * 1.2f                 // tall poster area
        val cats = displayCategories()

        LazyColumn(Modifier.fillMaxSize()) {
            item {
                HeroCarousel(state.heroPicks, wide, heroH, !landscape, onSelect = ::openDetail)
            }
            item {
                val entries = remember(state.watchHistory.toList()) {
                    val seen = HashSet<String>()
                    state.continueWatching.filter { it.type != MediaType.LIVE_TV && seen.add(it.itemId) }
                }
                ContinueWatchingRow(entries) { entry -> sheetEntry = entry }
            }
            items(cats, key = { it.id }) { cat -> CategoryRow(cat, wide, ::openDetail) }
            item { Spacer(Modifier.height(110.dp)) }
        }

        sheetEntry?.let { entry ->
            ContinueWatchingSheet(
                entry = entry,
                onDismiss = { sheetEntry = null },
                onResume = {
                    scope.launch { resolveAndPlay(entry, entry.positionMs); sheetEntry = null }
                },
                onPlayFromStart = {
                    scope.launch { resolveAndPlay(entry, 0); sheetEntry = null }
                },
                onDetails = { sheetEntry = null; openDetail(mediaItemFor(entry)) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ContinueWatchingSheet(
    entry: WatchProgress,
    onDismiss: () -> Unit,
    onResume: () -> Unit,
    onPlayFromStart: () -> Unit,
    onDetails: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    var resolving by remember { mutableStateOf(false) }
    ModalBottomSheet(
        onDismissRequest = { if (!resolving) onDismiss() },
        sheetState = sheetState,
        containerColor = LiquidColors.Dusk.copy(alpha = 0.96f),
        dragHandle = null,
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 22.dp).padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.width(132.dp).height(74.dp).clip(RoundedCornerShape(10.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp))) {
                    PosterImage(entry.backdropUrl ?: entry.posterUrl, Modifier.fillMaxSize(), ContentScale.Crop)
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                    Text(entry.title, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Black,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val pct = (entry.fraction * 100).toInt()
                    val sub = if (entry.seasonNumber != null && entry.episodeNumber != null)
                        "S${entry.seasonNumber}E${entry.episodeNumber} • $pct% watched"
                    else "$pct% watched"
                    Text(sub, color = Color.White.copy(alpha = 0.66f), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            if (resolving) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                    CircularProgressIndicator(color = LiquidColors.Cyan, modifier = Modifier.size(22.dp))
                    Text("Resolving…", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                }
            } else {
                SheetButton("▶ Resume", primary = true) { resolving = true; onResume() }
                SheetButton("↺ Play from beginning") { resolving = true; onPlayFromStart() }
                SheetButton("ℹ Details") { onDetails() }
            }
        }
    }
}

@Composable
private fun SheetButton(label: String, primary: Boolean = false, onClick: () -> Unit) {
    val bg = if (primary) Color.White else Color.White.copy(alpha = 0.1f)
    val fg = if (primary) Color.Black else Color.White
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(bg)
            .border(if (primary) 0.dp else 1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(12.dp))
            .tvFocusable(onClick = onClick, corner = 12)
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = fg, fontSize = 16.sp, fontWeight = FontWeight.Black)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HeroCarousel(picks: List<MediaItem>, wide: Boolean, height: Dp, portrait: Boolean, onSelect: (MediaItem) -> Unit) {
    val state = AppGraph.appState
    // Capture picks ONCE with a stable identity key (the list of ids). An unrelated
    // Home recomposition that returns a fresh List instance must NOT rebuild the pager
    // or reset it mid-animation, which is what caused the half-page settle glitch.
    val limited = remember(picks.map { it.id }) { picks.take(10) }
    if (limited.isEmpty()) {
        Box(
            Modifier
                .fillMaxWidth().height(height)
                .background(Brush.verticalGradient(listOf(LiquidColors.Dusk, LiquidColors.DeepTeal))),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Omniverse", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Black)
                Text(
                    if (state.needsSetup) "Add your TMDB key in Settings to fill this carousel."
                    else "Refreshing the carousel...",
                    color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp,
                )
            }
        }
        return
    }
    val pageCount = limited.size
    val pager = rememberPagerState(pageCount = { pageCount })
    // Auto-advance: keyed on (pager, pageCount), NOT currentPage, so the effect isn't
    // restarted every page change. Loop with a fixed delay and only advance when the
    // pager is fully settled and not being dragged.
    androidx.compose.runtime.LaunchedEffect(pager, pageCount) {
        if (pageCount <= 1) return@LaunchedEffect
        while (true) {
            delay(6000)
            if (pageCount > 1 && !pager.isScrollInProgress) {
                pager.animateScrollToPage((pager.currentPage + 1) % pageCount)
            }
        }
    }
    // Safety net: whenever scrolling settles, if the pager came to rest between two
    // pages (non-zero offset fraction), hard-snap to the current whole page so it can
    // NEVER show half of two banners.
    androidx.compose.runtime.LaunchedEffect(pager) {
        snapshotFlow { pager.isScrollInProgress }.collect { scrolling ->
            if (!scrolling && pager.currentPageOffsetFraction != 0f) {
                pager.scrollToPage(pager.currentPage)
            }
        }
    }
    Box(Modifier.fillMaxWidth().height(height)) {
        HorizontalPager(
            state = pager,
            modifier = Modifier.fillMaxSize(),
            pageSize = PageSize.Fill,
            flingBehavior = PagerDefaults.flingBehavior(state = pager),
            beyondViewportPageCount = 1,
        ) { page ->
            HeroPage(limited[page], wide, portrait, onSelect)
        }
        Row(
            Modifier.align(Alignment.BottomCenter).padding(bottom = if (wide) 56.dp else 16.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            repeat(limited.size) { i ->
                Box(
                    Modifier
                        .height(8.dp)
                        .width(if (i == pager.currentPage) 30.dp else 8.dp)
                        .clip(RoundedCornerShape(50))
                        .background(if (i == pager.currentPage) LiquidColors.Cyan else Color.White.copy(alpha = 0.36f))
                )
            }
        }
    }
}

@Composable
private fun HeroPage(item: MediaItem, wide: Boolean, portrait: Boolean, onSelect: (MediaItem) -> Unit) {
    androidx.compose.foundation.layout.BoxWithConstraints(
        Modifier.fillMaxSize().tvFocusable(onClick = { onSelect(item) }, corner = 0)
    ) {
        // Portrait → tall 9:16 poster; landscape → 16:9 backdrop, so the image
        // matches the frame and isn't blown up/cropped.
        val heroUrl = if (portrait)
            (imageUrl(item.posterPath, "original") ?: item.heroBackdropUrl ?: item.backdropUrl ?: item.posterUrl)
        else
            (item.heroBackdropUrl ?: item.backdropUrl ?: item.posterUrl)
        PosterImage(heroUrl, Modifier.fillMaxSize(), ContentScale.Crop)
        // Gentle bottom dissolve so the banner melts into the rows below.
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    0f to Color.Transparent,
                    0.6f to Color.Transparent,
                    0.92f to LiquidColors.Ink.copy(alpha = 0.85f),
                    1f to LiquidColors.Ink,
                )
            )
        )
        // Text colour is derived dynamically from the hero image (a light, vibrant
        // swatch via Palette), falling back to white. A shadow keeps it legible.
        val accent = rememberHeroTextColor(heroUrl)
        val textShadow = androidx.compose.ui.graphics.Shadow(
            Color.Black.copy(alpha = 0.85f), androidx.compose.ui.geometry.Offset(0f, 2f), 10f,
        )
        val ratingPart = if (item.rating > 0) "★ " + String.format("%.1f", item.rating) + " • " else ""
        val metaText = ratingPart + item.type.label +
            (if (item.genres.isEmpty()) "" else " • " + item.genres.take(2).joinToString(" • "))
        // Portrait shows ONLY the metadata, CENTERED on the image; landscape shows
        // the name above it, left-aligned.
        Column(
            Modifier
                .align(if (portrait) Alignment.BottomCenter else Alignment.BottomStart)
                .fillMaxWidth()
                .padding(horizontal = if (wide) 54.dp else 20.dp)
                .padding(bottom = if (wide) 60.dp else 44.dp),
            horizontalAlignment = if (portrait) Alignment.CenterHorizontally else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!portrait) {
                Text(
                    item.title, color = accent, fontSize = if (wide) 46.sp else 32.sp,
                    fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    style = androidx.compose.ui.text.TextStyle(shadow = textShadow),
                )
            }
            Text(
                metaText,
                color = accent.copy(alpha = 0.95f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                textAlign = if (portrait) androidx.compose.ui.text.style.TextAlign.Center else androidx.compose.ui.text.style.TextAlign.Start,
                style = androidx.compose.ui.text.TextStyle(shadow = textShadow),
            )
            // Portrait gets a centered Play button (opens the title to play).
            if (portrait) {
                Row(
                    Modifier
                        .padding(top = 4.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.White)
                        .tvFocusable(onClick = { onSelect(item) }, corner = 50)
                        .padding(vertical = 12.dp, horizontal = 32.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Filled.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(20.dp))
                    Text("Play", color = Color.Black, fontWeight = FontWeight.Black, fontSize = 16.sp)
                }
            }
        }
    }
}

/// Derives the hero text colour from the banner image: loads it, extracts a
/// light/vibrant swatch via Palette, and lightens it if too dark to stay
/// readable. Falls back to white. Recomputed per image URL.
@Composable
private fun rememberHeroTextColor(url: String?): Color {
    val context = androidx.compose.ui.platform.LocalContext.current
    val color = remember(url) { androidx.compose.runtime.mutableStateOf(Color.White) }
    androidx.compose.runtime.LaunchedEffect(url) {
        if (url.isNullOrBlank()) return@LaunchedEffect
        val rgb: Int? = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            runCatching {
                val loader = coil.ImageLoader(context)
                val req = coil.request.ImageRequest.Builder(context)
                    .data(url).allowHardware(false).size(256).build()
                val result = loader.execute(req)
                val bmp = (result.drawable as? android.graphics.drawable.BitmapDrawable)?.bitmap
                    ?: return@runCatching null
                val palette = androidx.palette.graphics.Palette.from(bmp).generate()
                (palette.lightVibrantSwatch ?: palette.vibrantSwatch
                    ?: palette.lightMutedSwatch ?: palette.dominantSwatch)?.rgb
            }.getOrNull()
        }
        if (rgb != null) {
            var c = Color(rgb)
            if (androidx.core.graphics.ColorUtils.calculateLuminance(rgb) < 0.5) {
                c = androidx.compose.ui.graphics.lerp(c, Color.White, 0.6f)
            }
            color.value = c
        }
    }
    return color.value
}

/// Top10 + genre-row shaping, ported from the Swift HomeScreen displayCategories.
@Composable
private fun displayCategories(): List<MediaCategory> {
    val state = AppGraph.appState
    return remember(state.categories.toList(), state.animeCategories.toList()) {
        val movieCat = state.categories.firstOrNull { it.id == "trending_movies" || it.id == "trakt_trending_movies" }
        val seriesCat = state.categories.firstOrNull { it.id == "trending_series" || it.id == "trakt_trending_series" }
        val animeCat = state.animeCategories.firstOrNull { it.id == "anime_trending" || it.title.lowercase().contains("trending") }
        val movies = movieCat?.items ?: emptyList()
        val series = seriesCat?.items ?: emptyList()
        val anime = animeCat?.items ?: emptyList()

        val out = ArrayList<MediaCategory>()
        var mi = 0; var si = 0; var ai = 0
        fun roundRobin(limit: Int): List<MediaItem> {
            val r = ArrayList<MediaItem>()
            while (r.size < limit && (mi < movies.size || si < series.size || ai < anime.size)) {
                if (mi < movies.size) { r.add(movies[mi]); mi++; if (r.size >= limit) break }
                if (si < series.size) { r.add(series[si]); si++; if (r.size >= limit) break }
                if (ai < anime.size) { r.add(anime[ai]); ai++; if (r.size >= limit) break }
            }
            return r
        }
        val top10 = roundRobin(10)
        if (top10.isNotEmpty()) out.add(MediaCategory("top_10_trending", "Top 10 Trending", MediaType.MOVIE, top10,
            "The most watched movies, TV shows, and anime this week"))
        if (movies.isNotEmpty()) out.add(MediaCategory("top_10_trending_movies", "Top 10 Trending Movies", MediaType.MOVIE, movies.take(10)))
        if (series.isNotEmpty()) out.add(MediaCategory("top_10_trending_series", "Top 10 Trending TV Shows", MediaType.SERIES, series.take(10)))
        if (anime.isNotEmpty()) out.add(MediaCategory("top_10_trending_anime", "Top 10 Trending Anime", MediaType.ANIME, anime.take(10)))
        val trending = roundRobin(40)
        if (trending.isNotEmpty()) out.add(MediaCategory("trending_all", "Trending", MediaType.MOVIE, trending,
            "Popular movies, TV shows, and anime this week"))

        val allItems = movies + anime + series
        for (genre in listOf("Action", "Comedy", "Drama", "Science Fiction", "Animation", "Horror", "Mystery")) {
            val seen = HashSet<String>()
            val picks = ArrayList<MediaItem>()
            for (item in allItems) if (item.genres.contains(genre) && seen.add(item.id)) picks.add(item)
            if (picks.size >= 4) {
                out.add(MediaCategory(
                    "genre_${genre.lowercase().replace(" ", "_")}", "Trending $genre", MediaType.MOVIE,
                    picks.take(15), "Popular $genre titles to watch this week",
                ))
            }
        }
        if (out.isEmpty()) state.categories.toList() else out
    }
}

package com.finix.omniverse.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
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
import com.finix.omniverse.Http
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.MediaType
import com.finix.omniverse.objects
import com.finix.omniverse.optArrayOrNull
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.launch
import org.json.JSONObject

private val onePaceSubLanguages = listOf(
    "en" to "English", "en cc" to "English (CC)", "alternate en" to "English (Alternate)",
    "ar" to "Arabic", "de" to "German", "es" to "Spanish", "fr" to "French", "it" to "Italian",
    "pt" to "Portuguese", "ru" to "Russian", "tr" to "Turkish", "cs" to "Czech", "fi" to "Finnish", "pl" to "Polish",
)
private val onePaceRepoFoldersDefault = listOf(
    "00 Cover Stories and Specials", "01 Romance Dawn", "02 Orange Town", "03 Syrup Village", "04 Gaimon",
    "05 Baratie", "06 Arlong Park", "07 Loguetown", "08 Reverse Mountain", "09 Whisky Peak", "10 Little Garden",
    "11 Drum Island", "12 Alabasta", "13 Jaya", "14 Skypiea", "16 Water Seven", "17 Enies Lobby",
    "19 Thriller Bark", "22 Impel Down", "23 Marineford", "24 Post War", "25 Return to Sabaody",
    "26 Fishman Island", "27 Punk Hazard", "28 Dressrosa", "29 Zou", "30 Whole Cake Island", "31 Reverie", "32 Wano", "33 Egghead",
)
private const val DESKTOP_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

private data class OnePacePlaylist(val id: String, val resolution: Int)
private data class OnePacePlaylistGroup(val sub: String, val dub: String, val playlists: List<OnePacePlaylist>)
private data class OnePaceArc(val title: String, val slug: String, val description: String, val chapters: String,
                              val animeEpisodes: String, val backdropUrl: String, val playlistGroups: List<OnePacePlaylistGroup>)
private data class OnePaceEpisode(val id: String, val name: String, val size: Int, val episodeNumber: Int, val cleanTitle: String)

@Composable
fun OnePaceScreen(nav: NavController) {
    val state = AppGraph.appState
    val scope = rememberCoroutineScope()

    var loadingArcs by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var arcs by remember { mutableStateOf<List<OnePaceArc>>(emptyList()) }
    var selectedSeason by remember { mutableIntStateOf(1) }
    var groupIndex by remember { mutableIntStateOf(0) }
    var subLang by remember { mutableStateOf("en") }

    var loadingEpisodes by remember { mutableStateOf(false) }
    var episodes by remember { mutableStateOf<List<OnePaceEpisode>>(emptyList()) }
    var episodesError by remember { mutableStateOf<String?>(null) }
    var repoFolders by remember { mutableStateOf(onePaceRepoFoldersDefault) }
    var resolving by remember { mutableStateOf(false) }

    var seasonMenu by remember { mutableStateOf(false) }
    var audioMenu by remember { mutableStateOf(false) }
    var subMenu by remember { mutableStateOf(false) }

    val arc = arcs.getOrNull(selectedSeason - 1)

    suspend fun loadEpisodes(a: OnePaceArc) {
        loadingEpisodes = true; episodesError = null; episodes = emptyList()
        try {
            if (a.playlistGroups.isEmpty()) throw RuntimeException("No streamable playlist groups found for this arc.")
            val gi = if (groupIndex >= a.playlistGroups.size) 0 else groupIndex
            val pg = a.playlistGroups[gi]
            if (pg.playlists.isEmpty()) throw RuntimeException("No playlists available inside this audio track.")
            val listId = pg.playlists.maxByOrNull { it.resolution }!!.id
            episodes = fetchOnePaceEpisodes(listId)
        } catch (t: Throwable) { episodesError = "$t" } finally { loadingEpisodes = false }
    }

    LaunchedEffect(Unit) {
        loadingArcs = true; error = null
        repoFolders = fetchFolders() ?: onePaceRepoFoldersDefault
        try {
            val fetched = fetchOnePaceArcs()
            arcs = fetched
            loadingArcs = false
            if (fetched.isNotEmpty()) {
                val active = state.continueWatching.firstOrNull { it.itemId == "onepace:anime:21" || (it.itemId == "anilist:anime:21" && it.title == "One Pace") }
                selectedSeason = active?.seasonNumber?.takeIf { it in 1..fetched.size } ?: 1
                groupIndex = 0
                loadEpisodes(fetched[selectedSeason - 1])
            }
        } catch (t: Throwable) { loadingArcs = false; error = "$t" }
    }

    fun play(episode: OnePaceEpisode) {
        val a = arc ?: return
        resolving = true
        scope.launch {
            val subUrl = runCatching { resolveSubtitleUrl(repoFolders, a.title, episode.episodeNumber, subLang) }.getOrNull() ?: ""
            val fileUrl = buildOnePaceStreamUrl(episode.id, state.credentials.pixeldrainApiKey)
            val dummyItem = onePaceDummyItem(a)
            val mapped = mappedAnimeEpisode(a.animeEpisodes, episode.episodeNumber, episodes.size)
            val playerEpisode = MediaEpisode(selectedSeason, episode.episodeNumber, episode.cleanTitle,
                "Covered Manga Chapters: ${a.chapters}\nCovered Anime Episodes: ${a.animeEpisodes}")
            resolving = false
            RouteArgs.player = PlayerArgs("One Pace • ${a.title} • ${episode.cleanTitle}", fileUrl, emptyMap(),
                dummyItem, playerEpisode, subUrl, 0, mapped)
            nav.navigate("player")
        }
    }

    Box(Modifier.fillMaxSize()) {
        when {
            loadingArcs -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = LiquidColors.Cyan) }
            error != null -> Column(Modifier.fillMaxSize(), Arrangement.Center, Alignment.CenterHorizontally) {
                Text("Failed to load One Pace details", color = Color.White.copy(alpha = 0.7f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            else -> androidx.compose.foundation.layout.BoxWithConstraints {
                val wide = maxWidth >= 900.dp
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    if (arc != null) {
                        Box(Modifier.fillMaxWidth().height(if (wide) 520.dp else 640.dp)) {
                            PosterImage(arc.backdropUrl.ifEmpty { null }, Modifier.fillMaxSize(), ContentScale.Crop)
                            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.27f), Color.Black))))
                            Column(Modifier.align(Alignment.BottomStart).widthIn(max = 640.dp).padding(horizontal = if (wide) 54.dp else 26.dp).padding(bottom = 24.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Box(Modifier.clip(RoundedCornerShape(4.dp)).background(LiquidColors.Cyan).padding(horizontal = 10.dp, vertical = 4.dp)) {
                                        Text("ONE PACE", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black)
                                    }
                                    Text("Season $selectedSeason • ${episodes.size} Episodes", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                }
                                Text(arc.title, color = Color.White, fontSize = if (wide) 46.sp else 32.sp, fontWeight = FontWeight.Black)
                                Text(arc.description, color = Color.White.copy(alpha = 0.85f), fontSize = 15.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                                if (episodes.isNotEmpty()) {
                                    Box(Modifier.clip(RoundedCornerShape(24.dp)).background(Color.White).tvFocusable(onClick = { play(episodes[0]) }, corner = 24).padding(horizontal = 24.dp, vertical = 12.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Icon(Icons.Filled.PlayArrow, null, tint = Color.Black, modifier = Modifier.size(18.dp))
                                            Text("Play S1E1", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Column(Modifier.padding(horizontal = if (wide) 54.dp else 26.dp)) {
                        Spacer(Modifier.height(24.dp))
                        // Season selector
                        Box {
                            Row(Modifier.tvFocusable(onClick = { seasonMenu = true }, corner = 4).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("${arc?.title ?: "Arc"} (Season $selectedSeason)", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                                Icon(Icons.Filled.KeyboardArrowDown, null, tint = Color.White.copy(alpha = 0.7f))
                            }
                            DropdownMenu(seasonMenu, { seasonMenu = false }) {
                                arcs.forEachIndexed { idx, a ->
                                    DropdownMenuItem(text = { Text("Season ${idx + 1}: ${a.title}") }, onClick = {
                                        seasonMenu = false; selectedSeason = idx + 1; groupIndex = 0; scope.launch { loadEpisodes(a) }
                                    })
                                }
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                            // Audio
                            arc?.let { a ->
                                if (a.playlistGroups.isNotEmpty()) {
                                    val gi = groupIndex.coerceIn(0, a.playlistGroups.size - 1)
                                    Box {
                                        Text("🔊 ${audioGroupLabel(a.playlistGroups[gi])}  ▾", color = Color.White.copy(alpha = 0.7f), fontSize = 15.sp, fontWeight = FontWeight.Bold,
                                            modifier = Modifier.tvFocusable(onClick = { audioMenu = true }, corner = 4).padding(6.dp))
                                        DropdownMenu(audioMenu, { audioMenu = false }) {
                                            a.playlistGroups.forEachIndexed { idx, pg ->
                                                DropdownMenuItem(text = { Text(audioGroupLabel(pg)) }, onClick = { audioMenu = false; groupIndex = idx; scope.launch { loadEpisodes(a) } })
                                            }
                                        }
                                    }
                                }
                            }
                            // Subtitles
                            Box {
                                val label = onePaceSubLanguages.firstOrNull { it.first == subLang }?.second ?: "English"
                                Text("💬 Subs: $label  ▾", color = Color.White.copy(alpha = 0.7f), fontSize = 15.sp, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.tvFocusable(onClick = { subMenu = true }, corner = 4).padding(6.dp))
                                DropdownMenu(subMenu, { subMenu = false }) {
                                    onePaceSubLanguages.forEach { (code, name) -> DropdownMenuItem(text = { Text(name) }, onClick = { subMenu = false; subLang = code }) }
                                }
                            }
                        }
                        Spacer(Modifier.height(20.dp))
                        when {
                            loadingEpisodes -> Box(Modifier.fillMaxWidth().padding(vertical = 48.dp), Alignment.Center) { CircularProgressIndicator(color = LiquidColors.Cyan) }
                            episodesError != null -> Text("Error loading episodes: $episodesError", color = Color.White.copy(alpha = 0.6f), fontSize = 14.sp, modifier = Modifier.padding(vertical = 48.dp))
                            episodes.isEmpty() -> Text("No episodes listed in this quality / category.", color = Color.White.copy(alpha = 0.54f), fontSize = 14.sp, modifier = Modifier.padding(vertical = 32.dp))
                            else -> LazyRow(Modifier.height(180.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                itemsIndexed(episodes, key = { _, e -> e.id }) { _, ep -> OnePaceEpisodeCard(ep) { play(ep) } }
                            }
                        }
                        Spacer(Modifier.height(48.dp))
                    }
                }
            }
        }
        if (resolving) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)), Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                CircularProgressIndicator(color = LiquidColors.Cyan)
                Text("Resolving Subtitles...", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun OnePaceEpisodeCard(ep: OnePaceEpisode, onTap: () -> Unit) {
    Box(Modifier.width(250.dp).height(180.dp).tvFocusable(onClick = onTap).clip(RoundedCornerShape(12.dp))) {
        PosterImage("https://pixeldrain.net/api/file/${ep.id}/thumbnail", Modifier.fillMaxSize(), ContentScale.Crop)
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f)))))
        Column(Modifier.align(Alignment.BottomStart).padding(12.dp)) {
            Text("EPISODE ${ep.episodeNumber}", color = LiquidColors.Cyan, fontSize = 10.sp, fontWeight = FontWeight.Black)
            Text(ep.cleanTitle, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text("${ep.size / (1024 * 1024)} MB", color = Color.White.copy(alpha = 0.54f), fontSize = 10.sp)
        }
    }
}

// MARK: - Scraping / parsing (ported from one_pace_screen.dart)

private suspend fun fetchFolders(): List<String>? = runCatching {
    val r = Http.request("https://api.github.com/repos/one-pace/one-pace-public-subtitles/contents/main",
        headers = mapOf("User-Agent" to "Mozilla/5.0"), timeoutMs = 3000)
    if (!r.ok) return null
    val arr = org.json.JSONArray(r.body)
    val live = arr.objects().filter { it.optString("type") == "dir" }.map { it.optString("name") }.filter { it.isNotEmpty() }
    live.ifEmpty { null }
}.getOrNull()

private suspend fun fetchOnePaceArcs(): List<OnePaceArc> {
    val r = Http.request("https://onepace.net/en/watch", headers = mapOf("User-Agent" to DESKTOP_UA))
    if (!r.ok) throw RuntimeException("Failed to load One Pace website: ${r.status}")
    val html = r.body
    val regex = Regex("self\\.__next_f\\.push\\(\\[1,\"(.*?)\"\\]\\)", RegexOption.DOT_MATCHES_ALL)
    val block = regex.findAll(html).map { it.groupValues[1] }.firstOrNull { it.contains("playlistGroups") }
        ?: throw RuntimeException("Could not parse One Pace data block.")
    val unescaped = block.replace("\\\"", "\"").replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t").replace("\\\\", "\\")
    var startIdx = unescaped.indexOf("{\"timeline\"")
    if (startIdx < 0) startIdx = unescaped.indexOf("{\"data\"")
    if (startIdx < 0) throw RuntimeException("Could not unescape data block.")
    val jsonChunk = extractBalancedJson(unescaped, startIdx)
    val decoded = runCatching { JSONObject(jsonChunk) }.getOrNull() ?: throw RuntimeException("Could not decode One Pace JSON.")
    val data = decoded.optJSONObject("data") ?: decoded
    val timeline = data.optJSONObject("timeline") ?: throw RuntimeException("No timeline.")
    val segments = timeline.optArrayOrNull("segments") ?: throw RuntimeException("No timeline segments.")
    return segments.objects().map { seg ->
        val backdrops = seg.optArrayOrNull("backdrops")
        var backdropUrl = ""
        backdrops?.optJSONObject(0)?.optString("src")?.takeIf { it.isNotEmpty() }?.let {
            backdropUrl = if (it.startsWith("http")) it else "https://onepace.net$it"
        }
        val groups = seg.optArrayOrNull("playlistGroups")?.objects()?.map { pg ->
            val playlists = pg.optArrayOrNull("playlists")?.objects()?.map { pl ->
                OnePacePlaylist(pl.optString("id"), pl.optInt("resolution"))
            } ?: emptyList()
            OnePacePlaylistGroup(pg.optString("sub"), pg.optString("dub"), playlists)
        } ?: emptyList()
        OnePaceArc(seg.optString("title"), seg.optString("slug"), seg.optString("description"),
            seg.optString("chapters"), seg.optString("episodes"), backdropUrl, groups)
    }
}

private suspend fun fetchOnePaceEpisodes(listId: String): List<OnePaceEpisode> {
    val r = Http.request("https://pixeldrain.net/api/list/$listId")
    if (!r.ok) throw RuntimeException("Failed to load Pixeldrain server files")
    val files = JSONObject(r.body).optArrayOrNull("files") ?: return emptyList()
    return files.objects().mapIndexed { i, f ->
        val name = f.optString("name")
        var clean = name
            .replace(Regex("\\[One\\s+Pace\\]", RegexOption.IGNORE_CASE), "")
            .replace(Regex("\\[[a-zA-Z0-9\\s-]+\\]"), "")
            .replace(Regex("\\.mp4$", RegexOption.IGNORE_CASE), "").trim()
        if (clean.startsWith("]")) clean = clean.drop(1).trim()
        OnePaceEpisode(f.optString("id"), name, f.optInt("size"), i + 1, clean.ifEmpty { "Episode ${i + 1}" })
    }
}

private suspend fun resolveSubtitleUrl(repoFolders: List<String>, arcTitle: String, epNum: Int, langCode: String): String {
    val episodePadded = "%02d".format(epNum)
    fun normalize(s: String) = s.lowercase().replace(Regex("[^a-z0-9]"), "")
    val normalizedArc = normalize(arcTitle)
    var matchedFolder = repoFolders.firstOrNull { val nf = normalize(it); nf.contains(normalizedArc) || normalizedArc.contains(nf) }
    if (matchedFolder == null) arcTitle.split(" ").firstOrNull()?.let { fw -> matchedFolder = repoFolders.firstOrNull { normalize(it).contains(normalize(fw)) } }
    val folder = matchedFolder ?: return ""
    val encodedFolder = java.net.URLEncoder.encode(folder, "UTF-8").replace("+", "%20")
    fun candidate(suffix: String) =
        "https://raw.githubusercontent.com/one-pace/one-pace-public-subtitles/main/main/$encodedFolder/$episodePadded/$normalizedArc%20$episodePadded%20${suffix.replace(" ", "%20")}.ass"
    val candidates = listOf(candidate(langCode), candidate("en"), candidate("en cc"))
    for (url in candidates) {
        val ok = runCatching { Http.request(url, method = "HEAD", timeoutMs = 1000).status == 200 }.getOrDefault(false)
        if (ok) return url
    }
    return candidate(langCode)
}

private fun extractBalancedJson(text: String, startIdx: Int): String {
    var balance = 0
    var i = startIdx
    while (i < text.length) {
        when (text[i]) { '{' -> balance++; '}' -> { balance--; if (balance == 0) return text.substring(startIdx, i + 1) } }
        i++
    }
    return text.substring(startIdx)
}

private fun audioGroupLabel(pg: OnePacePlaylistGroup): String {
    val sub = pg.sub.lowercase(); val dub = pg.dub.lowercase()
    if (sub == "en" && dub == "ja") return "Japanese Audio (English Subs)"
    if (sub == "en" && dub == "en") return "English Dub (with Closed Captions)"
    if (dub == "en") return "English Dub (No Subs)"
    val subLabel = if (sub == "\$undefined") "No Subs" else "${sub.uppercase()} Subs"
    return "${dub.uppercase()} Audio ($subLabel)"
}

/// Builds the One Pace stream URL with the user's policy ordering:
/// GameDrive userscript bypass (faster Pixeldrain loading): fetch the proxy list
/// and use the first *reachable* proxy, like the userscript does.
/// Fallback (no proxy works / fetch fails) = direct Pixeldrain + optional api_key.
internal suspend fun buildOnePaceStreamUrl(fileId: String, pixeldrainApiKey: String): String {
    val apiKey = pixeldrainApiKey.trim()
    val direct = "https://pixeldrain.net/api/file/$fileId" + if (apiKey.isNotEmpty()) "?api_key=$apiKey" else ""
    val working = runCatching {
        val r = Http.request("https://pixeldrain-bypass.gamedrive.org/api/proxy.json", timeoutMs = 2000)
        if (!r.ok) return@runCatching null
        val proxies = JSONObject(r.body).optArrayOrNull("proxies")
        val list = (0 until (proxies?.length() ?: 0)).mapNotNull { proxies?.optString(it) }
            .map { it.trim() }.filter { it.isNotEmpty() }.take(3)
        for (p in list) {
            val clean = if (p.startsWith("http")) p else "https://$p"
            val normalized = if (clean.endsWith("/")) clean else "$clean/"
            val candidate = "$normalized$fileId"
            val ok = runCatching { Http.request(candidate, method = "HEAD", timeoutMs = 1500).status < 500 }.getOrDefault(false)
            if (ok) return@runCatching candidate
        }
        null
    }.getOrNull()
    return working ?: direct
}

/// Direct Pixeldrain fallback URL used by the player error listener for One Pace.
internal fun officialPixeldrainUrl(fileId: String, pixeldrainApiKey: String): String {
    val apiKey = pixeldrainApiKey.trim()
    var url = "https://pixeldrain.net/api/file/$fileId"
    if (apiKey.isNotEmpty()) url += "?api_key=$apiKey"
    return url
}

private fun onePaceDummyItem(a: OnePaceArc): MediaItem = MediaItem(
    id = "onepace:anime:21", type = MediaType.SERIES, title = "One Pace", overview = a.description,
    posterPath = "/k73H7nbaGo76tH7nI1gG6P3g6W4Z.jpg",
    backdropPath = a.backdropUrl.replace("https://onepace.net", ""),
    genres = listOf("Action", "Adventure", "Animation", "Fantasy", "Comedy"),
)

/// Result of resolving a One Pace Continue Watching entry into a playable player route.
internal data class OnePaceResume(
    val title: String, val url: String, val item: MediaItem,
    val episode: MediaEpisode, val subtitleUrl: String, val aniSkipEpisode: Int,
)

/// Full arc/episode resolution for resuming a One Pace Continue Watching entry.
/// Mirrors OnePaceScreen: arc index = seasonNumber-1, English-sub playlist group
/// (else first), episodes via Pixeldrain list, find by episodeNumber, resolve
/// subtitle, build GameDrive-primary URL, compute AniSkip-mapped One Piece episode.
/// Returns null if resolution fails (caller should fall back to opening the screen).
internal suspend fun resolveOnePaceResume(
    seasonNumber: Int, episodeNumber: Int, pixeldrainApiKey: String,
): OnePaceResume? = runCatching {
    val arcs = fetchOnePaceArcs()
    val arc = arcs.getOrNull(seasonNumber - 1) ?: return null
    if (arc.playlistGroups.isEmpty()) return null
    // Prefer the English-sub (Japanese-audio) group, else the first group.
    val group = arc.playlistGroups.firstOrNull { it.sub.lowercase() == "en" && it.dub.lowercase() == "ja" }
        ?: arc.playlistGroups.first()
    if (group.playlists.isEmpty()) return null
    val listId = group.playlists.maxByOrNull { it.resolution }!!.id
    val episodes = fetchOnePaceEpisodes(listId)
    val episode = episodes.firstOrNull { it.episodeNumber == episodeNumber } ?: return null
    val repoFolders = fetchFolders() ?: onePaceRepoFoldersDefault
    val subUrl = runCatching { resolveSubtitleUrl(repoFolders, arc.title, episode.episodeNumber, "en") }.getOrNull() ?: ""
    val url = buildOnePaceStreamUrl(episode.id, pixeldrainApiKey)
    val mapped = mappedAnimeEpisode(arc.animeEpisodes, episode.episodeNumber, episodes.size)
    val playerEpisode = MediaEpisode(seasonNumber, episode.episodeNumber, episode.cleanTitle,
        "Covered Manga Chapters: ${arc.chapters}\nCovered Anime Episodes: ${arc.animeEpisodes}")
    OnePaceResume("One Pace • ${arc.title} • ${episode.cleanTitle}", url, onePaceDummyItem(arc),
        playerEpisode, subUrl, mapped)
}.getOrNull()

private fun mappedAnimeEpisode(episodesStr: String, epIndex: Int, totalEpisodes: Int): Int {
    val epNumbers = ArrayList<Int>()
    for (part in episodesStr.split(",")) {
        val clean = part.trim()
        if (clean.contains("-")) {
            val rp = clean.split("-")
            if (rp.size == 2) { val s = rp[0].trim().toIntOrNull(); val e = rp[1].trim().toIntOrNull(); if (s != null && e != null) for (n in s..e) epNumbers.add(n) }
        } else clean.toIntOrNull()?.let { epNumbers.add(it) }
    }
    if (epNumbers.isEmpty()) return 1
    if (totalEpisodes <= 1) return epNumbers.first()
    val ratio = (epIndex - 1).toDouble() / (totalEpisodes - 1)
    val targetIndex = (Math.round(ratio * (epNumbers.size - 1)).toInt()).coerceIn(0, epNumbers.size - 1)
    return epNumbers[targetIndex]
}

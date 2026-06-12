package com.finix.omniverse.ui

import android.content.pm.ActivityInfo
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem as Media3Item
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.finix.omniverse.AppGraph
import com.finix.omniverse.Http
import com.finix.omniverse.KeepScreenOn
import com.finix.omniverse.LocalActivity
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.MediaType
import com.finix.omniverse.optArrayOrNull
import com.finix.omniverse.objects
import com.finix.omniverse.optObjectOrNull
import com.finix.omniverse.optDoubleOrNull
import com.finix.omniverse.optStringOrNull
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import org.json.JSONObject

private data class SkipInterval(val type: String, val startMs: Int, val endMs: Int)
private data class CaptionCue(val startMs: Int, val endMs: Int, val text: String)

private fun formatTime(ms: Int): String {
    val total = (ms.coerceAtLeast(0)) / 1000
    val h = total / 3600; val m = (total % 3600) / 60; val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
fun PlayerScreen(
    args: PlayerArgs,
    onPlayNext: (PlayerArgs) -> Unit = {},
    onPlayVidsrc: (VidsrcArgs) -> Unit = {},
    onOpenDetail: (MediaItem) -> Unit = {},
    onClose: () -> Unit,
) {
    val appState = AppGraph.appState
    val context = LocalContext.current
    val activity = LocalActivity.current
    val scope = rememberCoroutineScope()

    KeepScreenOn(true)
    // Landscape lock
    DisposableEffect(Unit) {
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        onDispose { activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }

    val isAnime = args.item?.type == MediaType.ANIME || args.item?.isAnime == true

    // Build ExoPlayer with OkHttp datasource passing custom headers.
    val player = remember {
        val ok = com.finix.omniverse.Http.streamingClient
        val httpFactory = OkHttpDataSource.Factory(ok).apply {
            if (args.headers.isNotEmpty()) setDefaultRequestProperties(args.headers)
        }
        val dsFactory = DefaultDataSource.Factory(context, httpFactory)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dsFactory))
            .build().apply {
                setMediaItem(Media3Item.fromUri(args.url))
                playWhenReady = true
                prepare()
            }
    }

    var durationMs by remember { mutableIntStateOf(0) }
    var positionMs by remember { mutableIntStateOf(0) }
    var isPlaying by remember { mutableStateOf(false) }
    var isReady by remember { mutableStateOf(false) }
    var hasError by remember { mutableStateOf(false) }
    // One Pace: on playback error, fall back once from the GameDrive proxy to the
    // direct Pixeldrain (+api_key) URL, preserving position.
    val isOnePace = args.item?.title == "One Pace"
    var currentUrl by remember { mutableStateOf(args.url) }
    var fallbackAttempted by remember { mutableStateOf(false) }
    // Stall auto-recovery: bounded re-resolve when playback freezes mid-stream.
    var reconnectAttempts by remember { mutableIntStateOf(0) }
    var controlsVisible by remember { mutableStateOf(true) }
    var interactionCount by remember { mutableIntStateOf(0) }
    var showCaptions by remember { mutableStateOf(true) }
    var toast by remember { mutableStateOf<String?>(null) }
    var currentCaption by remember { mutableStateOf("") }
    val skipIntervals = remember { mutableListOf<SkipInterval>() }
    val captionCues = remember { mutableListOf<CaptionCue>() }
    val skippedTypes = remember { HashSet<String>() }

    // Scrobble bookkeeping
    var activeScrobble by remember { mutableStateOf(false) }
    var finishedScrobble by remember { mutableStateOf(false) }
    var wasPlaying by remember { mutableStateOf(false) }

    fun progressPct(): Double = if (durationMs > 0) positionMs.toDouble() / durationMs * 100 else 0.0
    fun isComplete(): Boolean = durationMs > 0 && (positionMs >= durationMs - 2000)

    // Autoplay / end-of-show recommendations
    var episodeFinishedFired by remember { mutableStateOf(false) }
    var recommendations by remember { mutableStateOf<List<MediaItem>?>(null) }
    var loadingRecommendations by remember { mutableStateOf(false) }
    val nextEp = remember(args.item, args.episode) {
        if (args.item != null && args.episode != null) {
            nextEpisodeFor(args.item, args.episode)
        } else null
    }

    // Fired once when the episode ends (natural end or AniSkip "ed"): autoplay the
    // next episode, or load recommendations for the end screen if nothing's left.
    val onEpisodeFinished: () -> Unit = onEpisodeFinished@{
        if (episodeFinishedFired) return@onEpisodeFinished
        episodeFinishedFired = true
        scope.launch {
            when (val next = resolveNextEpisode(args.item, args.episode, appState)) {
                is AutoplayNext.Play -> onPlayNext(next.args)
                is AutoplayNext.Embed -> onPlayVidsrc(next.args)
                null -> {
                    loadingRecommendations = true
                    val recs = appState.recommendationsFor(args.item)
                    loadingRecommendations = false
                    if (recs.isEmpty()) onClose() else recommendations = recs
                }
            }
        }
    }

    // Player listener
    DisposableEffect(player) {
        val listener = object : androidx.media3.common.Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == androidx.media3.common.Player.STATE_READY) {
                    reconnectAttempts = 0
                    if (!isReady) {
                        isReady = true
                        val d = player.duration
                        if (d > 0) durationMs = d.toInt()
                        args.startPositionMs?.takeIf { it > 0 }?.let { player.seekTo(it.toLong()) }
                    }
                }
                if (state == androidx.media3.common.Player.STATE_ENDED) {
                    if (!finishedScrobble) {
                        finishedScrobble = true; activeScrobble = false
                        args.item?.let { scope.launch { appState.stopTraktPlayback(it, 100.0, args.episode) } }
                    }
                    onEpisodeFinished()
                }
            }
            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                if (reconnectAttempts < 3) {
                    reconnectAttempts++
                    val resumePos = player.currentPosition.coerceAtLeast(0)
                    if (isOnePace) {
                        val fileId = currentUrl.trimEnd('/').substringAfterLast('/').substringBefore('?')
                        if (fileId.isNotEmpty()) {
                            toast = "Reconnecting…"
                            scope.launch {
                                val bypassUrl = buildOnePaceStreamUrl(fileId, appState.credentials.pixeldrainApiKey)
                                currentUrl = bypassUrl
                                player.setMediaItem(Media3Item.fromUri(bypassUrl))
                                player.prepare()
                                if (resumePos > 0) player.seekTo(resumePos)
                                player.playWhenReady = true
                            }
                            return
                        }
                    } else if (args.item != null) {
                        toast = "Reconnecting…"
                        scope.launch {
                            val src = runCatching { appState.playbackSourcesFor(args.item, args.episode) }
                                .getOrNull()?.firstOrNull { it.isDirect }
                            if (src != null) {
                                currentUrl = src.url
                                player.setMediaItem(Media3Item.fromUri(src.url))
                                player.prepare()
                                if (resumePos > 0) player.seekTo(resumePos)
                                player.playWhenReady = true
                            } else {
                                hasError = true
                            }
                        }
                        return
                    }
                }
                hasError = true
            }
        }
        player.addListener(listener)
        onDispose {
            // pause scrobble if active
            if (args.item != null && activeScrobble && !finishedScrobble) {
                scope.launch { appState.pauseTraktPlayback(args.item, progressPct(), args.episode) }
            }
            if (args.item != null && durationMs > 0) {
                scope.launch {
                    appState.recordProgress(args.item, positionMs, durationMs, args.episode)
                    if (appState.credentials.hasTraktUser) {
                        runCatching { appState.syncSettingsToTrakt(silent = true) }
                    }
                }
            }
            player.removeListener(listener)
            player.release()
        }
    }

    // 0.5s ticker: position, captions, auto-skip, scrobble lifecycle
    LaunchedEffect(player) {
        while (isActive) {
            positionMs = player.currentPosition.toInt()
            if (player.duration > 0) durationMs = player.duration.toInt()
            isPlaying = player.isPlaying
            // captions
            currentCaption = if (captionCues.isEmpty()) "" else
                captionCues.firstOrNull { positionMs >= it.startMs && positionMs <= it.endMs }?.text ?: ""
            // auto-skip
            if (skipIntervals.isNotEmpty() && isPlaying) {
                for (interval in skipIntervals) {
                    if (interval.type in skippedTypes) continue
                    if (positionMs >= interval.startMs && positionMs < interval.endMs - 1000) {
                        skippedTypes.add(interval.type)
                        if (interval.type == "ed") {
                            toast = "Skipped Ending"; finishedScrobble = true; activeScrobble = false
                            args.item?.let { scope.launch { appState.stopTraktPlayback(it, 100.0, args.episode) } }
                            onEpisodeFinished()
                        } else {
                            player.seekTo(interval.endMs.toLong())
                            toast = when (interval.type) { "op" -> "Skipped Intro"; "recap" -> "Skipped Recap"; else -> "Skipped" }
                        }
                        break
                    }
                }
            }
            // scrobble change
            if (args.item != null && isReady) {
                if (isPlaying && !activeScrobble) {
                    activeScrobble = true; finishedScrobble = false; wasPlaying = true
                    scope.launch { appState.startTraktPlayback(args.item, progressPct(), args.episode) }
                } else if (!isPlaying && wasPlaying && !isComplete()) {
                    wasPlaying = false; activeScrobble = false
                    scope.launch { appState.pauseTraktPlayback(args.item, progressPct(), args.episode) }
                }
            }

            // Autoplay next episode when countdown reaches 0 (1s or less remaining)
            val hasNextEp = args.item != null && args.episode != null && (isOnePace || nextEpisodeFor(args.item, args.episode) != null)
            if (hasNextEp && durationMs > 0 && durationMs - positionMs <= 1000) {
                onEpisodeFinished()
            }

            delay(500)
        }
    }

    // 10s progress record + scrobble keep-alive
    LaunchedEffect(player) {
        while (isActive) {
            delay(10_000)
            if (args.item != null && durationMs > 0) {
                appState.recordProgress(args.item, positionMs, durationMs, args.episode)
                if (activeScrobble && !finishedScrobble) appState.startTraktPlayback(args.item, progressPct(), args.episode)
            }
        }
    }

    // Stall watchdog: re-resolve and rebuild the stream at the same position when
    // playback freezes for ~12s (sampled every ~3s). Two stall signatures both count:
    //   (a) STUCK BUFFERING — STATE_BUFFERING with playWhenReady=true but isPlaying()==false
    //       (the stream is trying to play but never delivers; this is the case the user
    //       reports for anime + One Pace where recovery never fired before).
    //   (b) FROZEN PLAYBACK — actively playing (isPlaying()==true) but currentPosition
    //       has not advanced.
    // Excluded: user pause (playWhenReady=false), seeking, ended, hard error, not ready.
    // One Pace/gamedrive/pixeldrain -> official Pixeldrain (+api_key) URL. Other items
    // -> re-fetch playback sources, take the first direct stream. Bounded to 3 retries.
    LaunchedEffect(player) {
        var lastPos = -1L
        var stalledFor = 0
        while (isActive) {
            delay(3000)
            val state = player.playbackState
            val buffering = state == androidx.media3.common.Player.STATE_BUFFERING
            val ended = state == androidx.media3.common.Player.STATE_ENDED
            // Skip legitimate non-stall states: not ready, user-paused, ended, hard error.
            if (!isReady || ended || player.playerError != null || !player.playWhenReady) {
                lastPos = player.currentPosition; stalledFor = 0; continue
            }
            val stuckBuffering = buffering && player.playWhenReady && !player.isPlaying
            val pos = player.currentPosition
            val frozenPlaying = player.isPlaying && lastPos >= 0 && pos == lastPos
            if (stuckBuffering || frozenPlaying) {
                stalledFor += 3
            } else {
                stalledFor = 0
                if (player.isPlaying && pos > lastPos) {
                    reconnectAttempts = 0
                }
            }
            lastPos = pos
            if (stalledFor >= 12 && reconnectAttempts < 3) {
                reconnectAttempts++
                stalledFor = 0
                val savedPos = pos.coerceAtLeast(0)
                toast = "Reconnecting…"
                val rebuildAsPixeldrain = isOnePace ||
                    currentUrl.contains("gamedrive", ignoreCase = true) ||
                    currentUrl.contains("pixeldrain", ignoreCase = true)
                if (rebuildAsPixeldrain) {
                    val fileId = currentUrl.trimEnd('/').substringAfterLast('/').substringBefore('?')
                    if (fileId.isNotEmpty()) {
                        val bypassUrl = buildOnePaceStreamUrl(fileId, appState.credentials.pixeldrainApiKey)
                        currentUrl = bypassUrl
                        player.setMediaItem(Media3Item.fromUri(bypassUrl))
                        player.prepare()
                        if (savedPos > 0) player.seekTo(savedPos)
                        player.playWhenReady = true
                    }
                } else if (args.item != null) {
                    val src = runCatching { appState.playbackSourcesFor(args.item, args.episode) }
                        .getOrNull()?.firstOrNull { it.isDirect }
                    if (src != null) {
                        currentUrl = src.url
                        player.setMediaItem(Media3Item.fromUri(src.url))
                        player.prepare()
                        if (savedPos > 0) player.seekTo(savedPos)
                        player.playWhenReady = true
                    }
                }
                lastPos = -1
            }
        }
    }

    // Fetch AniSkip once ready
    LaunchedEffect(isReady, durationMs) {
        if (!isReady || durationMs <= 0) return@LaunchedEffect
        val title = args.item?.title?.lowercase() ?: ""
        val id = args.item?.id?.lowercase() ?: ""
        if (title == "one pace" || title.contains("one pace") || id.startsWith("onepace:") || id.contains("onepace")) return@LaunchedEffect
        val anilistId = args.item?.anilistId ?: return@LaunchedEffect
        val ep = args.episode ?: return@LaunchedEffect
        val intervals = fetchAniSkip(anilistId, args.aniSkipEpisode ?: ep.episodeNumber, durationMs / 1000)
        if (intervals.isNotEmpty()) { skipIntervals.clear(); skipIntervals.addAll(intervals) }
    }

    // Fetch subtitles
    LaunchedEffect(args.subtitleUrl) {
        val url = args.subtitleUrl.trim()
        if (url.startsWith("http")) {
            runCatching {
                val r = Http.request(url, timeoutMs = 12_000)
                if (r.ok) { val cues = parseCaptions(r.body); captionCues.clear(); captionCues.addAll(cues) }
            }
        }
    }

    // Auto-hide controls 1s
    LaunchedEffect(controlsVisible, interactionCount) {
        if (controlsVisible) { delay(1000); controlsVisible = false }
    }

    val showManualSkip = isAnime && skipIntervals.isEmpty()

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (hasError) {
            PlayerMessage("Could not open this stream.", onClose)
        } else {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        useController = false
                        this.player = player
                        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
            // tap to toggle controls
            Box(Modifier.fillMaxSize().pointerInput(Unit) {
                detectTapGestures {
                    controlsVisible = !controlsVisible
                    if (controlsVisible) {
                        interactionCount++
                    }
                }
            })

            if (!isReady) {
                Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = LiquidColors.Cyan)
                        Spacer(Modifier.height(16.dp))
                        Text(args.title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text("Opening stream...", color = Color.White.copy(alpha = 0.72f), fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // Captions overlay
            if (showCaptions && currentCaption.isNotEmpty()) {
                Box(Modifier.fillMaxSize().padding(bottom = if (controlsVisible) 150.dp else 42.dp), Alignment.BottomCenter) {
                    Text(currentCaption, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.background(Color.Black.copy(alpha = 0.58f)).padding(horizontal = 10.dp, vertical = 4.dp))
                }
            }

            if (controlsVisible && isReady) {
                PlayerControls(
                    args.title, args.episode, isPlaying, durationMs, positionMs, showCaptions,
                    onClose = onClose,
                    onPlayPause = { if (player.isPlaying) player.pause() else player.play(); controlsVisible = true; interactionCount++ },
                    onSeekBy = { player.seekTo((player.currentPosition + it).coerceIn(0, durationMs.toLong())); controlsVisible = true; interactionCount++ },
                    onScrub = { f -> player.seekTo((durationMs * f).toLong()); controlsVisible = true; interactionCount++ },
                    onToggleCaptions = { showCaptions = it },
                )
            }

            // Manual Skip Intro
            if (showManualSkip && positionMs / 1000 in 5..120) {
                Box(Modifier.fillMaxSize().padding(end = 28.dp, bottom = 110.dp), Alignment.BottomEnd) {
                    Row(
                        Modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.66f))
                            .border(1.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(50))
                            .tvFocusable(onClick = { player.seekTo(player.currentPosition + 85_000) }, corner = 50)
                            .padding(horizontal = 18.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Filled.SkipNext, null, tint = Color.White, modifier = Modifier.size(18.dp))
                        Text("Skip Intro", color = Color.White, fontWeight = FontWeight.Black, fontSize = 15.sp)
                    }
                }
            }

            // Toast
            toast?.let { t ->
                LaunchedEffect(t) { delay(2000); toast = null }
                Box(Modifier.fillMaxSize().padding(top = 40.dp), Alignment.TopCenter) {
                    Row(
                        Modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.6f)).padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.Filled.SkipNext, null, tint = LiquidColors.Cyan)
                        Text(t, color = Color.White, fontWeight = FontWeight.Black, fontSize = 16.sp)
                    }
                }
            }

            // Next Episode Countdown Overlay (last 10s of play)
            val hasNextEp = args.item != null && args.episode != null && (isOnePace || nextEp != null)
            val remainingSecs = maxOf(0, (durationMs - positionMs) / 1000)
            val isLast10Sec = durationMs > 0 && (durationMs - positionMs <= 10000)

            if (isLast10Sec && hasNextEp) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(end = 28.dp, bottom = if (controlsVisible) 120.dp else 36.dp),
                    contentAlignment = Alignment.BottomEnd
                ) {
                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color.Black.copy(alpha = 0.85f))
                            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                            .tvFocusable(onClick = { onEpisodeFinished() }, corner = 16)
                            .padding(horizontal = 20.dp, vertical = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(CircleShape)
                                .background(Color.White),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                Icons.Filled.PlayArrow,
                                contentDescription = "Play",
                                tint = Color.Black,
                                modifier = Modifier.size(16.dp)
                            )
                        }

                        Column(horizontalAlignment = Alignment.Start) {
                            Text(
                                text = "Next Episode Playing in ${remainingSecs}s",
                                color = LiquidColors.Cyan,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = if (isOnePace) "Next Episode" else "S${nextEp?.seasonNumber ?: 0} • E${nextEp?.episodeNumber ?: 0}: ${nextEp?.title ?: ""}",
                                color = Color.White,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.widthIn(max = 240.dp)
                            )
                        }

                        Box(modifier = Modifier.size(36.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(
                                progress = remainingSecs / 10f,
                                color = LiquidColors.Cyan,
                                trackColor = Color.White.copy(alpha = 0.2f),
                                strokeWidth = 3.dp,
                                modifier = Modifier.fillMaxSize()
                            )
                            Text(
                                text = "$remainingSecs",
                                color = Color.White,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }

            // End-of-show recommendations
            if (recommendations != null || loadingRecommendations) {
                RecommendationsEndScreen(
                    showTitle = (args.item?.title ?: args.title).substringBefore("•").trim(),
                    recommendations = recommendations,
                    loading = loadingRecommendations,
                    onSelect = onOpenDetail,
                    onClose = onClose,
                )
            }
        }
    }
}

/// Shown over the finished player when there are no more episodes/seasons. Lists
/// "because you watched" recommendations; tapping one opens its detail screen.
@Composable
internal fun RecommendationsEndScreen(
    showTitle: String,
    recommendations: List<MediaItem>?,
    loading: Boolean,
    onSelect: (MediaItem) -> Unit,
    onClose: () -> Unit,
) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.92f))) {
        Column(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 36.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text("You're all caught up", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black)
                    Text(
                        "Because you watched $showTitle",
                        color = Color.White.copy(alpha = 0.7f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                    )
                }
                Box(
                    Modifier.size(44.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f))
                        .tvFocusable(onClick = onClose, corner = 50),
                    Alignment.Center,
                ) { Icon(Icons.Filled.Close, "Close", tint = Color.White) }
            }
            Spacer(Modifier.height(24.dp))
            when {
                loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = LiquidColors.Cyan) }
                !recommendations.isNullOrEmpty() -> androidx.compose.foundation.lazy.LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(recommendations) { rec ->
                        Box(Modifier.width(132.dp)) { MediaPosterCard(rec, onTap = onSelect) }
                    }
                }
                else -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    Text("No recommendations available.", color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp)
                }
            }
        }
    }
}

@Composable
private fun PlayerControls(
    title: String, episode: MediaEpisode?, isPlaying: Boolean, durationMs: Int, positionMs: Int, showCaptions: Boolean,
    onClose: () -> Unit, onPlayPause: () -> Unit, onSeekBy: (Long) -> Unit, onScrub: (Float) -> Unit, onToggleCaptions: (Boolean) -> Unit,
) {
    val isLive = durationMs <= 0
    Box(Modifier.fillMaxSize().background(
        Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.66f), Color.Transparent, Color.Transparent, Color.Black.copy(alpha = 0.8f)))
    )) {
        Column(Modifier.fillMaxSize().padding(horizontal = 24.dp, vertical = 16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircleBtn(Icons.Filled.Close, onClose)
                Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.weight(1f))
            // On a TV remote, land focus on the central play/pause control each time the
            // overlay appears so the D-pad can immediately operate playback.
            val isTv = isTvDevice()
            val playFocus = remember { FocusRequester() }
            LaunchedEffect(Unit) { if (isTv) runCatching { playFocus.requestFocus() } }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                LargeBtn(Icons.Filled.Replay10, 82.dp) { onSeekBy(-10_000) }
                Spacer(Modifier.size(56.dp))
                LargeBtn(if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, 112.dp, focusRequester = playFocus, onClick = onPlayPause)
                Spacer(Modifier.size(56.dp))
                LargeBtn(Icons.Filled.Forward10, 82.dp) { onSeekBy(10_000) }
            }
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(if (isLive) "LIVE" else formatTime(positionMs), color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    Scrubber(if (durationMs > 0) positionMs.toFloat() / durationMs else 0f, isLive, Modifier.weight(1f), onScrub)
                    Text(if (isLive) "" else "-" + formatTime(durationMs - positionMs), color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }
                val display = if (episode != null) "$title • S${episode.seasonNumber}E${episode.episodeNumber}" else title
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(display, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    if (!isLive) {
                        Box(
                            Modifier.size(44.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.1f))
                                .tvFocusable(onClick = { onToggleCaptions(!showCaptions) }, corner = 22),
                            contentAlignment = Alignment.Center,
                        ) { Text("CC", color = if (showCaptions) LiquidColors.Cyan else Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Scrubber(fraction: Float, isLive: Boolean, modifier: Modifier, onScrub: (Float) -> Unit) {
    Box(
        modifier.height(28.dp).pointerInput(isLive) {
            if (!isLive) detectTapGestures { offset -> onScrub((offset.x / size.width).coerceIn(0f, 1f)) }
        },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.12f)))
        Box(Modifier.fillMaxWidth(if (isLive) 1f else fraction.coerceIn(0f, 1f)).height(4.dp).clip(RoundedCornerShape(50)).background(Color.White))
    }
}

@Composable
private fun CircleBtn(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier.size(58.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.4f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
            .tvFocusable(onClick = onClick, corner = 29),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(24.dp)) }
}

@Composable
private fun LargeBtn(icon: androidx.compose.ui.graphics.vector.ImageVector, size: androidx.compose.ui.unit.Dp, focusRequester: FocusRequester? = null, onClick: () -> Unit) {
    Box(
        Modifier.size(size).clip(CircleShape).background(Color.Black.copy(alpha = 0.4f))
            .border(1.dp, Color.White.copy(alpha = 0.11f), CircleShape)
            .tvFocusable(onClick = onClick, corner = 100, focusRequester = focusRequester),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(size * 0.42f)) }
}

@Composable
private fun PlayerMessage(message: String, onClose: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black), Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Text(message, color = Color.White.copy(alpha = 0.82f), fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Box(
                Modifier.clip(RoundedCornerShape(50)).background(LiquidColors.Cyan)
                    .tvFocusable(onClick = onClose, corner = 50).padding(horizontal = 24.dp, vertical = 12.dp),
            ) { Text("Close", color = Color.Black, fontWeight = FontWeight.Bold) }
        }
    }
}

// MARK: - AniSkip + caption parsing (ported)

private suspend fun fetchAniSkip(anilistId: Int, episode: Int, lengthSec: Int): List<SkipInterval> {
    suspend fun fetch(url: String): List<SkipInterval> = withContext(Dispatchers.IO) {
        runCatching {
            val r = Http.request(url, headers = mapOf("Accept" to "application/json"), timeoutMs = 4000)
            if (r.status != 200) return@runCatching emptyList<SkipInterval>()
            val obj = JSONObject(r.body)
            if (obj.optBoolean("found") != true) return@runCatching emptyList<SkipInterval>()
            val results = obj.optArrayOrNull("results") ?: return@runCatching emptyList<SkipInterval>()
            results.objects().mapNotNull { e ->
                val interval = e.optObjectOrNull("interval") ?: return@mapNotNull null
                val type = e.optStringOrNull("skipType") ?: e.optStringOrNull("skip_type") ?: return@mapNotNull null
                val start = interval.optDoubleOrNull("startTime") ?: interval.optDoubleOrNull("start_time") ?: return@mapNotNull null
                val end = interval.optDoubleOrNull("endTime") ?: interval.optDoubleOrNull("end_time") ?: return@mapNotNull null
                if (end <= start) return@mapNotNull null
                SkipInterval(type, (start * 1000).toInt(), (end * 1000).toInt())
            }
        }.getOrDefault(emptyList())
    }
    var list = fetch("https://api.aniskip.com/v2/skip-times/$anilistId/$episode?types[]=op&types[]=ed&types[]=recap&episodeLength=$lengthSec")
    if (list.isNotEmpty()) return list
    list = fetch("https://api.aniskip.com/v2/skip-times/$anilistId/$episode?types[]=op&types[]=ed&types[]=recap&episodeLength=1440")
    if (list.isNotEmpty()) return list
    return fetch("https://api.aniskip.com/v1/skip-times/$anilistId/$episode?types=op&types=ed")
}

private fun parseCaptions(contents: String): List<CaptionCue> {
    val normalized = contents.replace("\r\n", "\n").replace("\r", "\n")
    val blocks = normalized.split(Regex("\\n\\s*\\n"))
    val cues = ArrayList<CaptionCue>()
    for (block in blocks) {
        val lines = block.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        val timeIndex = lines.indexOfFirst { it.contains("-->") }
        if (timeIndex < 0 || timeIndex == lines.size - 1) continue
        val range = captionRange(lines[timeIndex]) ?: continue
        val text = lines.subList(timeIndex + 1, lines.size).joinToString("\n")
            .replace(Regex("<[^>]*>"), "").replace(Regex("\\{[^}]*\\}"), "")
        cues.add(CaptionCue(range.first, range.second, text))
    }
    return cues
}

private fun captionRange(line: String): Pair<Int, Int>? {
    val parts = line.split("-->")
    if (parts.size < 2) return null
    val start = captionTime(parts[0]) ?: return null
    val endRaw = parts[1].trim().split(Regex("[ \t]")).firstOrNull() ?: parts[1]
    val end = captionTime(endRaw) ?: return null
    if (end <= start) return null
    return start to end
}

private fun captionTime(value: String): Int? {
    val clean = value.trim().replace(",", ".")
    val pieces = clean.split(":")
    if (pieces.size < 2 || pieces.size > 3) return null
    val secParts = pieces.last().split(".")
    val seconds = secParts[0].toIntOrNull() ?: return null
    var millis = 0
    if (secParts.size > 1) millis = secParts[1].padEnd(3, '0').take(3).toIntOrNull() ?: 0
    val minutes = pieces[pieces.size - 2].toIntOrNull() ?: return null
    val hours = if (pieces.size == 3) (pieces[0].toIntOrNull() ?: return null) else 0
    if (hours < 0) return null
    return (hours * 3600 + minutes * 60 + seconds) * 1000 + millis
}

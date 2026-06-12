package com.finix.omniverse.ui

import android.annotation.SuppressLint
import android.content.pm.ActivityInfo
import android.graphics.Color as AndroidColor
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.finix.omniverse.AppGraph
import com.finix.omniverse.KeepScreenOn
import com.finix.omniverse.LocalActivity
import com.finix.omniverse.MediaItem
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

private data class VServer(val name: String, val hash: String)
private enum class VStage { EMBED, PLAYER }

private const val POLL_ATTEMPTS = 14
private const val TURNSTILE_ATTEMPTS = 45
private const val POLL_MS = 700L

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun VidsrcResolveScreen(
    args: VidsrcArgs,
    onPlayNext: (PlayerArgs) -> Unit = {},
    onPlayVidsrc: (VidsrcArgs) -> Unit = {},
    onOpenDetail: (MediaItem) -> Unit = {},
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    val scope = rememberCoroutineScope()
    val appState = AppGraph.appState

    KeepScreenOn(true)
    DisposableEffect(Unit) {
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        activity?.window?.let { window ->
            val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
            controller.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        onDispose {
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            activity?.window?.let { window ->
                val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
                controller.show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            }
        }
    }

    var status by remember { mutableStateOf("Loading embed...") }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var finished by remember { mutableStateOf(false) }
    val servers = remember { mutableStateListOf<VServer>() }
    var currentServer by remember { mutableIntStateOf(0) }
    var serverMenu by remember { mutableStateOf(false) }

    // End-of-show autoplay / recommendations
    var handledFinish by remember { mutableStateOf(false) }
    var recommendations by remember { mutableStateOf<List<MediaItem>?>(null) }
    var loadingRecommendations by remember { mutableStateOf(false) }

    // state machine vars (held outside compose to avoid recomposition churn)
    val machine = remember {
        object {
            var domainIndex = 0
            var stage = VStage.EMBED
            var cloudnestraBase: String? = null
            var pollJob: Job? = null
        }
    }
    val webRef = remember { arrayOfNulls<WebView>(1) }

    suspend fun runJs(js: String): String? {
        val wv = webRef[0] ?: return null
        val deferred = CompletableDeferred<String?>()
        wv.evaluateJavascript(js) { raw ->
            val s = raw?.takeIf { it != "null" }?.trim('"')?.replace("\\\"", "\"")?.replace("\\\\", "\\")
            deferred.complete(s)
        }
        return deferred.await()
    }

    fun loadCurrentDomain() {
        machine.pollJob?.cancel()
        if (finished) return
        if (machine.domainIndex >= args.embedUrls.size) {
            errorMessage = "Could not resolve a working VidSrc server (tried ${args.embedUrls.size} domain(s))."
            return
        }
        machine.stage = VStage.EMBED
        servers.clear(); currentServer = 0; machine.cloudnestraBase = null
        val url = args.embedUrls[machine.domainIndex]
        status = "Loading ${Uri.parse(url).host ?: "embed"}..."
        errorMessage = null
        webRef[0]?.loadUrl(url)
    }

    fun nextDomain() { machine.pollJob?.cancel(); if (finished) return; machine.domainIndex++; loadCurrentDomain() }

    fun navigateToServer() {
        if (finished) return
        val base = machine.cloudnestraBase ?: run { nextDomain(); return }
        if (currentServer >= servers.size) { nextDomain(); return }
        machine.stage = VStage.PLAYER
        val s = servers[currentServer]
        status = "Loading ${s.name.ifEmpty { "server ${currentServer + 1}" }}..."
        webRef[0]?.loadUrl("$base/rcp/${s.hash}")
    }

    fun tryNextServer() { machine.pollJob?.cancel(); currentServer++; navigateToServer() }

    fun waitForEmbed() {
        status = "Looking for servers..."
        machine.pollJob?.cancel()
        machine.pollJob = scope.launch {
            var attempt = 0
            while (true) {
                if (finished) return@launch
                attempt++
                val text = runJs(WebGuards.embedProbeJs)
                val json = text?.let { runCatching { JSONObject(it) }.getOrNull() }
                if (json == null) { delay(POLL_MS); continue }
                val list = json.optJSONArray("servers")
                val parsed = ArrayList<VServer>()
                if (list != null) for (i in 0 until list.length()) {
                    val e = list.optJSONObject(i) ?: continue
                    val hash = e.optString("hash"); if (hash.isEmpty()) continue
                    parsed.add(VServer(e.optString("name"), hash))
                }
                val hasChallenge = json.optBoolean("hasChallenge")
                val iframeSrc = json.optString("iframeSrc")
                if (hasChallenge && parsed.isEmpty()) {
                    status = "Solving Cloudflare check (${attempt}s)..."
                    if (attempt >= POLL_ATTEMPTS) { nextDomain(); return@launch }
                    delay(POLL_MS); continue
                }
                if (parsed.isNotEmpty() && iframeSrc.isNotEmpty()) {
                    servers.clear(); servers.addAll(parsed); currentServer = 0
                    val raw = if (iframeSrc.startsWith("//")) "https:$iframeSrc" else iframeSrc
                    val uri = runCatching { Uri.parse(raw) }.getOrNull()
                    machine.cloudnestraBase = if (uri?.scheme != null && uri.host != null) "${uri.scheme}://${uri.host}" else "https://cloudnestra.com"
                    navigateToServer(); return@launch
                }
                if (attempt >= POLL_ATTEMPTS) { nextDomain(); return@launch }
                delay(POLL_MS)
            }
        }
    }

    // End detected (or movie closed): autoplay the next episode if there is one,
    // otherwise show recommendations.
    fun onEpisodeFinished() {
        if (handledFinish) return
        handledFinish = true
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

    // Polls reachable frames for an ended <video> once playback has begun. No-op
    // for cross-origin players (the close fallback covers those for movies).
    fun startEndWatch() {
        scope.launch {
            while (true) {
                delay(2000)
                if (handledFinish) return@launch
                val t = runJs(WebGuards.videoEndedProbeJs)
                val j = t?.let { runCatching { JSONObject(it) }.getOrNull() }
                if (j?.optBoolean("ended") == true) { onEpisodeFinished(); return@launch }
            }
        }
    }

    // Movies show recommendations on close (fallback); everything else just closes.
    fun closeOrRecommend() {
        if (finished && args.episode == null && recommendations == null && !loadingRecommendations && !handledFinish) {
            onEpisodeFinished()
        } else {
            onClose()
        }
    }

    fun onPlayerLoaded() {
        machine.pollJob?.cancel()
        machine.pollJob = scope.launch {
            var attempt = 0
            while (true) {
                if (finished) return@launch
                attempt++
                val text = runJs(WebGuards.playerProbeJs)
                val json = text?.let { runCatching { JSONObject(it) }.getOrNull() }
                if (json == null) { delay(POLL_MS); continue }
                val hasChallenge = json.optBoolean("hasChallenge")
                val hasTurnstile = json.optBoolean("hasTurnstile")
                val hasRcp = json.optBoolean("hasRcpToken")
                val hasPlay = json.optBoolean("hasPlayButton")
                val iframeLoaded = json.optBoolean("iframeLoaded")
                if (hasChallenge) {
                    status = "Cloudflare check on cloudnestra (${attempt}s)..."
                    if (attempt >= POLL_ATTEMPTS) { tryNextServer(); return@launch }
                    delay(POLL_MS); continue
                }
                if (hasTurnstile && !hasRcp) {
                    status = "Verifying with Cloudflare Turnstile (${attempt}s)..."
                    if (attempt >= TURNSTILE_ATTEMPTS) { tryNextServer(); return@launch }
                    delay(POLL_MS); continue
                }
                if (hasPlay && !iframeLoaded) runJs(WebGuards.clickPlayJs)
                if (hasPlay || iframeLoaded) {
                    finished = true
                    status = if (iframeLoaded) "Playing in WebView. Tap inside the player if it pauses." else "Server ready — tap the play button."
                    startEndWatch()
                    return@launch
                }
                if (attempt >= POLL_ATTEMPTS) { tryNextServer(); return@launch }
                delay(POLL_MS)
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize().background(Color.Black)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).tvFocusable(onClick = { closeOrRecommend() }, corner = 20), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Close, "Close", tint = Color.White)
            }
            Text(args.title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
            if (servers.size > 1) {
                Box {
                    Text("Servers", color = Color.White, fontSize = 14.sp, modifier = Modifier.tvFocusable(onClick = { serverMenu = true }, corner = 6).padding(8.dp))
                    DropdownMenu(serverMenu, { serverMenu = false }) {
                        servers.forEachIndexed { i, s ->
                            DropdownMenuItem(text = { Text((s.name.ifEmpty { "Server ${i + 1}" }) + (if (i == currentServer) " ✓" else "")) }, onClick = {
                                serverMenu = false; machine.pollJob?.cancel(); finished = false; currentServer = i; navigateToServer()
                            })
                        }
                    }
                }
            }
        }
        if (!finished) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (errorMessage == null) CircularProgressIndicator(color = Color.White, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text(errorMessage ?: status, color = Color.White.copy(alpha = 0.8f), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    setLayerType(android.view.View.LAYER_TYPE_HARDWARE, null)
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.databaseEnabled = true
                    settings.mediaPlaybackRequiresUserGesture = false
                    settings.setSupportMultipleWindows(false)
                    // The cloudnestra player loads http subresources inside an
                    // https page — allow mixed content or the stream never loads.
                    settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                    settings.useWideViewPort = true
                    settings.loadWithOverviewMode = true
                    settings.allowContentAccess = true
                    settings.allowFileAccess = true
                    // A WebChromeClient is required for HTML5 video playback in WebView.
                    webChromeClient = android.webkit.WebChromeClient()
                    // NO custom UA — Turnstile fingerprints WebViews; keep the real UA.
                    setBackgroundColor(AndroidColor.BLACK)
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                            if (request?.isForMainFrame != true) return false
                            val url = (request.url?.toString() ?: "").lowercase()
                            val allow = url.startsWith("about:") || url.contains("vidsrc-embed") || url.contains("vsembed") ||
                                url.contains("vsrc.") || url.contains("vidsrcme") || url.contains("cloudnestra") ||
                                url.contains("rcp/") || url.contains("prorcp/")
                            return !allow
                        }
                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                            // Defeat iframe sandboxing as early as possible.
                            view?.evaluateJavascript(WebGuards.unsandboxJs, null)
                        }
                        override fun onPageFinished(view: WebView?, url: String?) {
                            if (finished) return
                            view?.evaluateJavascript(WebGuards.unsandboxJs, null)
                            view?.evaluateJavascript(WebGuards.vidsrcGuardJs, null)
                            if (machine.stage == VStage.EMBED) waitForEmbed() else onPlayerLoaded()
                        }
                        override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: android.webkit.WebResourceError?) {
                            if (request?.isForMainFrame != true) return
                            if (machine.stage == VStage.EMBED) nextDomain() else tryNextServer()
                        }
                    }
                    webRef[0] = this
                    post { loadCurrentDomain() }
                }
            },
            modifier = Modifier.fillMaxSize().weight(1f),
        )
        if (errorMessage != null) {
            Row(Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.86f)).padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    Modifier.clip(RoundedCornerShape(8.dp)).border(1.dp, Color.White.copy(alpha = 0.4f), RoundedCornerShape(8.dp))
                        .tvFocusable(onClick = { machine.domainIndex = 0; errorMessage = null; loadCurrentDomain() }, corner = 8).padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) { Icon(Icons.Filled.Refresh, null, tint = Color.White, modifier = Modifier.size(18.dp)); Text("Retry", color = Color.White) }
                Text("Close", color = Color.White, modifier = Modifier.tvFocusable(onClick = onClose, corner = 6).padding(8.dp))
            }
        }
    }

        // End-of-show recommendations
        if (recommendations != null || loadingRecommendations) {
            RecommendationsEndScreen(
                showTitle = args.item.title,
                recommendations = recommendations,
                loading = loadingRecommendations,
                onSelect = onOpenDetail,
                onClose = onClose,
            )
        }
    }

    DisposableEffect(Unit) { onDispose { machine.pollJob?.cancel() } }
}

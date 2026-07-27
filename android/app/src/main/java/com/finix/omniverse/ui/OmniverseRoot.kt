package com.finix.omniverse.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import com.finix.omniverse.AppGraph
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.UserSettings
import com.finix.omniverse.ui.theme.LiquidBackdrop
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.delay

/// In-memory route argument holder. MediaItem/PlaybackSource are not nav-arg
/// serializable, so pushed routes read their payload from here. Set before
/// navigating to the matching route.
object RouteArgs {
    var detailItem: MediaItem? = null
    var detailFocus: DetailFocusArgs? = null
    var player: PlayerArgs? = null
    var web: WebArgs? = null
    var vidsrc: VidsrcArgs? = null
    var captcha: CaptchaArgs? = null
}

data class PlayerArgs(
    val title: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val item: MediaItem? = null,
    val episode: MediaEpisode? = null,
    val subtitleUrl: String = "",
    val startPositionMs: Int? = null,
    val aniSkipEpisode: Int? = null,
)

data class DetailFocusArgs(
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
)

data class WebArgs(
    val title: String,
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val item: MediaItem? = null,
    val episode: MediaEpisode? = null,
)

/// Captcha WebView payload. [onComplete] retries the request that hit
/// NEED_CAPTCHA, once the user has solved it and cookies are banked.
data class CaptchaArgs(val url: String, val onComplete: (() -> Unit)? = null)

data class VidsrcArgs(
    val item: MediaItem,
    val title: String,
    val embedUrls: List<String>,
    val episode: MediaEpisode? = null,
)

data class ShellTab(val id: String, val title: String, val icon: ImageVector)

@Composable
fun OmniverseRoot() {
    val state = AppGraph.appState
    LaunchedEffect(Unit) { if (!state.initialized) state.initialize() }

    val nav = rememberNavController()
    var showSplash by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(true) }

    Box(Modifier.fillMaxSize()) {
        LiquidBackdrop()
        if (showSplash) {
            AnimatedSplash { showSplash = false }
        } else if (!state.credentials.hasTraktUser) {
            OnboardingScreen()
        } else {
            NavHost(navController = nav, startDestination = "shell") {
                fun returnToDetail(fromRoute: String, item: MediaItem?, episode: MediaEpisode?) {
                    if (item == null) {
                        nav.popBackStack()
                        return
                    }
                    RouteArgs.detailItem = item
                    RouteArgs.detailFocus = DetailFocusArgs(
                        seasonNumber = episode?.seasonNumber,
                        episodeNumber = episode?.episodeNumber,
                    )
                    val hadDetail = nav.popBackStack("detail", inclusive = true)
                    if (hadDetail) {
                        nav.navigate("detail")
                    } else {
                        nav.navigate("detail") { popUpTo(fromRoute) { inclusive = true } }
                    }
                }

                composable("shell") { Shell(nav) }
                composable("detail") {
                    RouteArgs.detailItem?.let { MediaDetailScreen(it, nav, RouteArgs.detailFocus) }
                }
                composable("player") {
                    RouteArgs.player?.let { args ->
                        PlayerScreen(
                            args,
                            onPlayNext = {
                                RouteArgs.player = it
                                nav.navigate("player") { popUpTo("player") { inclusive = true } }
                            },
                            onPlayVidsrc = {
                                RouteArgs.vidsrc = it
                                nav.navigate("vidsrc") { popUpTo("player") { inclusive = true } }
                            },
                            onOpenDetail = {
                                RouteArgs.detailItem = it
                                RouteArgs.detailFocus = null
                                nav.navigate("detail") { popUpTo("player") { inclusive = true } }
                            },
                            onClose = { returnToDetail("player", args.item, args.episode) },
                        )
                    }
                }
                composable("web") {
                    RouteArgs.web?.let { args ->
                        WebEmbedScreen(args) { returnToDetail("web", args.item, args.episode) }
                    }
                }

                composable("vidsrc") {
                    RouteArgs.vidsrc?.let { vargs ->
                        VidsrcResolveScreen(
                            vargs,
                            onPlayNext = {
                                RouteArgs.player = it
                                nav.navigate("player") { popUpTo("vidsrc") { inclusive = true } }
                            },
                            onPlayVidsrc = {
                                RouteArgs.vidsrc = it
                                nav.navigate("vidsrc") { popUpTo("vidsrc") { inclusive = true } }
                            },
                            onOpenDetail = {
                                RouteArgs.detailItem = it
                                RouteArgs.detailFocus = null
                                nav.navigate("detail") { popUpTo("vidsrc") { inclusive = true } }
                            },
                            onClose = { returnToDetail("vidsrc", vargs.item, vargs.episode) },
                        )
                    }
                }
            }
        }

        // Universal secure pairing confirmation dialog overlay
        if (state.pendingPairingId != null) {
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { state.cancelPairing() },
                title = { Text("Pairing Request", color = Color.White, fontWeight = FontWeight.Bold) },
                text = {
                    Text(
                        "Do you want to pair and sync your settings with this device (ID: ${state.pendingPairingId})?",
                        color = Color.White.copy(alpha = 0.7f)
                    )
                },
                confirmButton = {
                    androidx.compose.material3.TextButton(onClick = { state.confirmPairing() }) {
                        Text("Confirm", color = LiquidColors.Cyan, fontWeight = FontWeight.Bold)
                    }
                },
                dismissButton = {
                    androidx.compose.material3.TextButton(onClick = { state.cancelPairing() }) {
                        Text("Cancel", color = Color.White.copy(alpha = 0.5f))
                    }
                },
                containerColor = Color(0xFF12141C),
                textContentColor = Color.White
            )
        }

        MessageBanner()
    }
}

fun resolveAvailableTabs(settings: UserSettings): List<ShellTab> {
    return buildList {
        if (settings.showMoviesTv) {
            add(ShellTab("home", "Home", Icons.Filled.Home))
            add(ShellTab("movies", "Movies", Icons.Filled.PlayCircle))
            add(ShellTab("shows", "Shows", Icons.Filled.PlayCircle))
        }
        if (settings.showLiveTv) {
            add(ShellTab("livetv", "Live TV", Icons.Filled.LiveTv))
        }
        add(ShellTab("search", "Search", Icons.Filled.Search))
        add(ShellTab("settings", "Settings", Icons.Filled.Settings))
    }
}

@Composable
private fun Shell(nav: androidx.navigation.NavController) {
    val state = AppGraph.appState
    val tabs = remember(state.settings) { resolveAvailableTabs(state.settings) }
    var requestedTabId by rememberSaveable { mutableStateOf("home") }

    val activeId = if (tabs.any { it.id == requestedTabId }) requestedTabId else (tabs.firstOrNull()?.id ?: "settings")

    val isTv = isTvDevice()
    val navFocus = remember { FocusRequester() }
    LaunchedEffect(isTv) {
        if (isTv) runCatching { navFocus.requestFocus() }
    }

    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 820.dp
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().padding(start = if (wide) 96.dp else 0.dp)) {
                androidx.compose.animation.AnimatedContent(
                    targetState = activeId,
                    transitionSpec = {
                        (androidx.compose.animation.fadeIn(animationSpec = androidx.compose.animation.core.tween(240)) +
                                androidx.compose.animation.scaleIn(initialScale = 0.97f, animationSpec = androidx.compose.animation.core.tween(240)))
                            .togetherWith(
                                androidx.compose.animation.fadeOut(animationSpec = androidx.compose.animation.core.tween(160))
                            )
                    },
                    label = "screenTransition"
                ) { target ->
                    when (target) {
                        "home" -> HomeScreen(nav)
                        "movies" -> HomeScreen(nav)
                        "shows" -> HomeScreen(nav)
                        "livetv" -> LiveTvScreen(nav)
                        "search" -> SearchScreen(nav)
                        else -> SettingsScreen()
                    }
                }
            }
            if (wide) {
                GlassRail(
                    tabs,
                    activeId,
                    navFocus,
                    Modifier.align(Alignment.CenterStart).padding(start = 16.dp, top = 24.dp, bottom = 24.dp)
                ) { requestedTabId = it }
            } else {
                GlassTabBar(
                    tabs,
                    activeId,
                    navFocus,
                    Modifier.align(Alignment.BottomCenter).navigationBarsPadding()
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                ) { requestedTabId = it }
            }
        }
    }
}

@Composable
private fun GlassTabBar(
    tabs: List<ShellTab>,
    activeId: String,
    focusRequester: FocusRequester,
    modifier: Modifier,
    onSelect: (String) -> Unit
) {
    val scrollState = rememberScrollState()
    Row(
        modifier
            .clip(RoundedCornerShape(32.dp))
            .background(Color.Black.copy(alpha = 0.65f))
            .border(1.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(32.dp))
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .horizontalScroll(scrollState),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        tabs.forEach { tab ->
            val active = tab.id == activeId
            Row(
                Modifier
                    .clip(RoundedCornerShape(24.dp))
                    .then(if (active) Modifier.background(LiquidColors.Cyan) else Modifier)
                    .tvFocusable(
                        onClick = { onSelect(tab.id) },
                        corner = 24,
                        focusRequester = if (active) focusRequester else null
                    )
                    .padding(horizontal = if (active) 16.dp else 12.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    tab.icon,
                    tab.title,
                    tint = if (active) LiquidColors.Ink else Color.White.copy(alpha = 0.75f),
                    modifier = Modifier.size(18.dp),
                )
                AnimatedVisibility(visible = active) {
                    Text(
                        tab.title,
                        color = LiquidColors.Ink,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.ExtraBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun GlassRail(
    tabs: List<ShellTab>,
    activeId: String,
    focusRequester: FocusRequester,
    modifier: Modifier,
    onSelect: (String) -> Unit
) {
    Column(
        modifier
            .fillMaxHeight()
            .width(64.dp)
            .clip(RoundedCornerShape(32.dp))
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(32.dp))
            .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(
            Icons.Filled.PlayCircle,
            null,
            tint = LiquidColors.Cyan,
            modifier = Modifier.size(30.dp).padding(bottom = 8.dp)
        )
        tabs.forEach { tab ->
            val active = tab.id == activeId
            Box(
                Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .then(if (active) Modifier.background(LiquidColors.Cyan) else Modifier)
                    .tvFocusable(
                        onClick = { onSelect(tab.id) },
                        corner = 26,
                        focusRequester = if (active) focusRequester else null
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    tab.icon,
                    tab.title,
                    tint = if (active) LiquidColors.Ink else Color.White.copy(alpha = 0.7f),
                    modifier = Modifier.size(21.dp)
                )
            }
        }
    }
}

@Composable
private fun MessageBanner() {
    val state = AppGraph.appState
    val msg = state.message
    LaunchedEffect(msg) {
        if (!msg.isNullOrEmpty()) {
            delay(3000); state.message = null
        }
    }
    AnimatedVisibility(visible = !msg.isNullOrEmpty(), modifier = Modifier.fillMaxWidth().statusBarsPadding()) {
        Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.TopCenter) {
            Box(
                Modifier
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.7f))
                    .border(1.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(50))
                    .padding(horizontal = 16.dp, vertical = 10.dp)
            ) {
                Text(msg ?: "", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
    Spacer(Modifier.height(0.dp))
}

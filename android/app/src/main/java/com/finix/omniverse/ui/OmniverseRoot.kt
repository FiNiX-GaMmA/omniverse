package com.finix.omniverse.ui

import androidx.compose.animation.AnimatedVisibility
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
import com.finix.omniverse.AppGraph
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.ui.theme.LiquidBackdrop
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.delay

/// In-memory route argument holder. MediaItem/PlaybackSource are not nav-arg
/// serializable, so pushed routes read their payload from here. Set before
/// navigating to the matching route.
object RouteArgs {
    var detailItem: MediaItem? = null
    var player: PlayerArgs? = null
    var web: WebArgs? = null
    var vidsrc: VidsrcArgs? = null
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

data class WebArgs(val title: String, val url: String, val headers: Map<String, String> = emptyMap())

data class VidsrcArgs(
    val item: MediaItem,
    val title: String,
    val embedUrls: List<String>,
    val episode: MediaEpisode? = null,
)

private data class ShellTab(val id: String, val title: String, val icon: ImageVector)

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
                composable("shell") { Shell(nav) }
                composable("detail") {
                    RouteArgs.detailItem?.let { MediaDetailScreen(it, nav) }
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
                                nav.navigate("detail") { popUpTo("player") { inclusive = true } }
                            },
                            onClose = { nav.popBackStack() },
                        )
                    }
                }
                composable("web") {
                    RouteArgs.web?.let { WebEmbedScreen(it) { nav.popBackStack() } }
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
                                nav.navigate("detail") { popUpTo("vidsrc") { inclusive = true } }
                            },
                            onClose = { nav.popBackStack() },
                        )
                    }
                }
            }
        }
        MessageBanner()
    }
}

@Composable
private fun Shell(nav: androidx.navigation.NavController) {
    val state = AppGraph.appState
    val tabs = remember(state.settings, state.credentials) {
        buildList {
            if (state.settings.showMoviesTv && state.credentials.hasTmdb)
                add(ShellTab("home", "Home", Icons.Filled.Home))
            if (state.credentials.hasPixeldrain)
                add(ShellTab("onepace", "One Pace", Icons.Filled.PlayCircle))
            if (state.settings.showLiveTv)
                add(ShellTab("livetv", "LiveTV", Icons.Filled.LiveTv))
            add(ShellTab("settings", "Settings", Icons.Filled.Settings))
            if (state.credentials.hasTmdb)
                add(ShellTab("search", "Search", Icons.Filled.Search))
        }
    }
    var selection by rememberSaveable { mutableStateOf(0) }
    val idx = selection.coerceIn(0, (tabs.size - 1).coerceAtLeast(0))
    val activeId = tabs.getOrNull(idx)?.id ?: "settings"

    // On a TV/leanback device, plant initial D-pad focus on the active nav item so a
    // remote always has a reachable, operable landing spot when the Shell opens.
    val isTv = isTvDevice()
    val navFocus = remember { FocusRequester() }
    LaunchedEffect(isTv) {
        if (isTv) runCatching { navFocus.requestFocus() }
    }

    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 820.dp
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().padding(start = if (wide) 96.dp else 0.dp)) {
                when (activeId) {
                    "home" -> HomeScreen(nav)
                    "onepace" -> OnePaceScreen(nav)
                    "livetv" -> LiveTvScreen(nav)
                    "search" -> SearchScreen(nav)
                    else -> SettingsScreen()
                }
            }
            if (wide) {
                GlassRail(tabs, idx, navFocus, Modifier.align(Alignment.CenterStart).padding(start = 16.dp, top = 24.dp, bottom = 24.dp)) { selection = it }
            } else {
                GlassTabBar(tabs, idx, navFocus, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 18.dp, vertical = 8.dp)) { selection = it }
            }
        }
    }
}

@Composable
private fun GlassTabBar(tabs: List<ShellTab>, selected: Int, focusRequester: FocusRequester, modifier: Modifier, onSelect: (Int) -> Unit) {
    Row(
        modifier
            .clip(RoundedCornerShape(26.dp))
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(26.dp))
            .padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        tabs.forEachIndexed { i, tab ->
            val active = i == selected
            Column(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .then(if (active) Modifier.background(LiquidColors.Cyan.copy(alpha = 0.16f)) else Modifier)
                    .tvFocusable(onClick = { onSelect(i) }, corner = 16, focusRequester = if (active) focusRequester else null)
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(tab.icon, tab.title, tint = if (active) LiquidColors.Cyan else Color.White.copy(alpha = 0.62f), modifier = Modifier.size(22.dp))
                Text(tab.title, color = if (active) LiquidColors.Cyan else Color.White.copy(alpha = 0.62f), fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun GlassRail(tabs: List<ShellTab>, selected: Int, focusRequester: FocusRequester, modifier: Modifier, onSelect: (Int) -> Unit) {
    Column(
        modifier
            .fillMaxHeight()
            .width(64.dp)
            .clip(RoundedCornerShape(32.dp))
            .background(Color.Black.copy(alpha = 0.5f))
            .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(32.dp))
            .padding(vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(Icons.Filled.PlayCircle, null, tint = LiquidColors.Cyan, modifier = Modifier.size(30.dp).padding(bottom = 8.dp))
        tabs.forEachIndexed { i, tab ->
            val active = i == selected
            Box(
                Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .then(if (active) Modifier.background(LiquidColors.Cyan) else Modifier)
                    .tvFocusable(onClick = { onSelect(i) }, corner = 26, focusRequester = if (active) focusRequester else null),
                contentAlignment = Alignment.Center,
            ) {
                Icon(tab.icon, tab.title, tint = if (active) LiquidColors.Ink else Color.White.copy(alpha = 0.7f), modifier = Modifier.size(21.dp))
            }
        }
    }
}

@Composable
private fun MessageBanner() {
    val state = AppGraph.appState
    val msg = state.message
    LaunchedEffect(msg) {
        if (!msg.isNullOrEmpty()) { delay(3000); state.message = null }
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

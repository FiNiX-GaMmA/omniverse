package com.finix.omniverse

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.lifecycleScope
import com.finix.omniverse.ui.OmniverseRoot
import com.finix.omniverse.ui.theme.OmniverseTheme
import kotlinx.coroutines.launch

/// Exposes the Activity so screens (e.g. the player) can toggle window flags
/// like FLAG_KEEP_SCREEN_ON and orientation.
val LocalActivity = staticCompositionLocalOf<MainActivity?> { null }

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        applyMaxRefreshRate()

        setContent {
            OmniverseTheme {
                androidx.compose.runtime.CompositionLocalProvider(LocalActivity provides this) {
                    OmniverseRoot()
                }
            }
        }

        // Handle a deep link that launched the app (e.g. Trakt OAuth redirect).
        handleDeepLink(intent)
    }

    /// Trakt/AniList OAuth redirects (omniplay://… / omniverse://…) come back as
    /// a new intent on this singleTask activity. Route them to AppState so the
    /// "Connecting to Trakt…" flow can complete instead of hanging forever.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
    }

    private fun handleDeepLink(intent: Intent?) {
        val uri: Uri = intent?.data ?: return
        val scheme = uri.scheme ?: return
        if (scheme == "omniplay" || scheme == "omniverse") {
            lifecycleScope.launch { AppGraph.appState.handleIncomingUri(uri) }
        }
    }

    override fun onResume() {
        super.onResume()
        applyMaxRefreshRate()
    }

    override fun onStart() {
        super.onStart()
        // Pull the latest watchlist / watch time / last-watched / keys on foreground.
        lifecycleScope.launch { runCatching { AppGraph.appState.syncNow() } }
    }

    override fun onStop() {
        super.onStop()
        // Push the latest local state before the app is backgrounded.
        lifecycleScope.launch { runCatching { AppGraph.appState.syncSettingsToTrakt(silent = true) } }
    }

    /// Drive the display at the MAXIMUM refresh rate the panel supports.
    /// On API 23–30 we set preferredRefreshRate; on API 30+ we pick the
    /// display mode whose refresh rate is highest at the native resolution.
    private fun applyMaxRefreshRate() {
        val attrs = window.attributes
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val modes = display?.supportedModes ?: return
        if (modes.isEmpty()) return

        // Highest refresh rate available.
        val maxRate = modes.maxOf { it.refreshRate }
        // Among modes at (or near) the largest resolution, choose the one with max rate.
        val best = modes
            .sortedWith(compareByDescending<android.view.Display.Mode> { it.physicalWidth * it.physicalHeight }
                .thenByDescending { it.refreshRate })
            .firstOrNull { it.refreshRate >= maxRate - 0.1f } ?: modes.maxByOrNull { it.refreshRate }

        if (best != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            attrs.preferredDisplayModeId = best.modeId
        }
        attrs.preferredRefreshRate = maxRate
        window.attributes = attrs
    }

    fun setKeepScreenOn(on: Boolean) {
        runOnUiThread {
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}

/// Composable helper: keeps the screen awake while present (player uses this).
@androidx.compose.runtime.Composable
fun KeepScreenOn(active: Boolean = true) {
    val activity = LocalActivity.current
    val context = LocalContext.current
    DisposableEffect(active) {
        activity?.setKeepScreenOn(active)
        onDispose { activity?.setKeepScreenOn(false) }
    }
}

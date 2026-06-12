package com.finix.omniverse

import android.app.Application
import android.content.pm.ApplicationInfo
import android.webkit.WebView

class OmniverseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppGraph.init(this)

        // Enable WebView debugging via USB debugging/ADB (chrome://inspect) in debuggable builds
        if (0 != (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE)) {
            WebView.setWebContentsDebuggingEnabled(true)
        }
    }
}

/// Tiny service locator so screens/repos share one AppState + stores.
object AppGraph {
    lateinit var appState: AppState
        private set

    fun init(app: Application) {
        if (::appState.isInitialized) return
        appState = AppState(app.applicationContext)
    }
}

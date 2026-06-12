package com.finix.omniverse

import android.app.Application

class OmniverseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppGraph.init(this)
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

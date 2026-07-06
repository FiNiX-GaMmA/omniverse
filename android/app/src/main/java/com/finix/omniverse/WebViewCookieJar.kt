package com.finix.omniverse

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * Bridges OkHttp's cookie handling to the global `android.webkit.CookieManager`
 * — the same store WebViews read and write. This lets the AllAnime API client
 * reuse the session cookie the user banks by solving a captcha in the WebView
 * ([com.finix.omniverse.ui.CaptchaScreen]), so the retried source request is
 * authenticated. Mirrors the iOS `HTTPCookieStorage.shared` sync.
 *
 * All access is guarded: if the WebView cookie subsystem isn't ready yet, we
 * degrade to "no cookies" rather than breaking every API call.
 */
object WebViewCookieJar : CookieJar {

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val manager = runCatching { CookieManager.getInstance() }.getOrNull() ?: return
        val target = url.toString()
        for (cookie in cookies) {
            runCatching { manager.setCookie(target, cookie.toString()) }
        }
        runCatching { manager.flush() }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val manager = runCatching { CookieManager.getInstance() }.getOrNull() ?: return emptyList()
        val raw = runCatching { manager.getCookie(url.toString()) }.getOrNull() ?: return emptyList()
        return raw.split(";").mapNotNull { pair -> Cookie.parse(url, pair.trim()) }
    }
}

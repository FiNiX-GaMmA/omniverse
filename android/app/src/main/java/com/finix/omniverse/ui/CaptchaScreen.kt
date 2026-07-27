package com.finix.omniverse.ui

import android.annotation.SuppressLint
import android.graphics.Color as AndroidColor
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.finix.omniverse.ui.theme.LiquidColors

/**
 * Shown when AllAnime answers NEED_CAPTCHA. Loads the AllAnime site in a WebView
 * so the user can solve the check; cookies land in the global CookieManager,
 * which `WebViewCookieJar` bridges to the API's OkHttp client. Tapping Done
 * flushes the cookie store and triggers the retry via [CaptchaArgs.onComplete].
 * Mirrors the iOS CaptchaResolveScreen + HTTPCookieStorage.shared sync.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CaptchaScreen(args: CaptchaArgs, onClose: () -> Unit) {
    var loading by remember { mutableStateOf(true) }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        @Suppress("DEPRECATION")
        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    layoutParams = android.view.ViewGroup.LayoutParams(
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                        android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.databaseEnabled = true
                    settings.useWideViewPort = true
                    settings.loadWithOverviewMode = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    // The session cookie the API checks is set on api.allanime.day
                    // during the site's XHRs — that's third-party to this page.
                    // `this` here is the WebView (the apply receiver).
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    settings.userAgentString = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
                    webChromeClient = android.webkit.WebChromeClient()
                    setBackgroundColor(AndroidColor.WHITE)
                    webViewClient = object : WebViewClient() {
                        override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                            loading = true
                        }
                        override fun onPageFinished(view: WebView?, url: String?) {
                            loading = false
                            CookieManager.getInstance().flush()
                            val autoSolveJS = """
                                (function() {
                                    function solve() {
                                        const checkbox = document.querySelector('input[type="checkbox"]') ||
                                                         document.querySelector('.ct-checkbox') ||
                                                         document.querySelector('#challenge-stage input') ||
                                                         document.querySelector('#challenge-stage label') ||
                                                         document.querySelector('#challenge-stage span');
                                        if (checkbox) {
                                            checkbox.click();
                                        }
                                    }
                                    setInterval(solve, 800);
                                })();
                            """.trimIndent()
                            view?.evaluateJavascript(autoSolveJS, null)
                        }
                    }
                    loadUrl(args.url)
                }
            },
            modifier = Modifier.fillMaxSize().padding(top = 66.dp),
        )

        if (loading) {
            Box(Modifier.fillMaxSize().padding(top = 66.dp), Alignment.Center) {
                CircularProgressIndicator(color = LiquidColors.Cyan)
            }
        }

        Row(
            Modifier.fillMaxWidth().background(Color.Black).padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(44.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.12f))
                    .tvFocusable(onClick = onClose, corner = 22),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Close, "Close", tint = Color.White) }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text("Verify to continue", color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text("Solve the check, then tap Done", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
            }
            Box(
                Modifier.clip(RoundedCornerShape(50)).background(Color.White)
                    .tvFocusable(
                        onClick = {
                            CookieManager.getInstance().flush()
                            onClose()
                            args.onComplete?.invoke()
                        },
                        corner = 50,
                    )
                    .padding(horizontal = 22.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) { Text("Done", color = Color.Black, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
        }
    }
}

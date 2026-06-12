package com.finix.omniverse

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/// In-app update check + sideload installer utilizing the GitHub Releases API on-the-fly.
object UpdateChecker {

    // Dynamic GitHub Releases API endpoint for your repository
    const val GITHUB_RELEASE_API_URL = "https://api.github.com/repos/FiNiX-GaMmA/omniverse/releases/latest"

    data class UpdateInfo(
        val versionCode: Int,
        val versionName: String,
        val apkUrl: String,
        val notes: String?,
    )

    sealed class CheckResult {
        data class Available(val info: UpdateInfo) : CheckResult()
        object UpToDate : CheckResult()
        data class Error(val message: String) : CheckResult()
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /// Semantic version comparison (Major.Minor.Patch)
    /// Returns true if the remote version name is newer than the local one.
    fun isNewerVersion(current: String, remote: String): Boolean {
        val currClean = current.trim().removePrefix("v").removePrefix("V")
        val remoClean = remote.trim().removePrefix("v").removePrefix("V")
        if (currClean == remoClean) return false
        val currParts = currClean.split(".").mapNotNull { it.toIntOrNull() }
        val remoParts = remoClean.split(".").mapNotNull { it.toIntOrNull() }
        val size = maxOf(currParts.size, remoParts.size)
        for (i in 0 until size) {
            val cVal = currParts.getOrNull(i) ?: 0
            val rVal = remoParts.getOrNull(i) ?: 0
            if (rVal > cVal) return true
            if (rVal < cVal) return false
        }
        return false
    }

    /// Fetch the latest GitHub release manifest and check for available updates.
    suspend fun check(): CheckResult = withContext(Dispatchers.IO) {
        runCatching {
            // Note: GitHub API strictly requires a User-Agent header or returns a 403.
            val req = Request.Builder()
                .url(GITHUB_RELEASE_API_URL)
                .header("User-Agent", "Omniverse-App")
                .get()
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext CheckResult.Error("Couldn't check for updates (HTTP ${resp.code}).")
                val body = resp.body?.string().orEmpty()
                val json = JSONObject(body)
                val tagName = json.optString("tag_name", "")
                val notes = json.optString("body", "").takeIf { it.isNotBlank() }

                // Scan through assets to find Omniverse.apk
                var apkUrl = ""
                val assets = json.optJSONArray("assets")
                if (assets != null) {
                    for (i in 0 until assets.length()) {
                        val asset = assets.optJSONObject(i) ?: continue
                        if (asset.optString("name", "") == "Omniverse.apk") {
                            apkUrl = asset.optString("browser_download_url", "")
                            break
                        }
                    }
                }

                if (tagName.isBlank() || apkUrl.isBlank()) {
                    return@withContext CheckResult.UpToDate
                }

                val info = UpdateInfo(
                    versionCode = 0, // unused under semantic name comparison
                    versionName = tagName,
                    apkUrl = apkUrl,
                    notes = notes
                )

                if (isNewerVersion(BuildConfig.VERSION_NAME, tagName)) {
                    CheckResult.Available(info)
                } else {
                    CheckResult.UpToDate
                }
            }
        }.getOrElse { CheckResult.Error("Couldn't check for updates: ${it.localizedMessage}") }
    }

    /// Download the APK to cache, then launch the system installer. Returns an
    /// error message on failure, or null on success (installer launched).
    suspend fun downloadAndInstall(context: Context, info: UpdateInfo): String? = withContext(Dispatchers.IO) {
        runCatching {
            val dir = File(context.cacheDir, "updates").apply { mkdirs() }
            val cleanTagName = info.versionName.removePrefix("v").removePrefix("V")
            val apk = File(dir, "omniverse-update-${cleanTagName}.apk")
            val req = Request.Builder().url(info.apkUrl).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext "Download failed (${resp.code})."
                val sink = resp.body ?: return@withContext "Download failed."
                apk.outputStream().use { out -> sink.byteStream().copyTo(out) }
            }
            val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            null
        }.getOrElse { "Couldn't download the update: ${it.localizedMessage}" }
    }
}

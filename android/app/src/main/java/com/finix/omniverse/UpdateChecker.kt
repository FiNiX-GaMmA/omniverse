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
import java.net.URI
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
        val currParts = parseVersion(current) ?: return false
        val remoParts = parseVersion(remote) ?: return false
        val size = maxOf(currParts.size, remoParts.size)
        for (i in 0 until size) {
            val cVal = currParts.getOrNull(i) ?: 0
            val rVal = remoParts.getOrNull(i) ?: 0
            if (rVal > cVal) return true
            if (rVal < cVal) return false
        }
        return false
    }

    private fun parseVersion(value: String): List<Int>? {
        val clean = value.trim().removePrefix("v").removePrefix("V")
        if (!clean.matches(Regex("\\d+(?:\\.\\d+)*"))) return null
        return clean.split(".").map { it.toIntOrNull() ?: return null }
    }

    fun isTrustedApkUrl(rawUrl: String): Boolean = runCatching {
        val uri = URI(rawUrl)
        val rawPath = uri.rawPath ?: return@runCatching false
        val path = uri.path ?: return@runCatching false
        val prefix = "/FiNiX-GaMmA/omniverse/releases/download/"
        val relative = path.removePrefix(prefix)
        val parts = relative.split("/")
        val fileName = parts.getOrNull(1).orEmpty().lowercase()
        uri.scheme == "https" &&
            uri.host == "github.com" &&
            uri.userInfo == null &&
            uri.query == null &&
            uri.fragment == null &&
            rawPath == path &&
            path.startsWith(prefix) &&
            parts.size == 2 &&
            parts[0].isNotBlank() &&
            fileName.startsWith("omniverse") &&
            fileName.endsWith(".apk")
    }.getOrDefault(false)

    fun safeVersionFileName(version: String): String {
        val clean = version.trim().removePrefix("v").removePrefix("V")
        val safe = clean.replace(Regex("[^A-Za-z0-9._-]"), "-").take(64)
        return safe.ifBlank { "update" }
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

                // Detect device architecture
                val abis = android.os.Build.SUPPORTED_ABIS
                val isArm64 = abis.contains("arm64-v8a")
                val isArmv7 = abis.contains("armeabi-v7a")
                val isX86_64 = abis.contains("x86_64")

                // Scan through assets to find matching APK
                var apkUrl = ""
                val assets = json.optJSONArray("assets")
                if (assets != null) {
                    // 1. Try to find architecture-specific APK first
                    for (i in 0 until assets.length()) {
                        val asset = assets.optJSONObject(i) ?: continue
                        val name = asset.optString("name", "").lowercase()
                        if (name.endsWith(".apk")) {
                            if (isArm64 && (name.contains("arm64") || name.contains("v8a"))) {
                                apkUrl = asset.optString("browser_download_url", "")
                                break
                            } else if (isArmv7 && (name.contains("armv7") || name.contains("v7a") || name.contains("armeabi"))) {
                                apkUrl = asset.optString("browser_download_url", "")
                                break
                            } else if (isX86_64 && name.contains("x86_64")) {
                                apkUrl = asset.optString("browser_download_url", "")
                                break
                            }
                        }
                    }
                    // 2. Fallback to first matching universal Omniverse.apk
                    if (apkUrl.isBlank()) {
                        for (i in 0 until assets.length()) {
                            val asset = assets.optJSONObject(i) ?: continue
                            val name = asset.optString("name", "")
                            if (name == "Omniverse.apk" || name.lowercase().endsWith(".apk")) {
                                apkUrl = asset.optString("browser_download_url", "")
                                break
                            }
                        }
                    }
                }

                if (tagName.isBlank() || apkUrl.isBlank()) {
                    return@withContext CheckResult.UpToDate
                }
                if (!isTrustedApkUrl(apkUrl)) {
                    return@withContext CheckResult.Error("The release contains an untrusted APK URL.")
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

    /// Download the APK to cache with progress tracking, then launch the system installer.
    /// Returns an error message on failure, or null on success (installer launched).
    suspend fun downloadAndInstall(
        context: Context,
        info: UpdateInfo,
        onProgress: ((Float) -> Unit)? = null
    ): String? = withContext(Dispatchers.IO) {
        if (!isTrustedApkUrl(info.apkUrl)) {
            return@withContext "Refusing an untrusted update download."
        }
        runCatching {
            val dir = File(context.cacheDir, "updates").apply { mkdirs() }
            val cleanTagName = safeVersionFileName(info.versionName)
            val apk = File(dir, "omniverse-update-${cleanTagName}.apk")
            val req = Request.Builder().url(info.apkUrl).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext "Download failed (${resp.code})."
                val body = resp.body ?: return@withContext "Download failed."
                val contentLength = body.contentLength()
                val inputStream = body.byteStream()
                apk.outputStream().use { out ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalRead = 0L
                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        out.write(buffer, 0, bytesRead)
                        totalRead += bytesRead
                        if (contentLength > 0 && onProgress != null) {
                            val pct = (totalRead.toFloat() / contentLength.toFloat()).coerceIn(0f, 1f)
                            onProgress(pct)
                        }
                    }
                }
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

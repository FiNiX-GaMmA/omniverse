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

/// In-app update check + sideload installer.
///
/// Fetches a small JSON manifest, compares its versionCode to the running build,
/// and (on user confirmation) downloads + launches the APK installer. Entirely
/// resilient to an unreachable/placeholder URL — every entry point returns a
/// typed result instead of throwing.
object UpdateChecker {

    // PLACEHOLDER URL — the user will set the real manifest URL later.
    // Expected JSON shape: {"versionCode":Int,"versionName":String,"apkUrl":String,"notes":String?}
    const val UPDATE_MANIFEST_URL = "https://example.com/omniverse/latest.json"

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

    /// Fetch the manifest and decide whether an update is available.
    suspend fun check(): CheckResult = withContext(Dispatchers.IO) {
        runCatching {
            val req = Request.Builder().url(UPDATE_MANIFEST_URL).get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext CheckResult.Error("Couldn't check for updates.")
                val body = resp.body?.string().orEmpty()
                val json = JSONObject(body)
                val info = UpdateInfo(
                    versionCode = json.optInt("versionCode", 0),
                    versionName = json.optString("versionName", ""),
                    apkUrl = json.optString("apkUrl", ""),
                    notes = json.optString("notes").takeIf { it.isNotBlank() },
                )
                if (info.versionCode > BuildConfig.VERSION_CODE && info.apkUrl.isNotBlank()) {
                    CheckResult.Available(info)
                } else {
                    CheckResult.UpToDate
                }
            }
        }.getOrElse { CheckResult.Error("Couldn't check for updates.") }
    }

    /// Download the APK to cache, then launch the system installer. Returns an
    /// error message on failure, or null on success (installer launched).
    suspend fun downloadAndInstall(context: Context, info: UpdateInfo): String? = withContext(Dispatchers.IO) {
        runCatching {
            val dir = File(context.cacheDir, "updates").apply { mkdirs() }
            val apk = File(dir, "omniverse-update-${info.versionCode}.apk")
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
        }.getOrElse { "Couldn't download the update." }
    }
}

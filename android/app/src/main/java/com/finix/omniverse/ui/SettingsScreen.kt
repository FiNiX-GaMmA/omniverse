package com.finix.omniverse.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.finix.omniverse.AppGraph
import com.finix.omniverse.SyncCenter
import com.finix.omniverse.UpdateChecker
import com.finix.omniverse.ui.theme.LiquidColors
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.launch

private val vidsrcEmbedDomains = listOf("vidsrc-embed.ru", "vidsrc-embed.su", "vidsrcme.su", "vsrc.su")
private val subtitleLanguageOptions = listOf(
    "en" to "English", "es" to "Spanish", "fr" to "French", "de" to "German",
    "it" to "Italian", "pt" to "Portuguese", "ja" to "Japanese", "ko" to "Korean",
    "zh" to "Chinese", "ar" to "Arabic", "hi" to "Hindi",
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen() {
    val state = AppGraph.appState
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // Pager is the source of truth for the selected tab; `tab` tracks the settled page
    // so the header row stays in sync whether the user taps or swipes.
    val pagerState = rememberPagerState(pageCount = { 3 }) // 0 API KEYS, 1 PREFERENCES, 2 CLOUD SYNC
    val tab = pagerState.currentPage

    var tmdb by remember { mutableStateOf(state.credentials.tmdbToken) }
    var tvdb by remember { mutableStateOf(state.credentials.tvdbApiKey) }
    var tvdbPin by remember { mutableStateOf(state.credentials.tvdbPin) }
    var traktId by remember { mutableStateOf(state.credentials.traktClientId) }
    var traktSecret by remember { mutableStateOf(state.credentials.traktClientSecret) }
    var pixeldrain by remember { mutableStateOf(state.credentials.pixeldrainApiKey) }
    var anilist by remember { mutableStateOf(state.credentials.anilistAccessToken) }

    var language by remember { mutableStateOf(state.settings.language) }
    var region by remember { mutableStateOf(state.settings.region) }
    var subtitleUrl by remember { mutableStateOf(state.settings.subtitleUrl) }
    var subtitleLanguage by remember { mutableStateOf(state.settings.subtitleLanguage.ifBlank { "en" }) }
    var vidsrcDomain by remember { mutableStateOf(if (state.settings.vidsrcDomain in vidsrcEmbedDomains) state.settings.vidsrcDomain else vidsrcEmbedDomains[0]) }
    var includeAdult by remember { mutableStateOf(state.settings.includeAdult) }
    var tvMode by remember { mutableStateOf(state.settings.tvMode) }
    var preferDubbed by remember { mutableStateOf(state.settings.preferDubbedAnime) }
    var showMoviesTv by remember { mutableStateOf(state.settings.showMoviesTv) }
    var showAnime by remember { mutableStateOf(state.settings.showAnime) }
    var showLiveTv by remember { mutableStateOf(state.settings.showLiveTv) }

    var showSyncQr by remember { mutableStateOf(false) }
    var updateInfo by remember { mutableStateOf<UpdateChecker.UpdateInfo?>(null) }

    fun openUrl(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

    fun launchScanner() {
        val options = com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_QR_CODE)
            .build()
        val scanner = com.google.mlkit.vision.codescanner.GmsBarcodeScanning.getClient(context, options)
        scanner.startScan()
            .addOnSuccessListener { barcode ->
                barcode.rawValue?.let { raw ->
                    scope.launch { state.applySyncString(raw) }
                }
            }
            .addOnFailureListener { e ->
                Toast.makeText(context, e.localizedMessage ?: "Failed to scan.", Toast.LENGTH_SHORT).show()
            }
    }
    fun requestScan() {
        launchScanner()
    }

    fun checkForUpdates() {
        scope.launch {
            when (val r = UpdateChecker.check()) {
                is UpdateChecker.CheckResult.Available -> updateInfo = r.info
                is UpdateChecker.CheckResult.UpToDate ->
                    Toast.makeText(context, "You're on the latest version.", Toast.LENGTH_SHORT).show()
                is UpdateChecker.CheckResult.Error ->
                    Toast.makeText(context, r.message, Toast.LENGTH_SHORT).show()
            }
        }
    }

    suspend fun saveAll() {
        var c = state.credentials.copy(
            tmdbToken = tmdb, tvdbApiKey = tvdb, tvdbPin = tvdbPin,
            traktClientId = traktId, traktClientSecret = traktSecret,
            pixeldrainApiKey = pixeldrain, anilistAccessToken = anilist,
        )
        state.saveCredentials(c)
        val s = state.settings.copy(
            language = language.trim().ifEmpty { "en-US" },
            region = region.trim().ifEmpty { "US" }.uppercase(),
            includeAdult = includeAdult, tvMode = tvMode, vidsrcDomain = vidsrcDomain,
            subtitleUrl = subtitleUrl.trim(), subtitleLanguage = subtitleLanguage.trim().ifEmpty { "en" },
            preferDubbedAnime = preferDubbed, showMoviesTv = showMoviesTv, showAnime = showAnime, showLiveTv = showLiveTv,
        )
        state.saveSettings(s)
        state.message = "Saved. Refreshing rows with the new settings."
    }

    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        // Tab bar — sits below the status bar (statusBarsPadding on the root). Tapping a
        // tab animates the pager; swiping the pager updates the highlighted tab.
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp)) {
            listOf("API KEYS", "PREFERENCES", "CLOUD SYNC").forEachIndexed { i, t ->
                Column(
                    Modifier.weight(1f).tvFocusable(onClick = { scope.launch { pagerState.animateScrollToPage(i) } }, corner = 4),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(t, color = if (tab == i) Color.White else Color.White.copy(alpha = 0.6f), fontSize = 14.sp, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(8.dp))
                    Box(Modifier.fillMaxWidth().height(3.dp).background(if (tab == i) LiquidColors.Cyan else Color.Transparent))
                }
            }
        }
        HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { page ->
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            when (page) {
                0 -> {
                    Section("Secret API Credentials") {
                        SecretField(tmdb, { tmdb = it }, "TheMovieDB (TMDB) token")
                        SecretField(tvdb, { tvdb = it }, "TVDB v4 API key")
                        SecretField(tvdbPin, { tvdbPin = it }, "TVDB Subscriber PIN (optional)")
                        SecretField(pixeldrain, { pixeldrain = it }, "Pixeldrain API key")
                        SecretField(anilist, { anilist = it }, "AniList Access Token")
                    }
                    Section("Trakt Developer Client Keys") {
                        SecretField(traktId, { traktId = it }, "Trakt Client ID")
                        SecretField(traktSecret, { traktSecret = it }, "Trakt Client Secret")
                    }
                }
                1 -> {
                    Section("Discovery preferences") {
                        LabeledField(language, { language = it }, "Language")
                        LabeledField(region, { region = it }, "Region")
                        PickerField("Preferred Vidsrc server", vidsrcDomain, vidsrcEmbedDomains.map { it to it }) { vidsrcDomain = it }
                    }
                    Section("Subtitle configurations") {
                        PickerField("Subtitle language", subtitleLanguage, subtitleLanguageOptions) { subtitleLanguage = it }
                        LabeledField(subtitleUrl, { subtitleUrl = it }, "Default subtitle URL")
                    }
                    Section("Display & Content Toggles") {
                        ToggleRow("Show Movies & TV shows", showMoviesTv) { showMoviesTv = it }
                        ToggleRow("Show Anime list", showAnime) { showAnime = it }
                        ToggleRow("Enable Live TV channels", showLiveTv) { showLiveTv = it }
                        ToggleRow("Include Adult content", includeAdult) { includeAdult = it }
                        ToggleRow("Enable TV / Landscape Mode", tvMode) { tvMode = it }
                        ToggleRow("Prefer Dubbed Anime", preferDubbed) { preferDubbed = it }
                    }
                }
                else -> {
                    SyncCard(
                        "Trakt.tv Sync Integration", state.credentials.hasTraktUser,
                        if (state.credentials.hasTraktUser) (if (state.credentials.traktUsername.isEmpty()) "Connected to Trakt" else "Connected as: ${state.credentials.traktUsername}")
                        else "Trakt disconnected (Sync disabled)",
                    ) {
                        Chip(if (state.credentials.hasTraktUser) "Refresh Login" else "Connect Trakt") {
                            scope.launch { saveAll(); state.startTraktBrowserAuth()?.let { openUrl(it.toString()) } }
                        }
                        if (state.credentials.hasTraktUser) {
                            Chip("Disconnect") { state.disconnectTrakt() }
                        }
                    }
                    SyncCard(
                        "Cross-Device Login", true,
                        "Move your login, API keys and preferences between devices with a QR code. No server, no re-login.",
                    ) {
                        Chip("Show Sync QR") { showSyncQr = true }
                        Chip("Scan Sync QR") { requestScan() }
                    }
                    SyncCard("App Updates", true, "Check for a newer version of Omniverse.") {
                        Chip("Check for updates") { checkForUpdates() }
                    }
                    SyncCard(
                        "AniList Sync Integration", state.credentials.hasAnilist,
                        if (state.credentials.hasAnilist) "Connected to AniList (Sync Active)" else "AniList disconnected (Sync disabled)",
                    ) {
                        Chip(if (state.credentials.hasAnilist) "Refresh Login" else "Connect AniList") {
                            openUrl("https://anilist.co/api/v2/oauth/authorize?client_id=14187&response_type=token")
                        }
                        if (state.credentials.hasAnilist) Chip("Disconnect") { scope.launch { state.saveCredentials(state.credentials.copy(anilistAccessToken = "")) } }
                    }
                    SyncCard("Manual Sync", true, "Push or pull your login, API keys and preferences to/from the cloud now.") {
                        Chip("Sync Now") {
                            scope.launch {
                                state.syncNow()
                                state.message = "Sync complete."
                                Toast.makeText(context, "Sync complete.", Toast.LENGTH_SHORT).show()
                            }
                        }
                        Chip("Restore from Cloud") {
                            scope.launch {
                                runCatching { state.restoreSettingsFromTrakt() }
                                    .onSuccess {
                                        // Re-seed the editable fields from the restored state.
                                        tmdb = state.credentials.tmdbToken
                                        tvdb = state.credentials.tvdbApiKey
                                        tvdbPin = state.credentials.tvdbPin
                                        traktId = state.credentials.traktClientId
                                        traktSecret = state.credentials.traktClientSecret
                                        pixeldrain = state.credentials.pixeldrainApiKey
                                        anilist = state.credentials.anilistAccessToken
                                        language = state.settings.language
                                        region = state.settings.region
                                        subtitleUrl = state.settings.subtitleUrl
                                        subtitleLanguage = state.settings.subtitleLanguage.ifBlank { "en" }
                                        vidsrcDomain = if (state.settings.vidsrcDomain in vidsrcEmbedDomains) state.settings.vidsrcDomain else vidsrcEmbedDomains[0]
                                        includeAdult = state.settings.includeAdult
                                        tvMode = state.settings.tvMode
                                        preferDubbed = state.settings.preferDubbedAnime
                                        showMoviesTv = state.settings.showMoviesTv
                                        showAnime = state.settings.showAnime
                                        showLiveTv = state.settings.showLiveTv
                                        state.message = "Restored from cloud."
                                        Toast.makeText(context, "Restored from cloud.", Toast.LENGTH_SHORT).show()
                                    }
                                    .onFailure {
                                        Toast.makeText(context, "Restore failed. Connect Trakt and sync first.", Toast.LENGTH_SHORT).show()
                                    }
                            }
                        }
                    }
                    Text("Trakt Redirect URI: omniplay://trakt/oauth\nAniList Redirect URI: omniplay://anilist/oauth",
                        color = Color.White.copy(alpha = 0.5f), fontSize = 12.sp, modifier = Modifier.fillMaxWidth())
                    if (showSyncQr) SyncQr(state) { showSyncQr = false }
                }
            }
        }
        }
        // Save button. The floating bottom NavigationBar (Shell) overlays content on
        // phones, so reserve space below the button (nav bar height ~88dp) to keep it
        // fully visible and tappable. On wide layouts the rail is on the left, so no
        // extra space is needed there — 88dp bottom padding is harmless either way.
        Box(
            Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 88.dp).height(56.dp)
                .clip(RoundedCornerShape(16.dp)).background(LiquidColors.Cyan)
                .tvFocusable(onClick = { scope.launch { saveAll() } }, corner = 16),
            contentAlignment = Alignment.Center,
        ) { Text("SAVE ALL CHANGES", color = Color.Black, fontSize = 15.sp, fontWeight = FontWeight.Black) }
    }

    updateInfo?.let { info ->
        AlertDialog(
            onDismissRequest = { updateInfo = null },
            title = { Text("Update available") },
            text = {
                val notes = info.notes?.takeIf { it.isNotBlank() }
                Text(
                    "Version ${info.versionName} is available." + (notes?.let { "\n\n$it" } ?: ""),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    updateInfo = null
                    scope.launch {
                        Toast.makeText(context, "Downloading update...", Toast.LENGTH_SHORT).show()
                        val err = UpdateChecker.downloadAndInstall(context, info)
                        if (err != null) Toast.makeText(context, err, Toast.LENGTH_SHORT).show()
                    }
                }) { Text("Download & Install") }
            },
            dismissButton = { TextButton(onClick = { updateInfo = null }) { Text("Later") } },
        )
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(20.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(title, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        content()
    }
}

@Composable
private fun SecretField(value: String, onChange: (String) -> Unit, label: String) {
    var obscure by remember { mutableStateOf(true) }
    Column(Modifier.fillMaxWidth()) {
        Text(label, color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        OutlinedTextField(
            value = value, onValueChange = onChange, modifier = Modifier.fillMaxWidth(), singleLine = true,
            visualTransformation = if (obscure) PasswordVisualTransformation() else VisualTransformation.None,
            trailingIcon = { Text(if (obscure) "show" else "hide", color = LiquidColors.Cyan, fontSize = 12.sp, modifier = Modifier.tvFocusable(onClick = { obscure = !obscure }, corner = 4).padding(8.dp)) },
            colors = textColors(),
        )
    }
}

@Composable
private fun LabeledField(value: String, onChange: (String) -> Unit, label: String) {
    Column(Modifier.fillMaxWidth()) {
        Text(label, color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        OutlinedTextField(value = value, onValueChange = onChange, modifier = Modifier.fillMaxWidth(), singleLine = true, colors = textColors())
    }
}

@Composable
private fun PickerField(label: String, selection: String, options: List<Pair<String, String>>, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        Text(label, color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Box {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).border(1.dp, Color.White.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                    .tvFocusable(onClick = { expanded = true }, corner = 8).padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(options.firstOrNull { it.first == selection }?.second ?: selection, color = Color.White)
                Text("▾", color = Color.White.copy(alpha = 0.6f))
            }
            DropdownMenu(expanded, { expanded = false }) {
                options.forEach { (v, l) -> DropdownMenuItem(text = { Text(l) }, onClick = { onSelect(v); expanded = false }) }
            }
        }
    }
}

@Composable
private fun ToggleRow(title: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Color.White, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Switch(checked = value, onCheckedChange = onChange, colors = SwitchDefaults.colors(checkedTrackColor = LiquidColors.Cyan, checkedThumbColor = Color.White))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SyncCard(title: String, connected: Boolean, status: String, actions: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White.copy(alpha = 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(20.dp)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Black)
        Text(status, color = if (connected) Color.White else Color.White.copy(alpha = 0.38f), fontSize = 13.sp, fontWeight = if (connected) FontWeight.Bold else FontWeight.Normal)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { actions() }
    }
}

@Composable
private fun Chip(label: String, onClick: () -> Unit) {
    Box(
        Modifier.clip(RoundedCornerShape(50)).border(1.dp, Color.White.copy(alpha = 0.28f), RoundedCornerShape(50))
            .tvFocusable(onClick = onClick, corner = 50).padding(horizontal = 14.dp, vertical = 9.dp),
    ) { Text(label, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
}

@Composable
private fun SyncQr(state: com.finix.omniverse.AppState, onClose: () -> Unit) {
    // Server-less cross-device sync QR (OMNIVERSE-SYNC1 payload). No network.
    val payload = remember(state.credentials, state.settings) {
        SyncCenter.buildSyncString(state.credentials, state.settings)
    }
    val bitmap = remember(payload) { qrBitmap(payload, 900) }
    Column(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Sync QR", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text("On your other device, open Omniverse and tap \"Scan Sync QR\" to sign in instantly.",
            color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp)
        bitmap?.let {
            Image(
                it.asImageBitmap(), null,
                Modifier.size(340.dp).clip(RoundedCornerShape(16.dp)).background(Color.White).padding(16.dp),
            )
        }
        Chip("Close", onClose)
    }
}

// QR error-correction level L = fewest modules = least dense = easiest to scan off a screen.
private fun qrBitmap(text: String, size: Int): Bitmap? = runCatching {
    val hints = mapOf(
        com.google.zxing.EncodeHintType.ERROR_CORRECTION to com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.L,
        com.google.zxing.EncodeHintType.MARGIN to 2,
    )
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, hints)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) for (y in 0 until size)
        bmp.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
    bmp
}.getOrNull()

@Composable
private fun textColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Color.White, unfocusedTextColor = Color.White,
    focusedBorderColor = LiquidColors.Cyan, unfocusedBorderColor = Color.White.copy(alpha = 0.3f),
    cursorColor = LiquidColors.Cyan,
)

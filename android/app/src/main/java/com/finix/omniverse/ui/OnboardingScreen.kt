package com.finix.omniverse.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.finix.omniverse.AppGraph
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.launch

@Composable
fun OnboardingScreen() {
    val state = AppGraph.appState
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var clientId by remember { mutableStateOf("") }
    var clientSecret by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    fun launchScanner() {
        error = null
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
                error = e.localizedMessage ?: "Failed to scan."
            }
    }
    fun requestScan() {
        launchScanner()
    }

    fun connect() {
        error = null
        scope.launch {
            if (state.credentials.traktClientId.trim().isEmpty() && clientId.trim().isEmpty()) {
                error = "Please enter your Trakt Client ID."; return@launch
            }
            if (clientId.trim().isNotEmpty()) {
                state.saveCredentials(state.credentials.copy(traktClientId = clientId.trim(), traktClientSecret = clientSecret.trim()))
            }
            val uri = state.startTraktBrowserAuth()
            if (uri == null) { error = "Could not open Trakt sign in." }
            else context.startActivity(Intent(Intent.ACTION_VIEW, uri))
        }
    }

    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Column(
            Modifier.widthIn(max = 480.dp).verticalScroll(rememberScrollState())
                .clip(RoundedCornerShape(28.dp)).background(Color.White.copy(alpha = 0.06f))
                .border(1.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(28.dp))
                .padding(horizontal = 24.dp, vertical = 36.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Welcome to Omniverse", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Black)
            Text("Already signed in on another device? Scan its Sync QR to instantly restore your watchlists, API keys, preferences and Trakt login. Or connect Trakt.tv directly.",
                color = Color.White.copy(alpha = 0.7f), fontSize = 15.sp)

            // Prominent primary action: scan the sync QR (camera).
            Box(
                Modifier.fillMaxWidth().height(54.dp).clip(RoundedCornerShape(24.dp)).background(LiquidColors.Cyan)
                    .tvFocusable(onClick = { requestScan() }, corner = 24),
                contentAlignment = Alignment.Center,
            ) { Text("Scan Sync QR", color = Color.Black, fontWeight = FontWeight.Black, fontSize = 16.sp) }

            if (!state.credentials.hasTraktApp) {
                OutlinedTextField(clientId, { clientId = it }, Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text("Trakt Client ID", color = Color.White.copy(alpha = 0.4f)) }, colors = obColors())
                OutlinedTextField(clientSecret, { clientSecret = it }, Modifier.fillMaxWidth(), singleLine = true,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                    placeholder = { Text("Trakt Client Secret", color = Color.White.copy(alpha = 0.4f)) }, colors = obColors())
            }

            if (state.traktConnecting) {
                CircularProgressIndicator(color = LiquidColors.Rose)
                Text("Connecting to Trakt...", color = Color.White.copy(alpha = 0.7f), fontWeight = FontWeight.Bold)
            } else {
                Box(
                    Modifier.fillMaxWidth().height(54.dp).clip(RoundedCornerShape(24.dp)).background(Color(0xFFE53935))
                        .tvFocusable(onClick = { connect() }, corner = 24),
                    contentAlignment = Alignment.Center,
                ) { Text("Connect Trakt.tv Account", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp) }
            }

            error?.let { Text(it, color = LiquidColors.Rose, fontSize = 13.sp) }
            state.message?.takeIf { it.contains("Trakt") || it.contains("Sync", true) }?.let {
                Text(it, color = Color.White.copy(alpha = 0.54f), fontSize = 13.sp)
            }
        }
    }
}

@Composable
private fun obColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Color.White, unfocusedTextColor = Color.White,
    focusedBorderColor = LiquidColors.Cyan, unfocusedBorderColor = Color.White.copy(alpha = 0.3f),
    cursorColor = LiquidColors.Cyan,
)

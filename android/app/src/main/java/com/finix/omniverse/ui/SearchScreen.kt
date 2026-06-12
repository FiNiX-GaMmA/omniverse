package com.finix.omniverse.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.finix.omniverse.AppGraph
import com.finix.omniverse.MediaItem
import com.finix.omniverse.ui.theme.LiquidColors
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged

@OptIn(kotlinx.coroutines.FlowPreview::class)
@Composable
fun SearchScreen(nav: NavController) {
    val state = AppGraph.appState
    var query by remember { mutableStateOf("") }
    var currentQuery by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var results by remember { mutableStateOf<List<MediaItem>>(emptyList()) }
    var requestId by remember { mutableIntStateOf(0) }

    // 320ms debounce on query
    LaunchedEffect(Unit) {
        snapshotFlow { query }
            .debounce(320)
            .distinctUntilChanged()
            .collect { value ->
                val trimmed = value.trim()
                if (trimmed.isEmpty()) { currentQuery = ""; results = emptyList(); loading = false; error = null; return@collect }
                requestId++
                val id = requestId
                currentQuery = trimmed
                loading = true; error = null
                if (!state.credentials.hasTmdb) {
                    loading = false; error = "Add your TMDB API key in Settings to enable search."; results = emptyList()
                    return@collect
                }
                val items = state.searchMedia(trimmed)
                if (id != requestId) return@collect
                loading = false; results = items
                error = if (items.isEmpty()) "No matches for \"$trimmed\"." else null
            }
    }

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = query, onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Search movies and TV shows", color = Color.White.copy(alpha = 0.54f)) },
                leadingIcon = { Icon(Icons.Filled.Search, null, tint = Color.White.copy(alpha = 0.7f)) },
                singleLine = true,
                shape = RoundedCornerShape(50),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White, unfocusedTextColor = Color.White,
                    focusedBorderColor = LiquidColors.Cyan, unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                    cursorColor = LiquidColors.Cyan,
                ),
            )
        }
        if (loading) Box(Modifier.fillMaxWidth().padding(24.dp), Alignment.Center) { CircularProgressIndicator(color = LiquidColors.Cyan) }
        if (!loading && error != null && results.isEmpty()) {
            Text(error!!, color = Color.White.copy(alpha = 0.78f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 20.dp))
        }
        if (results.isEmpty() && currentQuery.isEmpty()) {
            Column(Modifier.padding(horizontal = 28.dp, vertical = 8.dp)) {
                Text("Search Anything in Omniverse", color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Black)
                Text("Type a movie, TV show, or anime title. We search Omniverse for matches and open the same detail screen as the home rows — sources included.",
                    color = Color.White.copy(alpha = 0.7f), fontSize = 15.sp)
            }
        } else {
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
                val cols = when { maxWidth >= 1200.dp -> 6; maxWidth >= 900.dp -> 5; maxWidth >= 600.dp -> 4; else -> 3 }
                LazyVerticalGrid(
                    columns = GridCells.Fixed(cols),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    items(results, key = { it.id }) { item ->
                        Column {
                            Box(
                                Modifier.fillMaxWidth().aspectRatio(2f / 3f)
                                    .tvFocusable(onClick = { RouteArgs.detailItem = item; nav.navigate("detail") })
                                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                            ) { PosterImage(item.posterUrl ?: item.backdropUrl, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp))) }
                            Text(item.title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
                        }
                    }
                }
            }
        }
    }
}

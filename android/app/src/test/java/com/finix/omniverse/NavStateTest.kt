package com.finix.omniverse

import com.finix.omniverse.ui.resolveAvailableTabs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NavStateTest {

    @Test
    fun traktCredentialsRemoveClipboardFormattingNoise() {
        val raw = "  abcd\u200B ef\n12\uFEFF34  "
        assertEquals("abcdef1234", raw.normalizedTraktCredential())
    }

    @Test
    fun traktAuthorizeUrlAlwaysCarriesNormalizedClientId() {
        val uri = TraktRepositoryImpl().buildOAuthAuthorizeUri(
            ApiCredentials(traktClientId = " abcd\u200B1234 "),
            state = "state-token",
        )

        assertTrue(uri != null)
        assertTrue(uri!!.contains("client_id=abcd1234"))
        assertTrue(uri.contains("redirect_uri=omniplay%3A%2F%2Ftrakt%2Foauth"))
        assertTrue(uri.contains("state=state-token"))
    }

    @Test
    fun testResolveAvailableTabsDefault() {
        val settings = UserSettings(showMoviesTv = true, showLiveTv = true)
        val tabs = resolveAvailableTabs(settings)

        val tabIds = tabs.map { it.id }
        assertEquals(listOf("home", "movies", "shows", "livetv", "search", "settings"), tabIds)
    }

    @Test
    fun testResolveAvailableTabsWithoutMoviesTv() {
        val settings = UserSettings(showMoviesTv = false, showLiveTv = true)
        val tabs = resolveAvailableTabs(settings)

        val tabIds = tabs.map { it.id }
        assertEquals(listOf("livetv", "search", "settings"), tabIds)
        assertFalse(tabIds.contains("home"))
        assertFalse(tabIds.contains("movies"))
        assertFalse(tabIds.contains("shows"))
    }

    @Test
    fun testResolveAvailableTabsWithoutLiveTv() {
        val settings = UserSettings(showMoviesTv = true, showLiveTv = false)
        val tabs = resolveAvailableTabs(settings)

        val tabIds = tabs.map { it.id }
        assertEquals(listOf("home", "movies", "shows", "search", "settings"), tabIds)
        assertFalse(tabIds.contains("livetv"))
    }

    @Test
    fun testResolveAvailableTabsMinimal() {
        val settings = UserSettings(showMoviesTv = false, showLiveTv = false)
        val tabs = resolveAvailableTabs(settings)

        val tabIds = tabs.map { it.id }
        assertEquals(listOf("search", "settings"), tabIds)
    }

    @Test
    fun testTabFallbackLogic() {
        val settingsDisabled = UserSettings(showMoviesTv = false, showLiveTv = true)
        val tabs = resolveAvailableTabs(settingsDisabled)

        var requestedTabId = "home"
        val activeId = if (tabs.any { it.id == requestedTabId }) requestedTabId else (tabs.firstOrNull()?.id ?: "settings")

        // "home" is not in tabs, so it falls back to "livetv"
        assertEquals("livetv", activeId)
    }

    @Test
    fun testDefaultUserSettingsVidsrcDomain() {
        val settings = UserSettings()
        assertEquals("vsembed.ru", settings.vidsrcDomain)
        assertTrue(settings.showMoviesTv)
        assertTrue(settings.showLiveTv)
    }

    @Test
    fun testApiCredentialsHasTmdbAndOtherServices() {
        val emptyCreds = ApiCredentials()
        assertFalse(emptyCreds.hasTmdb)
        assertFalse(emptyCreds.hasTvdb)
        assertFalse(emptyCreds.hasTraktUser)
        assertFalse(emptyCreds.hasPixeldrain)

        val setCreds = ApiCredentials(
            tmdbToken = "  sample_key  ",
            tvdbApiKey = "tvdb_key",
            traktAccessToken = "trakt_token",
            pixeldrainApiKey = "pixel_key"
        )
        assertTrue(setCreds.hasTmdb)
        assertTrue(setCreds.hasTvdb)
        assertTrue(setCreds.hasTraktUser)
        assertTrue(setCreds.hasPixeldrain)
    }

    @Test
    fun testTabFilteringModes() {
        val movieItem = MediaItem(id = "1", type = MediaType.MOVIE, title = "Movie 1")
        val seriesItem = MediaItem(id = "2", type = MediaType.SERIES, title = "Series 1")
        val items = listOf(movieItem, seriesItem)

        val movieFiltered = items.filter { it.type == MediaType.MOVIE }
        val seriesFiltered = items.filter { it.type == MediaType.SERIES }

        assertEquals(1, movieFiltered.size)
        assertEquals("Movie 1", movieFiltered.first().title)

        assertEquals(1, seriesFiltered.size)
        assertEquals("Series 1", seriesFiltered.first().title)
    }

    @Test
    fun testCategoryShapingDistinctIds() {
        val cat1 = MediaCategory(id = "cat_1", title = "Category 1", type = MediaType.MOVIE, items = emptyList())
        val cat2 = MediaCategory(id = "cat_1", title = "Duplicate ID Category", type = MediaType.SERIES, items = emptyList())
        val cat3 = MediaCategory(id = "cat_2", title = "Category 2", type = MediaType.MOVIE, items = emptyList())

        val list = listOf(cat1, cat2, cat3)
        val distinctList = list.distinctBy { it.id }

        assertEquals(2, distinctList.size)
        assertEquals(listOf("cat_1", "cat_2"), distinctList.map { it.id })
    }

    @Test
    fun testImageUrlResolutionAcrossProviders() {
        assertEquals(null, imageUrl(null, "w342"))
        assertEquals("https://cdn.example/poster.jpg", imageUrl("https://cdn.example/poster.jpg", "w342"))
        assertEquals("https://cdn.example/poster.jpg", imageUrl("//cdn.example/poster.jpg", "w342"))
        assertEquals("https://artworks.thetvdb.com/banners/poster.jpg", imageUrl("banners/poster.jpg", "w342"))
        assertEquals("https://image.tmdb.org/t/p/w342/poster.jpg", imageUrl("/poster.jpg", "w342"))
    }

    @Test
    fun testDirectStreamDetectionHandlesQueriesAndCase() {
        assertTrue(LiveTvEntry.directStream("https://cdn.example/live.M3U8?token=abc"))
        assertTrue(LiveTvEntry.directStream("https://cdn.example/movie.mp4"))
        assertFalse(LiveTvEntry.directStream("https://embed.example/watch/123"))
    }

    @Test
    fun testWatchProgressFractionIsClamped() {
        assertEquals(0.0, WatchProgress(itemId = "1", title = "A", type = MediaType.MOVIE, positionMs = 10, durationMs = 0, lastWatchedAt = 1).fraction, 0.0)
        assertEquals(0.0, WatchProgress(itemId = "1", title = "A", type = MediaType.MOVIE, positionMs = -10, durationMs = 100, lastWatchedAt = 1).fraction, 0.0)
        assertEquals(1.0, WatchProgress(itemId = "1", title = "A", type = MediaType.MOVIE, positionMs = 150, durationMs = 100, lastWatchedAt = 1).fraction, 0.0)
    }
}

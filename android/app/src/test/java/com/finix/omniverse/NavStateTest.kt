package com.finix.omniverse

import com.finix.omniverse.ui.resolveAvailableTabs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NavStateTest {

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
}

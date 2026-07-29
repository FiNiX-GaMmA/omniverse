package com.finix.omniverse

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncCenterTest {

    @Test
    fun testIsSyncString() {
        assertTrue(SyncCenter.isSyncString("OMNIVERSE-SYNC1:abc"))
        assertTrue(SyncCenter.isSyncString("  OMNIVERSE-SYNC1:xyz  "))
        // Fail cases
        assertTrue(!SyncCenter.isSyncString("OMNIVERSE-SYNC:abc"))
        assertTrue(!SyncCenter.isSyncString("https://trakt.tv"))
    }

    @Test
    fun testBuildSyncString() {
        val creds = ApiCredentials(
            traktAccessToken = "test_token",
            traktUsername = "test_user"
        )
        val settings = UserSettings()
        val syncStr = SyncCenter.buildSyncString(creds, settings)

        assertTrue(syncStr.startsWith(SyncCenter.PREFIX))

        val parsed = SyncCenter.parse(syncStr)
        assertNotNull(parsed)
        assertEquals("test_token", parsed?.optString("trakt_access_token"))
        assertEquals("test_user", parsed?.optString("trakt_username"))
    }

    @Test
    fun testParseInvalid() {
        assertNull(SyncCenter.parse("INVALID-PREFIX:abc"))
        assertNull(SyncCenter.parse("OMNIVERSE-SYNC1:!!!invalid_base64!!!"))
        assertNull(SyncCenter.parse("OMNIVERSE-SYNC1:"))
        val nonObject = java.util.Base64.getEncoder().encodeToString("[]".toByteArray())
        assertNull(SyncCenter.parse(SyncCenter.PREFIX + nonObject))
    }

    @Test
    fun testPayloadTrimsValuesAndOmitsBlankOrLargeFields() {
        val creds = ApiCredentials(
            traktAccessToken = "  access-token  ",
            traktUsername = "   ",
            anilistAccessToken = "large-anilist-token"
        )

        val parsed = SyncCenter.parse(SyncCenter.buildSyncString(creds, UserSettings()))
        assertNotNull(parsed)
        assertEquals("access-token", parsed?.getString("trakt_access_token"))
        assertTrue(parsed?.has("trakt_username") == false)
        assertTrue(parsed?.has("anilist_access_token") == false)
        assertTrue(parsed?.has("settings") == false)
        assertEquals(1, parsed?.getInt("v"))
    }

    @Test
    fun testParserAcceptsWhitespaceAroundPayload() {
        val payload = SyncCenter.buildSyncString(ApiCredentials(tmdbToken = "tmdb"), UserSettings())
        assertEquals("tmdb", SyncCenter.parse("\n $payload \t")?.getString("tmdb_token"))
    }
}

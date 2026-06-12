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
    }
}

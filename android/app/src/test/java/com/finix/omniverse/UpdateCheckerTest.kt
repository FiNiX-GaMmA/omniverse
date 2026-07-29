package com.finix.omniverse

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateCheckerTest {

    @Test
    fun comparesVersionsNumericallyAndRejectsMalformedTags() {
        assertTrue(UpdateChecker.isNewerVersion("2.1.9", "v2.1.10"))
        assertTrue(UpdateChecker.isNewerVersion("2.1", "2.1.1"))
        assertFalse(UpdateChecker.isNewerVersion("2.1.10", "2.1.9"))
        assertFalse(UpdateChecker.isNewerVersion("2.1.10", "2.1.10.0"))
        assertFalse(UpdateChecker.isNewerVersion("2.1.9", "2.1.beta.10"))
        assertFalse(UpdateChecker.isNewerVersion("not-a-version", "2.1.10"))
    }

    @Test
    fun acceptsOnlyOfficialGithubApkAssets() {
        assertTrue(
            UpdateChecker.isTrustedApkUrl(
                "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse-android-arm64.apk"
            )
        )

        listOf(
            "http://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.apk",
            "https://github.com.evil.example/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.apk",
            "https://github.com/another/repo/releases/download/v2.1.80/Omniverse.apk",
            "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/not-omniverse.apk",
            "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.exe",
            "https://github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.apk?mirror=1",
            "https://user@github.com/FiNiX-GaMmA/omniverse/releases/download/v2.1.80/Omniverse.apk",
        ).forEach { assertFalse(it, UpdateChecker.isTrustedApkUrl(it)) }
    }

    @Test
    fun sanitizesReleaseTagsBeforeUsingThemAsFileNames() {
        assertEquals("2.1.80", UpdateChecker.safeVersionFileName("v2.1.80"))
        assertEquals("..-..-payload", UpdateChecker.safeVersionFileName("../../payload"))
        assertEquals("update", UpdateChecker.safeVersionFileName("  v  "))
    }
}

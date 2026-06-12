package com.finix.omniverse

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MediaType {
    @SerialName("movie") MOVIE,
    @SerialName("series") SERIES,
    @SerialName("anime") ANIME,
    @SerialName("liveTv") LIVE_TV;

    val label: String get() = when (this) {
        MOVIE -> "Movie"; SERIES -> "TV Show"; ANIME -> "Anime"; LIVE_TV -> "Live TV"
    }
    val tmdbPath: String get() = if (this == MOVIE) "movie" else "tv"
    val wire: String get() = when (this) {
        MOVIE -> "movie"; SERIES -> "series"; ANIME -> "anime"; LIVE_TV -> "liveTv"
    }
    companion object {
        fun fromWire(s: String?) = when (s) {
            "series" -> SERIES; "anime" -> ANIME; "liveTv" -> LIVE_TV; else -> MOVIE
        }
    }
}

/// Shared image URL resolver (ported from models.dart _imageUrl).
fun imageUrl(path: String?, size: String): String? {
    if (path.isNullOrEmpty()) return null
    if (path.startsWith("http")) return path
    if (path.startsWith("//")) return "https:$path"
    if (path.startsWith("/_next/") || path.startsWith("_next/")) {
        val clean = if (path.startsWith("/")) path else "/$path"
        return "https://onepace.net$clean"
    }
    if (path.startsWith("banners/") || path.startsWith("/banners/")) {
        val clean = if (path.startsWith("/")) path else "/$path"
        return "https://artworks.thetvdb.com$clean"
    }
    return "https://image.tmdb.org/t/p/$size$path"
}

@Serializable
data class ApiCredentials(
    val tmdbToken: String = "",
    val tvdbApiKey: String = "",
    val tvdbPin: String = "",
    val traktClientId: String = "",
    val traktClientSecret: String = "",
    val traktAccessToken: String = "",
    val traktRefreshToken: String = "",
    val traktTokenExpiresAt: Long = 0,
    val traktUsername: String = "",
    val pixeldrainApiKey: String = "",
    val anilistAccessToken: String = "",
) {
    val hasTmdb get() = tmdbToken.trim().isNotEmpty()
    val hasTvdb get() = tvdbApiKey.trim().isNotEmpty()
    val hasTraktApp get() = traktClientId.trim().isNotEmpty()
    val hasTraktUser get() = traktAccessToken.trim().isNotEmpty()
    val hasPixeldrain get() = pixeldrainApiKey.trim().isNotEmpty()
    val hasAnilist get() = anilistAccessToken.trim().isNotEmpty()
    val canRefreshTrakt get() = traktRefreshToken.trim().isNotEmpty() && traktClientSecret.trim().isNotEmpty()
}

@Serializable
data class UserSettings(
    val language: String = "en-US",
    val region: String = "US",
    val includeAdult: Boolean = false,
    val tvMode: Boolean = false,
    val vidsrcDomain: String = "vidsrc-embed.ru",
    val subtitleUrl: String = "",
    val subtitleLanguage: String = "en",
    val preferDubbedAnime: Boolean = false,
    val liveTvCountry: String = "IN",
    val showMoviesTv: Boolean = true,
    val showAnime: Boolean = true,
    val showLiveTv: Boolean = true,
    val stremioManifests: List<String> = emptyList(),
    val preferredSource: String = "vidsrc",
    val disableVidsrc: Boolean = false,
    val stremioServerUrl: String = "http://localhost:11470",
    val enableStremioService: Boolean = true,
) {
    fun applying(o: PlaybackOverrides) = copy(
        subtitleLanguage = o.subtitleLanguage ?: subtitleLanguage,
        subtitleUrl = o.subtitleUrl ?: subtitleUrl,
        preferDubbedAnime = o.preferDubbedAnime ?: preferDubbedAnime,
    )
}

data class PlaybackOverrides(
    val subtitleLanguage: String? = null,
    val subtitleUrl: String? = null,
    val preferDubbedAnime: Boolean? = null,
)

@Serializable
data class MediaSeason(
    val seasonNumber: Int,
    val name: String = "Season",
    val episodeCount: Int = 0,
)

@Serializable
data class MediaEpisode(
    val seasonNumber: Int,
    val episodeNumber: Int,
    val title: String = "Episode",
    val overview: String = "",
    val airDate: String = "",
    val runtimeMinutes: Int? = null,
    val stillPath: String? = null,
) {
    val stillUrl: String? get() = imageUrl(stillPath, "w300")
}

@Serializable
data class MediaItem(
    val id: String,
    val type: MediaType,
    val title: String,
    val overview: String = "",
    val posterPath: String? = null,
    val backdropPath: String? = null,
    val releaseDate: String = "",
    val rating: Double = 0.0,
    val voteCount: Int = 0,
    val genres: List<String> = emptyList(),
    val originCountry: List<String> = emptyList(),
    val cast: List<String> = emptyList(),
    val directors: List<String> = emptyList(),
    val runtimeMinutes: Int? = null,
    val seasons: List<MediaSeason> = emptyList(),
    val episodes: List<MediaEpisode> = emptyList(),
    val tmdbId: Int? = null,
    val tvdbId: Int? = null,
    val traktId: Int? = null,
    val imdbId: String? = null,
    val source: String = "tmdb",
) {
    val posterUrl get() = imageUrl(posterPath, "w342")
    val backdropUrl get() = imageUrl(backdropPath, "w1280")
    val heroBackdropUrl get() = imageUrl(backdropPath, "original")

    val anilistId: Int?
        get() {
            if (!id.startsWith("anilist:") && !id.startsWith("onepace:")) return null
            val parts = id.split(":"); if (parts.size < 3) return null
            return parts.last().toIntOrNull()
        }

    val isAnime: Boolean
        get() {
            if (type == MediaType.ANIME) return true
            if (type != MediaType.MOVIE && type != MediaType.SERIES) return false
            val hasAnimation = genres.any { it.lowercase().contains("animation") }
            val isJapanese = originCountry.any { it.uppercase() == "JP" }
            return hasAnimation && isJapanese
        }
}

@Serializable
data class MediaCategory(
    val id: String,
    val title: String,
    val type: MediaType,
    val items: List<MediaItem>,
    val description: String = "",
    val error: String? = null,
)

@Serializable
data class LiveTvEntry(
    val title: String,
    val url: String,
    val source: String,
    val region: String = "",
    val language: String = "",
    val logoUrl: String? = null,
    val headers: Map<String, String> = emptyMap(),
) {
    val isDirectStream get() = directStream(url)
    companion object {
        fun directStream(url: String): Boolean {
            val lower = url.lowercase()
            return lower.endsWith(".m3u8") || lower.endsWith(".mpd") || lower.endsWith(".mp4") ||
                lower.contains(".m3u8?") || lower.contains(".mpd?") || lower.contains(".mp4?")
        }
    }
}

@Serializable
data class LiveTvSource(
    val id: String,
    val name: String = "Live TV Source",
    val url: String,
    val enabled: Boolean = true,
) { val isDirectStream get() = LiveTvEntry.directStream(url) }

enum class PlaybackSourceKind { EMBED, DIRECT }

data class PlaybackSource(
    val id: String,
    val title: String,
    val url: String,
    val provider: String,
    val kind: PlaybackSourceKind,
    val quality: String = "",
    val headers: Map<String, String> = emptyMap(),
    val subtitleUrl: String = "",
) {
    val isEmbed get() = kind == PlaybackSourceKind.EMBED
    val isDirect get() = kind == PlaybackSourceKind.DIRECT
}

data class TraktDeviceCode(
    val deviceCode: String, val userCode: String, val verificationUrl: String,
    val expiresIn: Int, val interval: Int,
)

@Serializable
data class WatchProgress(
    val id: Int? = null,
    val itemId: String,
    val title: String,
    val type: MediaType,
    val posterPath: String? = null,
    val backdropPath: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val episodeTitle: String? = null,
    val positionMs: Int,
    val durationMs: Int,
    val lastWatchedAt: Long,
) {
    val fraction: Double get() = if (durationMs <= 0) 0.0 else (positionMs.toDouble() / durationMs).coerceIn(0.0, 1.0)
    val posterUrl get() = imageUrl(posterPath, "w342")
    val backdropUrl get() = imageUrl(backdropPath, "w780")
    val progressKey: String get() = itemId
}

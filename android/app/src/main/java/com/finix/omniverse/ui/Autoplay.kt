package com.finix.omniverse.ui

import com.finix.omniverse.AppState
import com.finix.omniverse.MediaEpisode
import com.finix.omniverse.MediaItem
import com.finix.omniverse.MediaType
import com.finix.omniverse.VidsrcExtractor

/// What to play next when an episode finishes. Ported from the Flutter
/// `_autoplayNextEpisode` / `_nextEpisodeFor` logic.
sealed interface AutoplayNext {
    data class Play(val args: PlayerArgs) : AutoplayNext     // a direct stream
    data class Embed(val args: VidsrcArgs) : AutoplayNext    // a VidSrc embed
}

/// Next episode on the current season, or episode 1 of the next season when the
/// current season is exhausted. `null` once the show is over.
internal fun nextEpisodeFor(item: MediaItem, current: MediaEpisode): MediaEpisode? {
    val season = item.seasons.firstOrNull { it.seasonNumber == current.seasonNumber }
    var maxEp = season?.episodeCount ?: item.episodes.size
    if (maxEp <= 0) maxEp = 9999
    val nextNumber = current.episodeNumber + 1
    if (nextNumber > maxEp) {
        val nextSeasonNumber = current.seasonNumber + 1
        return if (item.seasons.any { it.seasonNumber == nextSeasonNumber }) {
            MediaEpisode(nextSeasonNumber, 1, "Episode 1")
        } else {
            null
        }
    }
    return MediaEpisode(current.seasonNumber, nextNumber, "Episode $nextNumber")
}

/// Resolves the next thing to play. Series/anime roll into the next episode (and
/// into season N+1, episode 1, at a season boundary); One Pace resolves the next
/// arc/episode. Movies and Live TV never autoplay. `null` => nothing left to play.
internal suspend fun resolveNextEpisode(item: MediaItem?, episode: MediaEpisode?, appState: AppState): AutoplayNext? {
    if (item == null || episode == null) return null
    if (item.type == MediaType.MOVIE || item.type == MediaType.LIVE_TV) return null

    if (item.title == "One Pace") {
        val apiKey = appState.credentials.pixeldrainApiKey
        fun route(r: OnePaceResume) = AutoplayNext.Play(
            PlayerArgs(r.title, r.url, emptyMap(), r.item, r.episode, r.subtitleUrl, 0, r.aniSkipEpisode),
        )
        resolveOnePaceResume(episode.seasonNumber, episode.episodeNumber + 1, apiKey)?.let { return route(it) }
        resolveOnePaceResume(episode.seasonNumber + 1, 1, apiKey)?.let { return route(it) }
        return null
    }

    val next = nextEpisodeFor(item, episode) ?: return null
    val sources = runCatching { appState.playbackSourcesFor(item, next) }.getOrDefault(emptyList())

    sources.firstOrNull { it.isDirect }?.let { direct ->
        return AutoplayNext.Play(
            PlayerArgs("${item.title} • ${direct.title}", direct.url, direct.headers, item, next, direct.subtitleUrl, null, null),
        )
    }
    // Series fall back to the VidSrc embed resolver, same as a manual play.
    if (item.type == MediaType.SERIES) {
        val embed = sources.firstOrNull { it.isEmbed && it.provider == "VidSrc" }
        if (embed != null) {
            val urls = VidsrcExtractor().embedUrlsFor(
                item, next, appState.settings.vidsrcDomain,
                appState.settings.subtitleUrl, appState.settings.subtitleLanguage,
            )
            if (urls.isNotEmpty()) return AutoplayNext.Embed(VidsrcArgs(item, embed.title, urls, next))
        }
    }
    return null
}

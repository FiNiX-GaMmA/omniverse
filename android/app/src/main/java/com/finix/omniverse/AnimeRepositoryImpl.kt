package com.finix.omniverse

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Calendar
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Contract for the anime playback path. Mirrors the Dart `AnimeRepository`
 * surface and the iOS `AnimeRepositoryProtocol`.
 *
 * NOTE: Another agent owns the repository holder (Repositories.kt). If that
 * file also declares `interface AnimeRepository`, delete this declaration to
 * avoid a duplicate. It is defined here because Repositories.kt was absent at
 * port time.
 */
interface AnimeRepository {
    suspend fun fetchAnimeCategories(): List<MediaCategory>
    suspend fun findByTitle(title: String): MediaItem?
    suspend fun fetchEpisodes(item: MediaItem, seasonNumber: Int): List<MediaEpisode>
    suspend fun resolveSource(item: MediaItem, episode: MediaEpisode, settings: UserSettings): PlaybackSource
    suspend fun updateAniListProgress(accessToken: String, mediaId: Int, progress: Int, status: String)
    suspend fun recommendations(anilistId: Int): List<MediaItem>
}

/**
 * Faithful Kotlin port of ../lib/src/repositories/anime_repository.dart (cross-
 * checked against native/ios/.../AnimeRepository.swift).
 *
 * Routes anime through AniList (metadata) + AllManga / AllAnime (playback), the
 * same path ani-cli uses. The AllAnime episode payload is AES-256-CTR encrypted
 * ("tobeparsed") and source URLs are hex-encoded; both are decoded here with
 * javax.crypto + java.security (no third-party crypto).
 */
class AnimeRepositoryImpl(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false)
        .followSslRedirects(false)
        .build(),
    private val hianime: HianimeRepository = HianimeRepository(),
) : AnimeRepository {

    private val anilist = "https://graphql.anilist.co"
    private val allanime = "https://api.allanime.day/api"

    private val searchGql =
        "query(\$search:SearchInput \$limit:Int \$page:Int \$translationType:VaildTranslationTypeEnumType \$countryOrigin:VaildCountryOriginEnumType){shows(search:\$search limit:\$limit page:\$page translationType:\$translationType countryOrigin:\$countryOrigin){edges{_id name availableEpisodes __typename}}}"
    private val episodeGql =
        "query(\$showId:String! \$translationType:VaildTranslationTypeEnumType! \$episodeString:String!){episode(showId:\$showId translationType:\$translationType episodeString:\$episodeString){episodeString sourceUrls}}"
    private val episodeGqlHash =
        "d405d0edd690624b66baba3068e0edc3ac90f1597d898a1ec8db4e5c43c00fec"
    private val providerPriority = listOf(
        "S-mp4",
        "Luf-Mp4",
        "Yt-mp4",
        "Default",
        "Sl-Hls",
    )

    private val allanimeHeaders: Map<String, String> = mapOf(
        "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
        "Referer" to "https://allmanga.to",
        "Origin" to "https://allmanga.to",
        "Accept" to "*/*",
    )

    private val allmangaHeaders: Map<String, String> = mapOf(
        "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
        "Referer" to "https://allmanga.to",
        "Accept" to "*/*",
    )

    // MARK: - Supporting value types

    data class AnilistEpisodeMeta(val title: String, val thumbnail: String?)

    private data class AnimeCategorySpec(
        val id: String,
        val title: String,
        val description: String,
        val sort: List<String>,
        val format: String? = null,
        val status: String? = null,
        val season: String? = null,
        val seasonYear: Int? = null,
        val genre: String? = null,
    )

    private data class CurrentSeason(val season: String, val label: String, val year: Int)

    private data class SeasonTitle(val title: String, val romaji: String? = null)

    private data class AllAnimeSource(
        val sourceUrl: String,
        val sourceName: String = "",
        val priority: Double = 0.0,
        val path: String = "",
    )

    private data class ResolvedAnimeSource(
        val url: String,
        val resolution: String,
        val sourceName: String,
        val referer: String,
    )

    class AnimeException(message: String) : Exception(message)

    // MARK: - fetchAnimeCategories

    override suspend fun fetchAnimeCategories(): List<MediaCategory> {
        val season = currentAnilistSeason()
        // AniList rate-limits us to 30 requests per minute. Firing one query per
        // category (10 calls in parallel) trips the burst limiter and silently
        // returns `media: []` for most of them. Consolidate everything into one
        // GraphQL request with aliases — one round-trip, one rate-limit slot.
        val categories = listOf(
            AnimeCategorySpec(
                id = "anime_trending",
                title = "Trending Now",
                description = "What everyone is watching right now",
                sort = listOf("TRENDING_DESC"),
            ),
            AnimeCategorySpec(
                id = "anime_airing",
                title = "Currently Airing",
                description = "New episodes still landing each week",
                sort = listOf("POPULARITY_DESC"),
                status = "RELEASING",
            ),
            AnimeCategorySpec(
                id = "anime_this_season",
                title = "${season.label} ${season.year}",
                description = "Highest-buzz shows this season",
                sort = listOf("POPULARITY_DESC"),
                season = season.season,
                seasonYear = season.year,
            ),
            AnimeCategorySpec(
                id = "anime_top_rated",
                title = "All-Time Top Rated",
                description = "Highest scores on AniList",
                sort = listOf("SCORE_DESC"),
            ),
            AnimeCategorySpec(
                id = "anime_popular",
                title = "All-Time Popular",
                description = "Most-watched anime ever",
                sort = listOf("POPULARITY_DESC"),
            ),
            AnimeCategorySpec(
                id = "anime_recent",
                title = "Recently Added",
                description = "Newest additions to AniList",
                sort = listOf("ID_DESC"),
            ),
            AnimeCategorySpec(
                id = "anime_movies",
                title = "Anime Movies",
                description = "Movie-format anime",
                sort = listOf("SCORE_DESC"),
                format = "MOVIE",
            ),
            AnimeCategorySpec(
                id = "anime_action",
                title = "Action",
                description = "High-octane action picks",
                sort = listOf("POPULARITY_DESC"),
                genre = "Action",
            ),
            AnimeCategorySpec(
                id = "anime_romance",
                title = "Romance",
                description = "Love stories and slice-of-life",
                sort = listOf("POPULARITY_DESC"),
                genre = "Romance",
            ),
            AnimeCategorySpec(
                id = "anime_fantasy",
                title = "Fantasy",
                description = "Magic, isekai, and worlds elsewhere",
                sort = listOf("POPULARITY_DESC"),
                genre = "Fantasy",
            ),
        )

        val aliasBlocks = StringBuilder()
        for ((i, c) in categories.withIndex()) {
            val args = buildList {
                add("type: ANIME")
                add("sort: ${gqlEnumList(c.sort)}")
                if (c.format != null) add("format: ${c.format}")
                if (c.status != null) add("status: ${c.status}")
                if (c.season != null) add("season: ${c.season}")
                if (c.seasonYear != null) add("seasonYear: ${c.seasonYear}")
                if (c.genre != null) add("genre: \"${c.genre}\"")
                add("isAdult: false")
            }
            aliasBlocks.append(
                "  r$i: Page(page: 1, perPage: 24) { media(${args.joinToString(", ")}) { ...animeFields } }\n",
            )
        }

        val query = """
fragment animeFields on Media {
  id
  title { romaji english native }
  description(asHtml: false)
  coverImage { extraLarge large }
  bannerImage
  genres
  averageScore
  episodes
  duration
  format
  seasonYear
  startDate { year month day }
  studios(isMain: true) { nodes { name } }
}
query {
$aliasBlocks
}
"""

        return try {
            val body = postJson(anilist, JSONObject().put("query", query))
            val data = body.optJSONObject("data") ?: JSONObject()
            categories.mapIndexed { i, c ->
                val media = data.optJSONObject("r$i")?.optJSONArray("media")
                val items = if (media != null) {
                    (0 until media.length())
                        .mapNotNull { media.optJSONObject(it) }
                        .map { mediaFromAnilist(it) }
                } else {
                    emptyList()
                }
                MediaCategory(
                    id = c.id,
                    title = c.title,
                    type = MediaType.ANIME,
                    items = items,
                    description = c.description,
                    error = if (items.isEmpty()) "No results from AniList" else null,
                )
            }
        } catch (error: Throwable) {
            categories.map { c ->
                MediaCategory(
                    id = c.id,
                    title = c.title,
                    type = MediaType.ANIME,
                    items = emptyList(),
                    description = c.description,
                    error = "Anime row could not load: $error",
                )
            }
        }
    }

    private fun gqlEnumList(values: List<String>): String = "[${values.joinToString(", ")}]"

    /** Maps the current calendar month to AniList's MediaSeason enum + year. */
    private fun currentAnilistSeason(): CurrentSeason {
        val cal = Calendar.getInstance()
        val m = cal.get(Calendar.MONTH) + 1
        val year = cal.get(Calendar.YEAR)
        val season = when (m) {
            1, 2, 3 -> "WINTER"
            4, 5, 6 -> "SPRING"
            7, 8, 9 -> "SUMMER"
            else -> "FALL"
        }
        val label = season.substring(0, 1) + season.substring(1).lowercase()
        return CurrentSeason(season = season, label = label, year = year)
    }

    // MARK: - findByTitle

    /**
     * Searches AniList by title and returns the best anime match as an
     * AniList-sourced MediaItem, so a TMDB show flagged as anime can be
     * re-routed through the AllManga playback path. Returns `null` if no match
     * is found or the request fails.
     */
    override suspend fun findByTitle(title: String): MediaItem? {
        val query = title.trim()
        if (query.isEmpty()) return null
        val gql = """
query(${'$'}search: String) {
  Page(page: 1, perPage: 5) {
    media(type: ANIME, search: ${'$'}search, sort: [SEARCH_MATCH, POPULARITY_DESC], isAdult: false) {
      id
      title { romaji english native }
      description(asHtml: false)
      coverImage { extraLarge large }
      bannerImage
      genres
      averageScore
      episodes
      duration
      format
      seasonYear
      startDate { year month day }
      studios(isMain: true) { nodes { name } }
    }
  }
}
"""
        return try {
            val body = postJson(
                anilist,
                JSONObject()
                    .put("query", gql)
                    .put("variables", JSONObject().put("search", query)),
            )
            val media = body.optJSONObject("data")?.optJSONObject("Page")?.optJSONArray("media")
            if (media == null || media.length() == 0) return null
            var first: JSONObject? = null
            for (i in 0 until media.length()) {
                val obj = media.optJSONObject(i)
                if (obj != null) {
                    first = obj
                    break
                }
            }
            first?.let { mediaFromAnilist(it) }
        } catch (_: Throwable) {
            null
        }
    }

    // MARK: - recommendations

    /// AniList "you might also like" recommendations for an anime, used by the
    /// end-of-show recommendation rail when there are no more episodes/seasons.
    override suspend fun recommendations(anilistId: Int): List<MediaItem> {
        val gql = """
query (${'$'}id: Int) {
  Media(id: ${'$'}id, type: ANIME) {
    recommendations(sort: RATING_DESC, perPage: 24) {
      nodes {
        mediaRecommendation {
          id
          title { romaji english native }
          description(asHtml: false)
          coverImage { extraLarge large }
          bannerImage
          genres
          averageScore
          episodes
          duration
          format
          seasonYear
          startDate { year month day }
          studios(isMain: true) { nodes { name } }
        }
      }
    }
  }
}
"""
        return try {
            val body = postJson(
                anilist,
                JSONObject().put("query", gql).put("variables", JSONObject().put("id", anilistId)),
            )
            val nodes = body.optJSONObject("data")?.optJSONObject("Media")
                ?.optJSONObject("recommendations")?.optJSONArray("nodes") ?: return emptyList()
            val out = ArrayList<MediaItem>()
            for (i in 0 until nodes.length()) {
                val rec = nodes.optJSONObject(i)?.optJSONObject("mediaRecommendation") ?: continue
                val item = mediaFromAnilist(rec)
                if (item.posterPath != null || item.backdropPath != null) out.add(item)
            }
            out
        } catch (_: Throwable) {
            emptyList()
        }
    }

    // MARK: - fetchEpisodes

    override suspend fun fetchEpisodes(item: MediaItem, seasonNumber: Int): List<MediaEpisode> {
        val season = item.seasons.firstOrNull { it.seasonNumber == seasonNumber }
        // Movie-format anime: just one entry.
        if (season?.episodeCount == 1) {
            return listOf(MediaEpisode(seasonNumber = 1, episodeNumber = 1, title = "Movie"))
        }

        // Resolve the right title for this season (sequels are separate AniList
        // entries with their own episode counts on AllAnime).
        val seasonTitle = anilistSeasonTitle(item.title, seasonNumber)
        val searchTitle = seasonTitle.title

        // Pull the actual available episode count from AllAnime — AniList's
        // `episodes` field is the planned total, which is wrong for airing shows
        // and split-season releases. Fall back to AniList's count if AllAnime
        // doesn't know the show yet.
        val liveCount = allmangaEpisodeCount(searchTitle)
        val plannedCount = season?.episodeCount ?: item.episodes.size
        val count = liveCount ?: plannedCount
        if (count <= 0) return emptyList()

        // Look up real per-episode titles + thumbnails from AniList's
        // streamingEpisodes when present.
        val meta = anilistEpisodeMeta(searchTitle)

        return (1..count).map { ep ->
            MediaEpisode(
                seasonNumber = seasonNumber,
                episodeNumber = ep,
                title = meta[ep]?.title ?: "Episode $ep",
                stillPath = meta[ep]?.thumbnail,
            )
        }
    }

    private suspend fun allmangaEpisodeCount(title: String): Int? {
        return try {
            val edges = searchAllmanga(title, "sub")
            if (edges == null || edges.isEmpty()) return null
            val lower = title.lowercase().trim()
            val entry = edges.firstOrNull {
                (it.optString("name").lowercase().trim()) == lower
            } ?: edges.first()
            val available = entry.optJSONObject("availableEpisodes") ?: return null
            val sub = available.optInt("sub", 0)
            val dub = available.optInt("dub", 0)
            val raw = available.optInt("raw", 0)
            val maxVal = listOf(sub, dub, raw).fold(0) { a, b -> if (b > a) b else a }
            if (maxVal == 0) null else maxVal
        } catch (_: Throwable) {
            null
        }
    }

    suspend fun anilistEpisodeMeta(title: String): Map<Int, AnilistEpisodeMeta> {
        val gql = """
query(${'$'}search: String) {
  Media(type: ANIME, search: ${'$'}search, sort: SEARCH_MATCH) {
    streamingEpisodes { title thumbnail }
  }
}
"""
        return try {
            val body = postJson(
                anilist,
                JSONObject()
                    .put("query", gql)
                    .put("variables", JSONObject().put("search", title)),
            )
            val eps = body.optJSONObject("data")?.optJSONObject("Media")?.optJSONArray("streamingEpisodes")
                ?: return emptyMap()
            val out = HashMap<Int, AnilistEpisodeMeta>()
            // streamingEpisodes are normally returned in order. Common title shapes:
            // "Episode 1 - To You, In 2000 Years", "1 - Origins", just "Origins".
            val pattern = Regex("^(?:Episode\\s+)?(\\d+)\\s*[-:.|]\\s*(.+)$", RegexOption.IGNORE_CASE)
            for (i in 0 until eps.length()) {
                val entry = eps.optJSONObject(i) ?: continue
                val raw = entry.optString("title", "").trim()
                val thumb = entry.optString("thumbnail", "").trim()
                val thumbValue = thumb.ifEmpty { null }
                var number = i + 1
                var titleText = raw
                val match = pattern.find(raw)
                if (match != null) {
                    val n = match.groupValues.getOrNull(1)?.toIntOrNull()
                    val t = match.groupValues.getOrNull(2)?.trim()
                    if (n != null && !t.isNullOrEmpty()) {
                        number = n
                        titleText = t
                    }
                }
                out[number] = AnilistEpisodeMeta(title = titleText, thumbnail = thumbValue)
            }
            out
        } catch (_: Throwable) {
            emptyMap()
        }
    }

    // MARK: - resolveSource

    override suspend fun resolveSource(
        item: MediaItem,
        episode: MediaEpisode,
        settings: UserSettings,
    ): PlaybackSource {
        val dub = settings.preferDubbedAnime
        val translationType = if (dub) "dub" else "sub"
        val isMovie = item.seasons.firstOrNull()?.episodeCount == 1 && episode.episodeNumber == 1

        // AllAnime — primary path. Same path ani-cli uses.
        var result = resolveAllmanga(
            title = item.title,
            seasonNumber = episode.seasonNumber,
            episodeNumber = episode.episodeNumber,
            isMovie = isMovie,
            translationType = translationType,
        )
        if (result == null && translationType == "dub") {
            result = resolveAllmanga(
                title = item.title,
                seasonNumber = episode.seasonNumber,
                episodeNumber = episode.episodeNumber,
                isMovie = isMovie,
                translationType = "sub",
            )
        }
        val resolved = result ?: throw AnimeException("No playable anime source found for ${item.title}.")
        return PlaybackSource(
            id = "allmanga:${item.id}:${episode.seasonNumber}:${episode.episodeNumber}",
            title = "${resolved.sourceName} ${resolved.resolution}".trim(),
            url = resolved.url,
            provider = "AllManga",
            kind = PlaybackSourceKind.DIRECT,
            quality = resolved.resolution,
            headers = mapOf("Referer" to resolved.referer),
            subtitleUrl = settings.subtitleUrl.trim(),
        )
    }

    // MARK: - mediaFromAnilist

    private fun mediaFromAnilist(json: JSONObject): MediaItem {
        val id = json.optInt("id", 0)
        val titleJson = json.optJSONObject("title") ?: JSONObject()
        val title = titleJson.optStringOrNull("english")
            ?: titleJson.optStringOrNull("romaji")
            ?: titleJson.optStringOrNull("native")
            ?: "Anime"
        val episodes = if (json.has("episodes") && !json.isNull("episodes")) {
            json.optInt("episodes")
        } else {
            if (json.optStringOrNull("format") == "MOVIE") 1 else 0
        }
        val year: Int? = if (json.has("seasonYear") && !json.isNull("seasonYear")) {
            json.optInt("seasonYear")
        } else {
            json.optJSONObject("startDate")?.let {
                if (it.has("year") && !it.isNull("year")) it.optInt("year") else null
            }
        }
        val studiosArr = json.optJSONObject("studios")?.optJSONArray("nodes") ?: JSONArray()
        val studios = (0 until studiosArr.length())
            .mapNotNull { studiosArr.optJSONObject(it) }
            .mapNotNull { it.optStringOrNull("name") }
            .filter { it.isNotEmpty() }
            .take(3)
        val format = json.optStringOrNull("format")
        return MediaItem(
            id = "anilist:anime:$id",
            type = MediaType.ANIME,
            title = title,
            overview = cleanDescription(json.optStringOrNull("description") ?: ""),
            posterPath = json.optJSONObject("coverImage")?.optStringOrNull("extraLarge")
                ?: json.optJSONObject("coverImage")?.optStringOrNull("large"),
            backdropPath = json.optStringOrNull("bannerImage"),
            releaseDate = year?.toString() ?: "",
            rating = (if (json.has("averageScore") && !json.isNull("averageScore")) json.optDouble("averageScore", 0.0) else 0.0) / 10.0,
            genres = json.optJSONArray("genres").toStringList(),
            directors = studios,
            runtimeMinutes = if (json.has("duration") && !json.isNull("duration")) json.optInt("duration") else null,
            seasons = listOf(
                MediaSeason(
                    seasonNumber = 1,
                    name = if (format == "MOVIE") "Movie" else "Season 1",
                    episodeCount = episodes,
                ),
            ),
            source = "anilist",
        )
    }

    // MARK: - AllManga resolution

    private suspend fun resolveAllmanga(
        title: String,
        seasonNumber: Int,
        episodeNumber: Int,
        isMovie: Boolean,
        translationType: String,
    ): ResolvedAnimeSource? {
        val dubSub = if (translationType == "dub") "dub" else "sub"
        val seasonTitle = if (isMovie) SeasonTitle(title = title) else anilistSeasonTitle(title, seasonNumber)
        val epStr = if (isMovie) "1" else episodeNumber.toString()

        // Ordered, de-duplicated candidate list (honour the Dart literal-set
        // order while dropping repeats and blanks).
        val seen = LinkedHashSet<String>()
        fun addCandidate(value: String) {
            if (value.trim().isEmpty()) return
            seen.add(value)
        }
        addCandidate(seasonTitle.title)
        addCandidate(sanitizeTitle(seasonTitle.title))
        if (seasonTitle.romaji != null) addCandidate(seasonTitle.romaji)
        addCandidate(title)
        addCandidate(sanitizeTitle(title))
        val candidates = seen.toList()

        var edges: List<JSONObject>? = null
        var matchedTitle = seasonTitle.title
        for (candidate in candidates) {
            edges = try {
                searchAllmanga(candidate, dubSub)
            } catch (_: Throwable) {
                null
            }
            if (edges != null && edges.isNotEmpty()) {
                matchedTitle = candidate
                break
            }
        }
        val resolvedEdges = edges ?: return null
        if (resolvedEdges.isEmpty()) return null

        val normalized = matchedTitle.lowercase()
        val anime = resolvedEdges.firstOrNull {
            (it.optString("name").lowercase()) == normalized
        } ?: resolvedEdges.first()
        val showId = anime.optStringOrNull("_id") ?: return null
        if (showId.isEmpty()) return null

        val sourceUrls = episodeSourceUrls(showId = showId, translationType = dubSub, episodeString = epStr)
        if (sourceUrls == null || sourceUrls.isEmpty()) return null
        return trySourceUrls(sourceUrls)
    }

    private suspend fun anilistSeasonTitle(baseTitle: String, seasonNumber: Int): SeasonTitle {
        if (seasonNumber <= 1) return SeasonTitle(title = baseTitle)
        val query = """
query(${'$'}search:String) {
  Media(search: ${'$'}search, type: ANIME, sort: SEARCH_MATCH) {
    title { english romaji }
    relations {
      edges {
        relationType
        node {
          type
          format
          title { english romaji }
          startDate { year }
          seasonYear
        }
      }
    }
  }
}
"""
        return try {
            val body = postJson(
                anilist,
                JSONObject()
                    .put("query", query)
                    .put("variables", JSONObject().put("search", baseTitle)),
            )
            val media = body.optJSONObject("data")?.optJSONObject("Media") ?: return SeasonTitle(title = baseTitle)
            val relations = media.optJSONObject("relations")?.optJSONArray("edges") ?: JSONArray()
            val sequels = (0 until relations.length())
                .mapNotNull { relations.optJSONObject(it) }
                .filter { edge ->
                    val node = edge.optJSONObject("node") ?: JSONObject()
                    edge.optStringOrNull("relationType") == "SEQUEL" &&
                        node.optStringOrNull("type") == "ANIME" &&
                        (node.optStringOrNull("format") == "TV" || node.optStringOrNull("format") == "TV_SHORT")
                }
                .sortedBy { edge ->
                    val node = edge.optJSONObject("node") ?: JSONObject()
                    val start = node.optJSONObject("startDate")
                    val startYear = if (start != null && start.has("year") && !start.isNull("year")) start.optInt("year") else null
                    startYear
                        ?: (if (node.has("seasonYear") && !node.isNull("seasonYear")) node.optInt("seasonYear") else null)
                        ?: 9999
                }
            val targetIndex = seasonNumber - 2
            if (targetIndex < 0 || targetIndex >= sequels.size) return SeasonTitle(title = baseTitle)
            val node = sequels[targetIndex].optJSONObject("node")
            val title = node?.optJSONObject("title")
            SeasonTitle(
                title = title?.optStringOrNull("english") ?: title?.optStringOrNull("romaji") ?: baseTitle,
                romaji = title?.optStringOrNull("romaji"),
            )
        } catch (_: Throwable) {
            SeasonTitle(title = baseTitle)
        }
    }

    private suspend fun searchAllmanga(query: String, translationType: String): List<JSONObject>? {
        val variables = JSONObject()
            .put(
                "search",
                JSONObject()
                    .put("allowAdult", false)
                    .put("allowUnknown", false)
                    .put("query", query.lowercase()),
            )
            .put("limit", 40)
            .put("page", 1)
            .put("translationType", translationType)
            .put("countryOrigin", "ALL")
        val body = allanimeGql(variables, searchGql)
        val edges = body.optJSONObject("data")?.optJSONObject("shows")?.optJSONArray("edges") ?: return null
        return (0 until edges.length()).mapNotNull { edges.optJSONObject(it) }
    }

    private suspend fun episodeSourceUrls(
        showId: String,
        translationType: String,
        episodeString: String,
    ): List<AllAnimeSource>? {
        val candidates = buildList {
            add(episodeString)
            if (!episodeString.contains(".")) add("$episodeString.0")
        }
        for (candidate in candidates) {
            val body = allanimeEpisodeGql(
                JSONObject()
                    .put("showId", showId)
                    .put("translationType", translationType)
                    .put("episodeString", candidate),
            )
            val sources = parseEpisodeSourceUrls(body)
            if (sources != null && sources.isNotEmpty()) return sources
        }
        return null
    }

    private suspend fun allanimeGql(variables: JSONObject, query: String): JSONObject {
        return postJson(
            allanime,
            JSONObject()
                .put("variables", variables)
                .put("query", query),
            allanimeHeaders,
        )
    }

    private suspend fun allanimeEpisodeGql(variables: JSONObject): String {
        // GET path with persisted-query extensions first.
        try {
            val extensions = JSONObject()
                .put(
                    "persistedQuery",
                    JSONObject().put("version", 1).put("sha256Hash", episodeGqlHash),
                )
                .toString()
            val url = allanime.toHttpUrlOrNull()?.newBuilder()
                ?.addQueryParameter("variables", variables.toString())
                ?.addQueryParameter("extensions", extensions)
                ?.build()
            if (url != null) {
                val headers = allanimeHeaders + ("Origin" to "https://youtu-chan.com")
                val resp = get(url.toString(), headers, 12)
                if (resp != null && resp.code < 400 && resp.body != null) {
                    val parsed = parseEpisodeSourceUrls(resp.body)
                    if (parsed != null && parsed.isNotEmpty()) {
                        return resp.body
                    }
                }
            }
        } catch (_: Throwable) {
            // Fall back to the normal POST shape below.
        }
        return try {
            allanimeGql(variables, episodeGql).toString()
        } catch (_: Throwable) {
            ""
        }
    }

    private fun parseEpisodeSourceUrls(body: String): List<AllAnimeSource>? {
        // First: the encrypted "tobeparsed" blob.
        val encrypted = Regex("\"tobeparsed\"\\s*:\\s*\"([^\"]+)\"").find(body)
        if (encrypted != null) {
            val sources = decodeTobeparsed(encrypted.groupValues[1])
            if (sources.isNotEmpty()) return sources
        }
        return try {
            val json = JSONObject(body)
            val sourceUrls = json.optJSONObject("data")?.optJSONObject("episode")?.optJSONArray("sourceUrls")
                ?: return null
            (0 until sourceUrls.length())
                .mapNotNull { sourceUrls.optJSONObject(it) }
                .map { j ->
                    AllAnimeSource(
                        sourceUrl = j.optString("sourceUrl", ""),
                        sourceName = j.optString("sourceName", ""),
                        priority = j.optDouble("priority", 0.0),
                    )
                }
        } catch (_: Throwable) {
            null
        }
    }

    // MARK: - tobeparsed decode (AES-256-CTR)

    private fun decodeTobeparsed(blob: String): List<AllAnimeSource> {
        return try {
            val bytes = android.util.Base64.decode(blob, android.util.Base64.DEFAULT)
            if (bytes.size <= 29) return emptyList()
            // key = SHA-256(utf8("Xot36i3lK3:v1"))
            val key = MessageDigest.getInstance("SHA-256").digest("Xot36i3lK3:v1".toByteArray(Charsets.UTF_8))
            // iv = bytes[1..12] + [0,0,0,2]  (16 bytes)
            val iv = bytes.copyOfRange(1, 13) + byteArrayOf(0, 0, 0, 2)
            val ciphertext = bytes.copyOfRange(13, bytes.size - 16)
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
            val plainBytes = cipher.doFinal(ciphertext)
            val plain = String(plainBytes, Charsets.UTF_8) // lossy UTF-8

            val sources = ArrayList<AllAnimeSource>()
            // Split on regex [{}].
            for (chunk in plain.split(Regex("[{}]"))) {
                val url = Regex("\"sourceUrl\"\\s*:\\s*\"(--[^\"]+)\"").find(chunk) ?: continue
                val name = Regex("\"sourceName\"\\s*:\\s*\"([^\"]+)\"").find(chunk)
                val priority = Regex("\"priority\"\\s*:\\s*([0-9.]+)").find(chunk)
                sources.add(
                    AllAnimeSource(
                        sourceUrl = url.groupValues[1],
                        sourceName = name?.groupValues?.get(1) ?: "",
                        priority = priority?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0,
                    ),
                )
            }
            sources
        } catch (_: Throwable) {
            emptyList()
        }
    }

    // MARK: - trySourceUrls

    private suspend fun trySourceUrls(sourceUrls: List<AllAnimeSource>): ResolvedAnimeSource? {
        val decoded = sourceUrls
            .filter { it.sourceUrl.isNotEmpty() }
            .map { source ->
                val path = if (source.sourceUrl.startsWith("--")) {
                    decodeAllanimeUrl(source.sourceUrl).replace("/clock", "/clock.json")
                } else {
                    source.sourceUrl
                }
                source.copy(path = path)
            }
            .sortedBy {
                val index = providerPriority.indexOf(it.sourceName)
                if (index == -1) 99 else index
            }

        for (source in decoded) {
            val fetchUrl = normalizeAllanimeUrl(source.path) ?: continue
            try {
                if (fetchUrl.contains("fast4speed.rsvp") || source.sourceName == "Yt-mp4") {
                    val finalUrl = followRedirects(fetchUrl)
                    if (isDirectVideoUrl(finalUrl) && !isYoutubeUrl(finalUrl)) {
                        return ResolvedAnimeSource(
                            url = finalUrl,
                            resolution = "?",
                            sourceName = source.sourceName,
                            referer = "https://allmanga.to",
                        )
                    }
                    continue
                }

                val resp = get(fetchUrl, allmangaHeaders, 12)
                if (resp == null || resp.code != 200 || resp.body.isNullOrEmpty()) continue
                val json = JSONObject(resp.body)
                val links = json.optJSONArray("links") ?: continue
                val playable = (0 until links.length())
                    .mapNotNull { links.optJSONObject(it) }
                    .filter { it.opt("link") is String }
                if (playable.isEmpty()) continue
                val mp4Links = playable.filter { link ->
                    val u = link.optString("link").lowercase()
                    !u.contains(".m3u8") && !u.contains("master.")
                }
                val chosen = (if (mp4Links.isEmpty()) playable else mp4Links)
                    .sortedByDescending { resolution(it.opt("resolutionStr")) }
                val best = chosen.firstOrNull() ?: continue
                val url = best.optStringOrNull("link") ?: continue
                if (!isDirectVideoUrl(url)) continue
                return ResolvedAnimeSource(
                    url = url,
                    resolution = best.optStringOrNull("resolutionStr") ?: "?",
                    sourceName = source.sourceName,
                    referer = "https://allmanga.to",
                )
            } catch (_: Throwable) {
                continue
            }
        }
        return null
    }

    private suspend fun followRedirects(value: String, maxHops: Int = 10): String {
        var url = value.toHttpUrlOrNull() ?: return value
        for (hop in 0 until maxHops) {
            val resp = withContext(Dispatchers.IO) {
                try {
                    val scoped = client.newBuilder()
                        .followRedirects(false)
                        .followSslRedirects(false)
                        .callTimeout(10, TimeUnit.SECONDS)
                        .build()
                    val builder = Request.Builder().url(url).head()
                    allmangaHeaders.forEach { (k, v) -> builder.header(k, v) }
                    scoped.newCall(builder.build()).execute().use { response ->
                        val location = response.header("Location")
                        Pair(response.code, location)
                    }
                } catch (_: Throwable) {
                    null
                }
            } ?: return url.toString()
            val (code, location) = resp
            if (code in 300..399 && location != null) {
                val resolved = url.resolve(location) ?: return url.toString()
                url = resolved
                continue
            }
            return url.toString()
        }
        return url.toString()
    }

    // MARK: - HTTP helpers

    private suspend fun postJson(
        url: String,
        body: JSONObject,
        headers: Map<String, String> = emptyMap(),
    ): JSONObject = withContext(Dispatchers.IO) {
        val scoped = client.newBuilder()
            .callTimeout(14, TimeUnit.SECONDS)
            .readTimeout(14, TimeUnit.SECONDS)
            .connectTimeout(14, TimeUnit.SECONDS)
            .build()
        val builder = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
        headers.forEach { (k, v) -> builder.header(k, v) }
        scoped.newCall(builder.build()).execute().use { response ->
            val host = url.toHttpUrlOrNull()?.host ?: ""
            if (response.code >= 400) {
                throw AnimeException("$host returned ${response.code}")
            }
            JSONObject(response.body?.string() ?: "{}")
        }
    }

    private data class HttpResponse(val code: Int, val body: String?)

    private suspend fun get(
        url: String,
        headers: Map<String, String>,
        timeoutSeconds: Long,
    ): HttpResponse? = withContext(Dispatchers.IO) {
        try {
            val scoped = client.newBuilder()
                .followRedirects(true)
                .followSslRedirects(true)
                .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .readTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .connectTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()
            val builder = Request.Builder().url(url).get()
            headers.forEach { (k, v) -> builder.header(k, v) }
            scoped.newCall(builder.build()).execute().use { response ->
                HttpResponse(response.code, response.body?.string())
            }
        } catch (_: Throwable) {
            null
        }
    }

    // MARK: - URL / text helpers

    private fun normalizeAllanimeUrl(value: String): String? {
        if (value.startsWith("//")) return "https:$value"
        if (value.startsWith("/")) return "https://allanime.day$value"
        if (value.startsWith("http")) return value
        if (value.isNotEmpty()) return "https://allanime.day/$value"
        return null
    }

    private fun isDirectVideoUrl(value: String): Boolean {
        val lower = value.lowercase()
        if (lower.contains("googlevideo.com")) return true
        return Regex("\\.(mp4|webm|m4v|mov|m3u8)(\\?|$)").containsMatchIn(lower)
    }

    private fun isYoutubeUrl(value: String): Boolean {
        val lower = value.lowercase()
        return lower.contains("youtube.com/watch") || lower.contains("youtu.be/")
    }

    private fun resolution(value: Any?): Int {
        val text = value?.toString() ?: ""
        return Regex("\\d+").find(text)?.value?.toIntOrNull() ?: 0
    }

    private fun sanitizeTitle(value: String): String {
        return value
            .replace(Regex("[''`´]"), "")
            .replace(Regex("[:!.]"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun cleanDescription(value: String): String {
        return value
            .replace(Regex("<[^>]*>"), "")
            .replace(Regex("\\(Source:[^)]*\\)", RegexOption.IGNORE_CASE), "")
            .replace(Regex("\\bNote:[^\\n]*", RegexOption.IGNORE_CASE), "")
            .trim()
    }

    // MARK: - AllAnime hex URL decode

    private fun decodeAllanimeUrl(encoded: String): String {
        val value = if (encoded.startsWith("--")) encoded.substring(2) else encoded
        val buffer = StringBuilder()
        var index = 0
        while (index < value.length) {
            val end = minOf(index + 2, value.length)
            val pair = value.substring(index, end)
            buffer.append(allanimeHexMap[pair] ?: pair)
            index += 2
        }
        // replace "/" -> "/" and remove literal "\|"
        return buffer.toString()
            .replace("\\u002F", "/")
            .replace("\\|", "")
    }

    // MARK: - updateAniListProgress

    override suspend fun updateAniListProgress(
        accessToken: String,
        mediaId: Int,
        progress: Int,
        status: String,
    ) {
        val mutation = """
      mutation (${'$'}mediaId: Int, ${'$'}progress: Int, ${'$'}status: MediaListStatus) {
        SaveMediaListEntry (mediaId: ${'$'}mediaId, progress: ${'$'}progress, status: ${'$'}status) {
          id
          progress
          status
        }
      }
    """
        val bodyDict = JSONObject()
            .put("query", mutation)
            .put(
                "variables",
                JSONObject()
                    .put("mediaId", mediaId)
                    .put("progress", progress)
                    .put("status", status),
            )
        withContext(Dispatchers.IO) {
            val builder = Request.Builder()
                .url(anilist)
                .post(bodyDict.toString().toRequestBody("application/json".toMediaType()))
                .header("Authorization", "Bearer $accessToken")
                .header("Content-Type", "application/json")
                .header("Accept", "application/json")
            client.newCall(builder.build()).execute().use { response ->
                if (response.code >= 400) {
                    val text = response.body?.string() ?: ""
                    throw AnimeException("AniList progress update returned ${response.code}: $text")
                }
            }
        }
    }

    // MARK: - JSON helpers

    private fun JSONObject.optStringOrNull(key: String): String? {
        if (!has(key) || isNull(key)) return null
        val v = optString(key, "")
        return v.ifEmpty { null }
    }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull {
            val v = optString(it, "")
            v.ifEmpty { null }
        }
    }

    // MARK: - AllAnime hex map (copied verbatim from anime_repository.dart)

    private val allanimeHexMap: Map<String, String> = mapOf(
        "79" to "A", "7a" to "B", "7b" to "C", "7c" to "D", "7d" to "E", "7e" to "F", "7f" to "G",
        "70" to "H", "71" to "I", "72" to "J", "73" to "K", "74" to "L", "75" to "M", "76" to "N",
        "77" to "O", "68" to "P", "69" to "Q", "6a" to "R", "6b" to "S", "6c" to "T", "6d" to "U",
        "6e" to "V", "6f" to "W", "60" to "X", "61" to "Y", "62" to "Z", "59" to "a", "5a" to "b",
        "5b" to "c", "5c" to "d", "5d" to "e", "5e" to "f", "5f" to "g", "50" to "h", "51" to "i",
        "52" to "j", "53" to "k", "54" to "l", "55" to "m", "56" to "n", "57" to "o", "48" to "p",
        "49" to "q", "4a" to "r", "4b" to "s", "4c" to "t", "4d" to "u", "4e" to "v", "4f" to "w",
        "40" to "x", "41" to "y", "42" to "z", "08" to "0", "09" to "1", "0a" to "2", "0b" to "3",
        "0c" to "4", "0d" to "5", "0e" to "6", "0f" to "7", "00" to "8", "01" to "9", "15" to "-",
        "16" to ".", "67" to "_", "46" to "~", "02" to ":", "17" to "/", "07" to "?", "1b" to "#",
        "63" to "[", "65" to "]", "78" to "@", "19" to "!", "1c" to "$", "1e" to "&", "10" to "(",
        "11" to ")", "12" to "*", "13" to "+", "14" to ",", "03" to ";", "05" to "=", "1d" to "%",
    )
}

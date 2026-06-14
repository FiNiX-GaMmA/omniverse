package com.finix.omniverse

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Streams anime from the hianime / aniwatch / Zoro front-end. Four-step flow,
 * modelled after the community-maintained `aniwatch-api` and ani-cli's hianime
 * fork:
 *
 *   1. GET `/search?keyword=…`               → list of shows (HTML)
 *   2. GET `/ajax/v2/episode/list/{animeId}` → list of episodes (HTML in JSON)
 *   3. GET `/ajax/v2/episode/servers?episodeId={epId}` → server tiles
 *   4. GET `/ajax/v2/episode/sources?id={serverId}`   → Megacloud embed URL
 *
 * The Megacloud embed is then decrypted in [MegacloudDecryptor] — that's the
 * AES-256-CBC step where keys rotate upstream.
 *
 * Faithful port of ../lib/src/repositories/hianime_repository.dart. HTML is
 * parsed with jsoup.
 */

data class HianimeStream(
    val url: String,
    val referer: String,
    val subtitleUrl: String,
    val serverName: String,
    val mirror: String,
)

data class MegacloudResolved(
    val url: String,
    val referer: String,
    val subtitleUrl: String,
)

class HianimeRepository(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .build(),
    private val decryptor: MegacloudDecryptor = MegacloudDecryptor(),
) {

    /**
     * All mirrors hianime is currently served from. Tried in order until one
     * returns 2xx for the search call; the winning host is then reused for the
     * rest of the chain on this resolve call.
     */
    private val mirrors: List<String> = listOf(
        "https://hianime.to",
        "https://hianimez.to",
        "https://hianime.bz",
        "https://hianime.cx",
        "https://hianime.do",
        "https://hianime.gs",
        "https://hianime.nz",
        "https://hianime.pe",
        "https://hianime.sx",
        "https://hianimez.is",
    )

    private val userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    private fun headersFor(base: String): Map<String, String> = mapOf(
        "User-Agent" to userAgent,
        "Referer" to "$base/",
        "X-Requested-With" to "XMLHttpRequest",
        "Accept" to "text/html,application/xhtml+xml,application/xml,application/json",
    )

    private data class HiShow(val id: String, val name: String)
    private data class HiEpisode(val id: String, val number: Int)
    private data class HiServer(val id: String, val name: String, val type: String)

    /**
     * Top-level entry point. Returns the resolved direct stream + subtitles for
     * a single episode, or `null` if no mirror could deliver one.
     */
    suspend fun resolve(title: String, episodeNumber: Int, dub: Boolean): HianimeStream? {
        for (base in mirrors) {
            try {
                val result = withTimeout(10_000) {
                    resolveOn(base = base, title = title, episodeNumber = episodeNumber, dub = dub)
                }
                if (result != null) return result
            } catch (_: Throwable) {
                // Try the next mirror.
            }
        }
        if (dub) {
            for (base in mirrors) {
                try {
                    val result = withTimeout(10_000) {
                        resolveOn(base = base, title = title, episodeNumber = episodeNumber, dub = false)
                    }
                    if (result != null) return result
                } catch (_: Throwable) {
                    // Try the next mirror.
                }
            }
        }
        return null
    }

    private suspend fun resolveOn(
        base: String,
        title: String,
        episodeNumber: Int,
        dub: Boolean,
    ): HianimeStream? {
        val show = findShow(base = base, title = title) ?: return null
        val episodes = fetchEpisodes(base = base, animeId = show.id)
        val episode = episodes.firstOrNull { it.number == episodeNumber } ?: return null
        if (episode.id.isEmpty()) return null
        val servers = fetchServers(base = base, episodeId = episode.id)
        val targetType = if (dub) "dub" else "sub"
        // Prefer Megacloud-backed servers; the others (Streamtape etc.) require
        // separate extractors which we don't ship.
        val preferred = listOf("HD-1", "HD-2", "Vidstreaming", "Vidcloud")
        val ordered = buildList {
            for (name in preferred) {
                addAll(servers.filter { it.type == targetType && it.name == name })
            }
            addAll(servers.filter { it.type == targetType && !preferred.contains(it.name) })
        }
        for (server in ordered) {
            try {
                val embed = fetchSourceLink(base = base, serverId = server.id) ?: continue
                val stream = decryptor.resolve(embed)
                if (stream != null) {
                    return HianimeStream(
                        url = stream.url,
                        referer = stream.referer,
                        subtitleUrl = stream.subtitleUrl,
                        serverName = server.name,
                        mirror = base,
                    )
                }
            } catch (_: Throwable) {
                // Try the next server.
            }
        }
        return null
    }

    private suspend fun findShow(base: String, title: String): HiShow? {
        val url = "$base/search".toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("keyword", title)
            ?.build() ?: return null
        val resp = get(url.toString(), headersFor(base), 8) ?: return null
        if (resp.code >= 400) return null
        val body = resp.body ?: return null
        val doc = Jsoup.parse(body)
        val lower = title.lowercase().trim()
        var best: HiShow? = null
        for (node in doc.select(".flw-item .film-detail .film-name a")) {
            val name = node.text().trim()
            val href = node.attr("href")
            val id = idFromWatchHref(href)
            if (id == null || name.isEmpty()) continue
            val show = HiShow(id = id, name = name)
            // Exact match wins immediately.
            if (name.lowercase() == lower) return show
            if (best == null) best = show
        }
        return best
    }

    private fun idFromWatchHref(href: String): String? {
        // hrefs look like "/watch/attack-on-titan-112" or "/attack-on-titan-112"
        val clean = if (href.startsWith("/watch/")) href.substring(7) else href
        val match = Regex("-(\\d+)$").find(clean)
        return match?.groupValues?.get(1)
    }

    private suspend fun fetchEpisodes(base: String, animeId: String): List<HiEpisode> {
        val resp = get("$base/ajax/v2/episode/list/$animeId", headersFor(base), 8) ?: return emptyList()
        if (resp.code >= 400) return emptyList()
        val json = parseJsonObject(resp.body) ?: return emptyList()
        val html = json.optString("html", "")
        if (html.isEmpty()) return emptyList()
        val doc = Jsoup.parse(html)
        return doc.select(".ep-item").map { node ->
            HiEpisode(
                id = node.attr("data-id"),
                number = node.attr("data-number").toIntOrNull() ?: 0,
            )
        }.filter { it.id.isNotEmpty() && it.number > 0 }
    }

    private suspend fun fetchServers(base: String, episodeId: String): List<HiServer> {
        val url = "$base/ajax/v2/episode/servers".toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("episodeId", episodeId)
            ?.build() ?: return emptyList()
        val resp = get(url.toString(), headersFor(base), 8) ?: return emptyList()
        if (resp.code >= 400) return emptyList()
        val json = parseJsonObject(resp.body) ?: return emptyList()
        val html = json.optString("html", "")
        if (html.isEmpty()) return emptyList()
        val doc = Jsoup.parse(html)
        return doc.select(".server-item").map { node ->
            val anchor = node.selectFirst("a")?.text()?.trim()
            val fallback = node.text().trim().split(Regex("\\s+")).lastOrNull() ?: ""
            HiServer(
                id = node.attr("data-id"),
                name = if (!anchor.isNullOrEmpty()) anchor else fallback,
                type = node.attr("data-type").lowercase().ifEmpty { "sub" },
            )
        }.filter { it.id.isNotEmpty() }
    }

    private suspend fun fetchSourceLink(base: String, serverId: String): String? {
        val url = "$base/ajax/v2/episode/sources".toHttpUrlOrNull()?.newBuilder()
            ?.addQueryParameter("id", serverId)
            ?.build() ?: return null
        val resp = get(url.toString(), headersFor(base), 8) ?: return null
        if (resp.code >= 400) return null
        val json = parseJsonObject(resp.body) ?: return null
        val link = json.optString("link", "")
        if (link.isEmpty()) return null
        return link
    }

    // MARK: - HTTP helper

    private data class HttpResponse(val code: Int, val body: String?)

    private suspend fun get(
        url: String,
        headers: Map<String, String>,
        timeoutSeconds: Long,
    ): HttpResponse? = withContext(Dispatchers.IO) {
        try {
            val scoped = client.newBuilder()
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

    private fun parseJsonObject(body: String?): JSONObject? {
        if (body.isNullOrEmpty()) return null
        return try {
            JSONObject(body)
        } catch (_: Throwable) {
            null
        }
    }
}

/**
 * Resolves a Megacloud embed URL into a direct .m3u8. Megacloud encrypts the
 * sources blob with AES-256-CBC and rotates the key periodically — we fetch
 * the rotating key from a community-maintained endpoint at runtime, falling
 * back to a bundled snapshot if the network fetch fails.
 */
class MegacloudDecryptor(
    private val client: OkHttpClient = OkHttpClient.Builder().build(),
) {

    private var cachedKey: String? = null
    private var cachedKeyAt: Long? = null

    // Snapshot taken at build time. Megacloud rotates this every few weeks;
    // the network endpoint above is the authoritative source. Replace this
    // constant when shipping a build if the network fetch is unreliable.
    private val bundledKeyFallback = "296d28e2f8e319751dafee9d20966fab"

    private val keyEndpoints: List<String> = listOf(
        "https://raw.githubusercontent.com/itzzzme/megacloud-keys/main/key.txt",
        "https://raw.githubusercontent.com/yogesh-hacker/MegacloudKeys/refs/heads/main/keys.json",
    )

    private val userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    suspend fun resolve(embedUrl: String): MegacloudResolved? {
        val uri = embedUrl.toHttpUrlOrNull() ?: return null
        // Embed URLs look like:
        //   https://megacloud.tv/embed-2/e-1/{streamId}?k=1
        //   https://megacloud.blog/embed-1/e-1/{streamId}?k=1
        val segments = uri.pathSegments.filter { it.isNotEmpty() }
        if (segments.size < 3) return null
        val streamId = segments[segments.size - 1]
        val embedKind = segments[segments.size - 2] // "e-1"
        val pathBase = segments[segments.size - 3]   // "embed-1" / "embed-2"

        val sourcesUrl = okhttp3.HttpUrl.Builder()
            .scheme(uri.scheme)
            .host(uri.host)
            .addPathSegment(pathBase)
            .addPathSegment("ajax")
            .addPathSegment(embedKind)
            .addPathSegment("getSources")
            .addQueryParameter("id", streamId)
            .build()

        val headers = mapOf(
            "User-Agent" to userAgent,
            "Referer" to "${uri.scheme}://${uri.host}/",
            "X-Requested-With" to "XMLHttpRequest",
            "Accept" to "application/json",
        )
        val resp = get(sourcesUrl.toString(), headers, 8) ?: return null
        if (resp.code >= 400) return null
        val json = parseJsonObject(resp.body) ?: return null

        // Subtitle track selection: prefer English, otherwise first captions track.
        var subtitleUrl: String? = null
        val tracks = json.optJSONArray("tracks") ?: JSONArray()
        for (i in 0 until tracks.length()) {
            val track = tracks.optJSONObject(i) ?: continue
            val kind = track.optString("kind", "")
            if (kind == "captions" || kind == "subtitles") {
                val lang = track.optString("label", "").lowercase()
                if (subtitleUrl == null || lang.contains("english")) {
                    subtitleUrl = track.optStringOrNull("file")
                }
            }
        }

        var streamUrl: String? = null
        val encrypted = json.optBoolean("encrypted", false)
        val sources = json.opt("sources")
        if (!encrypted && sources is JSONArray && sources.length() > 0) {
            val first = sources.optJSONObject(0)
            if (first != null) streamUrl = first.optStringOrNull("file")
        } else if (encrypted && sources is String && sources.isNotEmpty()) {
            streamUrl = decryptSources(sources)
        }
        if (streamUrl.isNullOrEmpty()) return null
        return MegacloudResolved(
            url = streamUrl,
            referer = "${uri.scheme}://${uri.host}/",
            subtitleUrl = subtitleUrl ?: "",
        )
    }

    private suspend fun decryptSources(encrypted: String): String? {
        val key = fetchKey()
        if (key.isNullOrEmpty()) return null
        return try {
            val decrypted = aesDecrypt(encrypted, key)
            val parsed = JSONArray(decrypted)
            if (parsed.length() > 0) {
                val first = parsed.optJSONObject(0)
                first?.optStringOrNull("file")
            } else {
                null
            }
        } catch (_: Throwable) {
            // Decryption failed — likely the upstream key rotated. Caller falls back
            // to the next server / AllAnime.
            null
        }
    }

    /**
     * Megacloud's AES-256-CBC scheme: the supplied `encrypted` is base64-encoded
     * OpenSSL-format (`Salted__` + 8 salt bytes + ciphertext). Key + IV are
     * derived from the master key + salt via OpenSSL's EVP_BytesToKey (MD5).
     */
    private fun aesDecrypt(encrypted: String, passphrase: String): String {
        val cipherBytes = android.util.Base64.decode(encrypted, android.util.Base64.DEFAULT)
        require(cipherBytes.size >= 16) { "Unexpected Megacloud cipher prefix" }
        val prefix = String(cipherBytes.copyOfRange(0, 8), Charsets.UTF_8)
        require(prefix == "Salted__") { "Unexpected Megacloud cipher prefix" }
        val salt = cipherBytes.copyOfRange(8, 16)
        val ciphertext = cipherBytes.copyOfRange(16, cipherBytes.size)
        val pass = passphrase.toByteArray(Charsets.UTF_8)
        val (key, iv) = opensslKdf(pass, salt, keyLen = 32, ivLen = 16)
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val plaintext = cipher.doFinal(ciphertext)
        return String(plaintext, Charsets.UTF_8)
    }

    /**
     * OpenSSL EVP_BytesToKey with MD5: repeat block = MD5(prev || pass || salt)
     * until enough bytes for key + iv.
     */
    private fun opensslKdf(
        pass: ByteArray,
        salt: ByteArray,
        keyLen: Int,
        ivLen: Int,
    ): Pair<ByteArray, ByteArray> {
        val out = ArrayList<Byte>()
        var prev = ByteArray(0)
        val md5 = MessageDigest.getInstance("MD5")
        while (out.size < keyLen + ivLen) {
            md5.reset()
            md5.update(prev)
            md5.update(pass)
            md5.update(salt)
            val block = md5.digest()
            out.addAll(block.toList())
            prev = block
        }
        val all = out.toByteArray()
        val key = all.copyOfRange(0, keyLen)
        val iv = all.copyOfRange(keyLen, keyLen + ivLen)
        return key to iv
    }

    private suspend fun fetchKey(): String? {
        val now = System.currentTimeMillis()
        val cached = cachedKey
        val at = cachedKeyAt
        if (cached != null && at != null && now - at < 3_600_000L) {
            return cached
        }
        for (endpoint in keyEndpoints) {
            try {
                val resp = get(endpoint, mapOf("User-Agent" to userAgent), 5) ?: continue
                if (resp.code >= 400) continue
                val body = resp.body?.trim() ?: continue
                if (body.isEmpty()) continue
                // Some endpoints return JSON `{ "mega": "...hex..." }`; others return
                // the raw hex string. Handle both.
                var key: String? = null
                if (body.startsWith("{")) {
                    try {
                        val obj = JSONObject(body)
                        key = when {
                            obj.has("mega") -> obj.optString("mega")
                            obj.has("megacloud") -> obj.optString("megacloud")
                            obj.has("key") -> obj.optString("key")
                            else -> null
                        }
                    } catch (_: Throwable) {
                    }
                } else {
                    key = body
                }
                if (!key.isNullOrEmpty()) {
                    cachedKey = key
                    cachedKeyAt = now
                    return key
                }
            } catch (_: Throwable) {
                // Try next endpoint.
            }
        }
        return bundledKeyFallback
    }

    // MARK: - HTTP helper

    private data class HttpResponse(val code: Int, val body: String?)

    private suspend fun get(
        url: String,
        headers: Map<String, String>,
        timeoutSeconds: Long,
    ): HttpResponse? = withContext(Dispatchers.IO) {
        try {
            val scoped = client.newBuilder()
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

    private fun parseJsonObject(body: String?): JSONObject? {
        if (body.isNullOrEmpty()) return null
        return try {
            JSONObject(body)
        } catch (_: Throwable) {
            null
        }
    }
}

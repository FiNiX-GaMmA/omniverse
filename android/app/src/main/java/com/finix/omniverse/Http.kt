package com.finix.omniverse

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import okhttp3.Dns
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/// Shared HTTP client. Every client uses Android's platform trust store and
/// hostname verification; invalid or self-signed certificates are rejected.
object Http {

    /// Small, framework-agnostic response value used across repositories.
    data class Response(
        val status: Int,
        val body: String,
        val headers: Map<String, String> = emptyMap(),
        val finalUrl: String? = null,
    ) {
        val ok: Boolean get() = status < 400
        fun header(name: String): String? =
            headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

        fun jsonObject(): JSONObject = try { JSONObject(body) } catch (_: Throwable) { JSONObject() }
        fun jsonArray(): JSONArray = try { JSONArray(body) } catch (_: Throwable) { JSONArray() }
    }

    sealed class HttpError(message: String) : Exception(message) {
        class Status(val status: Int, val host: String) : HttpError("$host returned $status")
        class Transport(val detail: String) : HttpError(detail)
    }

    private const val JSON_MEDIA = "application/json; charset=utf-8"

    private val loggingInterceptor = Interceptor { chain ->
        val req = chain.request()
        println("[API REQUEST] ${req.method} ${req.url}")
        val resp = chain.proceed(req)
        println("[API RESPONSE] ${resp.code} for ${req.method} ${req.url}")
        resp
    }

    private val bootstrapClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .build()
    }

    class DohDns(private val bootstrap: OkHttpClient) : Dns {
        private val cache = ConcurrentHashMap<String, List<InetAddress>>()

        override fun lookup(hostname: String): List<InetAddress> {
            if (hostname == "localhost" || hostname == "1.1.1.1" || hostname == "8.8.8.8") {
                return Dns.SYSTEM.lookup(hostname)
            }
            cache[hostname]?.let { return it }

            // Try Cloudflare IP-based DoH (IPv4)
            try {
                val ips = resolveDoh("https://1.1.1.1/dns-query?name=$hostname&type=A")
                if (ips.isNotEmpty()) {
                    cache[hostname] = ips
                    return ips
                }
            } catch (_: Throwable) {}

            // Try Google IP-based DoH fallback (IPv4)
            try {
                val ips = resolveDoh("https://8.8.8.8/resolve?name=$hostname&type=A")
                if (ips.isNotEmpty()) {
                    cache[hostname] = ips
                    return ips
                }
            } catch (_: Throwable) {}

            return Dns.SYSTEM.lookup(hostname)
        }

        private fun resolveDoh(url: String): List<InetAddress> {
            val request = Request.Builder()
                .url(url)
                .header("Accept", "application/dns-json")
                .build()
            bootstrap.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: ""
                    val json = JSONObject(body)
                    val answer = json.optJSONArray("Answer")
                    if (answer != null && answer.length() > 0) {
                        val list = ArrayList<InetAddress>()
                        for (i in 0 until answer.length()) {
                            val obj = answer.optJSONObject(i) ?: continue
                            // Type 1 is A record (IPv4)
                            if (obj.optInt("type") == 1) {
                                val ip = obj.optString("data", "")
                                if (ip.isNotEmpty()) {
                                    list.add(InetAddress.getByName(ip))
                                }
                            }
                        }
                        if (list.isNotEmpty()) return list
                    }
                }
            }
            return emptyList()
        }
    }

    val dohDns: Dns by lazy { DohDns(bootstrapClient) }

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(18, TimeUnit.SECONDS)
            .readTimeout(18, TimeUnit.SECONDS)
            .writeTimeout(18, TimeUnit.SECONDS)
            .callTimeout(40, TimeUnit.SECONDS)
            .addInterceptor(loggingInterceptor)
            .dns(dohDns)
            .build()
    }

    /// Media client with no call timeout so long videos are not aborted. TLS
    /// certificates and hostnames are validated by the platform defaults.
    val streamingClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .dns(dohDns)
            .build()
    }

    /// Core request. Runs on Dispatchers.IO. Never throws on non-2xx — returns
    /// the Response with its status; only transport failures throw HttpError.Transport.
    suspend fun request(
        url: String,
        method: String = "GET",
        headers: Map<String, String> = emptyMap(),
        body: RequestBody? = null,
        followRedirects: Boolean = true,
        timeoutMs: Long = 18_000,
    ): Response = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url)
        for ((k, v) in headers) builder.header(k, v)
        // OkHttp requires a body for POST/PUT/etc. unless GET/HEAD.
        val upper = method.uppercase()
        val effectiveBody = body ?: if (upper == "POST" || upper == "PUT" || upper == "PATCH" || upper == "DELETE") {
            ByteArray(0).toRequestBody(null)
        } else null
        builder.method(upper, effectiveBody)

        val perCallClient =
            if (!followRedirects || timeoutMs != 18_000L) {
                client.newBuilder()
                    .followRedirects(followRedirects)
                    .followSslRedirects(followRedirects)
                    .callTimeout(timeoutMs + 22_000, TimeUnit.MILLISECONDS)
                    .build()
            } else client

        try {
            perCallClient.newCall(builder.build()).execute().use { resp ->
                val text = resp.body?.string() ?: ""
                val headerMap = LinkedHashMap<String, String>()
                for (i in 0 until resp.headers.size) {
                    headerMap[resp.headers.name(i)] = resp.headers.value(i)
                }
                Response(
                    status = resp.code,
                    body = text,
                    headers = headerMap,
                    finalUrl = resp.request.url.toString(),
                )
            }
        } catch (t: Throwable) {
            throw HttpError.Transport(t.message ?: t.toString())
        }
    }

    suspend fun getJsonObject(url: String, headers: Map<String, String> = emptyMap(), timeoutMs: Long = 18_000): JSONObject {
        val r = request(url, headers = headers, timeoutMs = timeoutMs)
        if (!r.ok) throw HttpError.Status(r.status, hostOf(url))
        return r.jsonObject()
    }

    suspend fun getJsonArray(url: String, headers: Map<String, String> = emptyMap(), timeoutMs: Long = 18_000): JSONArray {
        val r = request(url, headers = headers, timeoutMs = timeoutMs)
        if (!r.ok) throw HttpError.Status(r.status, hostOf(url))
        return r.jsonArray()
    }

    suspend fun postJson(
        url: String,
        json: JSONObject,
        headers: Map<String, String> = emptyMap(),
        timeoutMs: Long = 18_000,
    ): Response {
        val h = HashMap(headers)
        h["Content-Type"] = JSON_MEDIA
        h["Accept"] = "application/json"
        val body = json.toString().toRequestBody(JSON_MEDIA.toMediaType())
        return request(url, method = "POST", headers = h, body = body, timeoutMs = timeoutMs)
    }

    fun hostOf(url: String): String = try {
        java.net.URI(url).host ?: ""
    } catch (_: Throwable) {
        ""
    }
}

// MARK: - org.json access helpers (mirror the Swift Dictionary extension)

internal fun JSONObject.optStringOrNull(key: String): String? {
    if (!has(key) || isNull(key)) return null
    val v = opt(key) ?: return null
    val s = v.toString()
    return if (s == "null") null else s
}

internal fun JSONObject.optIntOrNull(key: String): Int? {
    if (!has(key) || isNull(key)) return null
    return when (val v = opt(key)) {
        is Int -> v
        is Long -> v.toInt()
        is Double -> v.toInt()
        is Number -> v.toInt()
        is String -> v.toIntOrNull()
        else -> null
    }
}

internal fun JSONObject.optDoubleOrNull(key: String): Double? {
    if (!has(key) || isNull(key)) return null
    return when (val v = opt(key)) {
        is Double -> v
        is Int -> v.toDouble()
        is Long -> v.toDouble()
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }
}

internal fun JSONObject.optLongOrNull(key: String): Long? {
    if (!has(key) || isNull(key)) return null
    return when (val v = opt(key)) {
        is Long -> v
        is Int -> v.toLong()
        is Double -> v.toLong()
        is Number -> v.toLong()
        is String -> v.toLongOrNull()
        else -> null
    }
}

internal fun JSONObject.optObjectOrNull(key: String): JSONObject? =
    if (has(key) && !isNull(key)) optJSONObject(key) else null

internal fun JSONObject.optArrayOrNull(key: String): JSONArray? =
    if (has(key) && !isNull(key)) optJSONArray(key) else null

internal fun JSONObject.strArray(key: String): List<String> {
    val arr = optArrayOrNull(key) ?: return emptyList()
    val out = ArrayList<String>(arr.length())
    for (i in 0 until arr.length()) {
        val v = arr.opt(i)
        if (v is String) out.add(v)
    }
    return out
}

internal fun JSONArray.objects(): List<JSONObject> {
    val out = ArrayList<JSONObject>(length())
    for (i in 0 until length()) {
        (opt(i) as? JSONObject)?.let { out.add(it) }
    }
    return out
}

internal fun JSONArray.intList(): List<Int> {
    val out = ArrayList<Int>(length())
    for (i in 0 until length()) {
        when (val v = opt(i)) {
            is Int -> out.add(v)
            is Long -> out.add(v.toInt())
            is Double -> out.add(v.toInt())
            is Number -> out.add(v.toInt())
        }
    }
    return out
}

internal fun JSONArray.stringList(): List<String> {
    val out = ArrayList<String>(length())
    for (i in 0 until length()) (opt(i) as? String)?.let { out.add(it) }
    return out
}

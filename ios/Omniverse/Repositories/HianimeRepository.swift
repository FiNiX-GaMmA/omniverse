import Foundation
import CryptoKit
import CommonCrypto

// Streams anime from the hianime / aniwatch / Zoro front-end. Four-step flow,
// modelled after the community-maintained `aniwatch-api` and ani-cli's hianime
// fork:
//
//   1. GET `/search?keyword=…`               → list of shows (HTML)
//   2. GET `/ajax/v2/episode/list/{animeId}` → list of episodes (HTML in JSON)
//   3. GET `/ajax/v2/episode/servers?episodeId={epId}` → server tiles
//   4. GET `/ajax/v2/episode/sources?id={serverId}`   → Megacloud embed URL
//
// The Megacloud embed is then decrypted in `MegacloudDecryptor` — that's the
// AES-256-CBC step where keys rotate upstream.
//
// HTML is parsed by regex / string scanning (no SwiftSoup). Faithful port of
// ../lib/src/repositories/hianime_repository.dart.

struct HianimeStream {
    let url: String
    let referer: String
    let subtitleUrl: String
    let serverName: String
    let mirror: String
}

struct MegacloudResolved {
    let url: String
    let referer: String
    let subtitleUrl: String
}

final class HianimeRepository {

    private let decryptor: MegacloudDecryptor

    init(decryptor: MegacloudDecryptor = MegacloudDecryptor()) {
        self.decryptor = decryptor
    }

    /// All mirrors hianime is currently served from. Tried in order until one
    /// returns 2xx for the search call; the winning host is then reused for the
    /// rest of the chain on this resolve call.
    private static let mirrors: [String] = [
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
    ]

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    private func headersFor(_ base: String) -> [String: String] {
        [
            "User-Agent": Self.userAgent,
            "Referer": "\(base)/",
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "text/html,application/xhtml+xml,application/xml,application/json",
        ]
    }

    // MARK: - Internal model types

    private struct HiShow {
        let id: String
        let name: String
    }

    private struct HiEpisode {
        let id: String
        let number: Int
    }

    private struct HiServer {
        let id: String
        let name: String
        let type: String
    }

    /// Top-level entry point. Returns the resolved direct stream + subtitles for
    /// a single episode, or `nil` if no mirror could deliver one.
    func resolve(title: String, episodeNumber: Int, dub: Bool) async -> HianimeStream? {
        for base in Self.mirrors {
            if let result = await resolveOn(base: base, title: title, episodeNumber: episodeNumber, dub: dub) {
                return result
            }
        }
        if dub {
            for base in Self.mirrors {
                if let result = await resolveOn(base: base, title: title, episodeNumber: episodeNumber, dub: false) {
                    return result
                }
            }
        }
        return nil
    }

    private func resolveOn(base: String, title: String, episodeNumber: Int, dub: Bool) async -> HianimeStream? {
        guard let show = await findShow(base: base, title: title) else { return nil }
        let episodes = await fetchEpisodes(base: base, animeId: show.id)
        guard let episode = episodes.first(where: { $0.number == episodeNumber }), !episode.id.isEmpty else {
            return nil
        }
        let servers = await fetchServers(base: base, episodeId: episode.id)
        let targetType = dub ? "dub" : "sub"
        // Prefer Megacloud-backed servers; the others (Streamtape etc.) require
        // separate extractors which we don't ship.
        let preferred = ["HD-1", "HD-2", "Vidstreaming", "Vidcloud"]
        var ordered: [HiServer] = []
        for name in preferred {
            ordered.append(contentsOf: servers.filter { $0.type == targetType && $0.name == name })
        }
        ordered.append(contentsOf: servers.filter { $0.type == targetType && !preferred.contains($0.name) })

        for server in ordered {
            guard let embed = await fetchSourceLink(base: base, serverId: server.id) else { continue }
            if let stream = await decryptor.resolve(embed) {
                return HianimeStream(
                    url: stream.url,
                    referer: stream.referer,
                    subtitleUrl: stream.subtitleUrl,
                    serverName: server.name,
                    mirror: base
                )
            }
        }
        return nil
    }

    private func findShow(base: String, title: String) async -> HiShow? {
        var comps = URLComponents(string: "\(base)/search")
        comps?.queryItems = [URLQueryItem(name: "keyword", value: title)]
        guard let url = comps?.url else { return nil }
        guard let resp = try? await Http.shared.request(url, headers: headersFor(base), timeout: 8), resp.ok else {
            return nil
        }
        let bodyHtml = resp.bodyString
        let lower = title.lowercased().trimmed
        var best: HiShow?
        for anchor in Self.filmNameAnchors(in: bodyHtml) {
            let name = anchor.text.trimmed
            let href = anchor.href
            guard let id = Self.idFromWatchHref(href), !name.isEmpty else { continue }
            let show = HiShow(id: id, name: name)
            // Exact match wins immediately.
            if name.lowercased() == lower { return show }
            if best == nil { best = show }
        }
        return best
    }

    private static func idFromWatchHref(_ href: String) -> String? {
        // hrefs look like "/watch/attack-on-titan-112" or "/attack-on-titan-112"
        let clean = href.hasPrefix("/watch/") ? String(href.dropFirst(7)) : href
        guard let match = clean.range(of: #"-(\d+)$"#, options: .regularExpression) else { return nil }
        // Extract the trailing digits.
        let tail = String(clean[match])
        return String(tail.dropFirst()) // drop leading '-'
    }

    private func fetchEpisodes(base: String, animeId: String) async -> [HiEpisode] {
        guard let url = URL(string: "\(base)/ajax/v2/episode/list/\(animeId)") else { return [] }
        guard let resp = try? await Http.shared.request(url, headers: headersFor(base), timeout: 8), resp.ok else {
            return []
        }
        let json = resp.jsonObject()
        let html = json.str("html") ?? ""
        if html.isEmpty { return [] }
        return Self.epItems(in: html)
            .filter { !$0.id.isEmpty && $0.number > 0 }
    }

    private func fetchServers(base: String, episodeId: String) async -> [HiServer] {
        var comps = URLComponents(string: "\(base)/ajax/v2/episode/servers")
        comps?.queryItems = [URLQueryItem(name: "episodeId", value: episodeId)]
        guard let url = comps?.url else { return [] }
        guard let resp = try? await Http.shared.request(url, headers: headersFor(base), timeout: 8), resp.ok else {
            return []
        }
        let json = resp.jsonObject()
        let html = json.str("html") ?? ""
        if html.isEmpty { return [] }
        return Self.serverItems(in: html).filter { !$0.id.isEmpty }
    }

    private func fetchSourceLink(base: String, serverId: String) async -> String? {
        var comps = URLComponents(string: "\(base)/ajax/v2/episode/sources")
        comps?.queryItems = [URLQueryItem(name: "id", value: serverId)]
        guard let url = comps?.url else { return nil }
        guard let resp = try? await Http.shared.request(url, headers: headersFor(base), timeout: 8), resp.ok else {
            return nil
        }
        let json = resp.jsonObject()
        guard let link = json.str("link"), !link.isEmpty else { return nil }
        return link
    }

    // MARK: - HTML scanning helpers (regex-based, no SwiftSoup)

    private struct Anchor {
        let href: String
        let text: String
    }

    /// Matches `.flw-item .film-detail .film-name a` anchors. The hianime markup
    /// nests these as `<div class="film-name"><a href="…" …>Title</a></div>`.
    /// We scan for film-name blocks and pull the inner anchor href + text.
    private static func filmNameAnchors(in html: String) -> [Anchor] {
        var results: [Anchor] = []
        // Find each `class="film-name"` occurrence, then read the following <a ...>...</a>.
        let ns = html as NSString
        let blockPattern = #"class\s*=\s*["'][^"']*\bfilm-name\b[^"']*["'][^>]*>\s*(<a\b[^>]*>.*?</a>)"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }
        let matches = blockRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges >= 2 {
            let anchorHtml = ns.substring(with: m.range(at: 1))
            if let a = parseAnchor(anchorHtml) {
                results.append(a)
            }
        }
        return results
    }

    private static func parseAnchor(_ anchorHtml: String) -> Anchor? {
        let href = attribute("href", in: anchorHtml) ?? ""
        let text = stripTags(anchorHtml)
        return Anchor(href: href, text: text)
    }

    /// Matches `.ep-item` nodes: pull `data-id` and `data-number`.
    private static func epItems(in html: String) -> [HiEpisode] {
        var results: [HiEpisode] = []
        let ns = html as NSString
        // Each ep-item is an <a ...> (or element) carrying both attributes.
        let pattern = #"<[^>]*\bclass\s*=\s*["'][^"']*\bep-item\b[^"']*["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return results }
        for m in regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            let id = attribute("data-id", in: tag) ?? ""
            let number = Int(attribute("data-number", in: tag) ?? "") ?? 0
            results.append(HiEpisode(id: id, number: number))
        }
        return results
    }

    /// Matches `.server-item` nodes: pull `data-id`, `data-type`, and the inner
    /// anchor text (or trailing word of the element text as a fallback).
    private static func serverItems(in html: String) -> [HiServer] {
        var results: [HiServer] = []
        let ns = html as NSString
        // Capture the opening tag plus the element body up to a closing tag so we
        // can read the inner <a> text.
        let pattern = #"(<[^>]*\bclass\s*=\s*["'][^"']*\bserver-item\b[^"']*["'][^>]*>)(.*?)</"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }
        for m in regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 3 {
            let openTag = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2))
            let id = attribute("data-id", in: openTag) ?? ""
            let type = (attribute("data-type", in: openTag) ?? "sub").lowercased()

            var name: String
            if let anchorText = innerAnchorText(inner), !anchorText.isEmpty {
                name = anchorText
            } else {
                let stripped = stripTags(inner).trimmed
                name = stripped.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).last.map(String.init) ?? ""
            }
            results.append(HiServer(id: id, name: name, type: type))
        }
        return results
    }

    private static func innerAnchorText(_ html: String) -> String? {
        let ns = html as NSString
        guard let regex = try? NSRegularExpression(pattern: #"<a\b[^>]*>(.*?)</a>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else {
            return nil
        }
        return stripTags(ns.substring(with: m.range(at: 1))).trimmed
    }

    /// Reads an attribute value from a single HTML tag string.
    private static func attribute(_ name: String, in tag: String) -> String? {
        let ns = tag as NSString
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let m = regex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        // Single-quoted variant.
        let pattern2 = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*'([^']*)'"
        if let regex = try? NSRegularExpression(pattern: pattern2, options: [.caseInsensitive]),
           let m = regex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return nil
    }

    private static func stripTags(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        return decodeBasicEntities(withoutTags).trimmed
    }

    private static func decodeBasicEntities(_ s: String) -> String {
        var out = s
        let map: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ]
        for (entity, replacement) in map {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}

// MARK: - Megacloud decryptor

/// Resolves a Megacloud embed URL into a direct .m3u8. Megacloud encrypts the
/// sources blob with AES-256-CBC and rotates the key periodically — we fetch
/// the rotating key from a community-maintained endpoint at runtime, falling
/// back to a bundled snapshot if the network fetch fails.
final class MegacloudDecryptor {

    private var cachedKey: String?
    private var cachedKeyAt: Date?

    // Snapshot taken at build time. Megacloud rotates this every few weeks;
    // the network endpoint above is the authoritative source. Replace this
    // constant when shipping a build if the network fetch is unreliable.
    private static let bundledKeyFallback = "296d28e2f8e319751dafee9d20966fab"

    private static let keyEndpoints: [String] = [
        "https://raw.githubusercontent.com/itzzzme/megacloud-keys/main/key.txt",
        "https://raw.githubusercontent.com/yogesh-hacker/MegacloudKeys/refs/heads/main/keys.json",
    ]

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    func resolve(_ embedUrl: String) async -> MegacloudResolved? {
        guard let uri = URL(string: embedUrl), let scheme = uri.scheme, let host = uri.host else { return nil }
        // Embed URLs look like:
        //   https://megacloud.tv/embed-2/e-1/{streamId}?k=1
        //   https://megacloud.blog/embed-1/e-1/{streamId}?k=1
        let segments = uri.pathComponents.filter { $0 != "/" }
        if segments.count < 3 { return nil }
        let streamId = segments[segments.count - 1]
        let embedKind = segments[segments.count - 2] // "e-1"
        let pathBase = segments[segments.count - 3]   // "embed-1" / "embed-2"

        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.path = "/\(pathBase)/ajax/\(embedKind)/getSources"
        comps.queryItems = [URLQueryItem(name: "id", value: streamId)]
        guard let sourcesUri = comps.url else { return nil }

        let headers: [String: String] = [
            "User-Agent": Self.userAgent,
            "Referer": "\(scheme)://\(host)/",
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "application/json",
        ]
        guard let resp = try? await Http.shared.request(sourcesUri, headers: headers, timeout: 8), resp.ok else {
            return nil
        }
        let json = resp.jsonObject()
        if json.isEmpty { return nil }

        // Subtitle track selection: prefer English, otherwise first captions track.
        var subtitleUrl: String?
        let tracks = json.arr("tracks") ?? []
        for case let track as [String: Any] in tracks {
            let kind = track.str("kind") ?? ""
            if kind == "captions" || kind == "subtitles" {
                let lang = (track.str("label") ?? "").lowercased()
                if subtitleUrl == nil || lang.contains("english") {
                    subtitleUrl = track.str("file")
                }
            }
        }

        var streamUrl: String?
        let encrypted = (json["encrypted"] as? Bool) == true
        let sources = json["sources"]
        if !encrypted, let sourceList = sources as? [Any], !sourceList.isEmpty {
            if let first = sourceList.first as? [String: Any] {
                streamUrl = first.str("file")
            }
        } else if encrypted, let sourceStr = sources as? String, !sourceStr.isEmpty {
            streamUrl = await decryptSources(sourceStr)
        }
        guard let url = streamUrl, !url.isEmpty else { return nil }
        return MegacloudResolved(
            url: url,
            referer: "\(scheme)://\(host)/",
            subtitleUrl: subtitleUrl ?? ""
        )
    }

    private func decryptSources(_ encrypted: String) async -> String? {
        guard let key = await fetchKey(), !key.isEmpty else { return nil }
        guard let decrypted = try? aesDecrypt(encrypted, passphrase: key) else { return nil }
        guard let data = decrypted.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let first = parsed.first as? [String: Any] else {
            return nil
        }
        return first.str("file")
    }

    /// Megacloud's AES-256-CBC scheme: the supplied `encrypted` is base64-encoded
    /// OpenSSL-format (`Salted__` + 8 salt bytes + ciphertext). Key + IV are
    /// derived from the master key + salt via OpenSSL's EVP_BytesToKey (MD5).
    private func aesDecrypt(_ encrypted: String, passphrase: String) throws -> String {
        guard let cipherBytes = Data(base64Encoded: encrypted) else {
            throw CryptoError.format("Invalid base64 Megacloud payload")
        }
        let bytes = [UInt8](cipherBytes)
        guard bytes.count >= 16 else {
            throw CryptoError.format("Unexpected Megacloud cipher prefix")
        }
        let prefix = String(decoding: bytes[0..<8], as: UTF8.self)
        guard prefix == "Salted__" else {
            throw CryptoError.format("Unexpected Megacloud cipher prefix")
        }
        let salt = Array(bytes[8..<16])
        let ciphertext = Array(bytes[16...])
        let pass = Array(passphrase.utf8)
        let (key, iv) = opensslKdf(pass: pass, salt: salt, keyLen: 32, ivLen: 16)
        let plaintext = try aesCBCDecryptPKCS7(ciphertext: ciphertext, key: key, iv: iv)
        return String(decoding: plaintext, as: UTF8.self)
    }

    /// OpenSSL EVP_BytesToKey with MD5: repeat block = MD5(prev || pass || salt)
    /// until enough bytes for key + iv.
    private func opensslKdf(pass: [UInt8], salt: [UInt8], keyLen: Int, ivLen: Int) -> (key: [UInt8], iv: [UInt8]) {
        var out: [UInt8] = []
        var prev: [UInt8] = []
        while out.count < keyLen + ivLen {
            var hasher = Insecure.MD5()
            hasher.update(data: Data(prev))
            hasher.update(data: Data(pass))
            hasher.update(data: Data(salt))
            let block = Array(hasher.finalize())
            out.append(contentsOf: block)
            prev = block
        }
        let key = Array(out[0..<keyLen])
        let iv = Array(out[keyLen..<(keyLen + ivLen)])
        return (key, iv)
    }

    private func aesCBCDecryptPKCS7(ciphertext: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        var outLength = 0
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let status = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                ciphertext.withUnsafeBytes { dataPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, key.count,
                        ivPtr.baseAddress,
                        dataPtr.baseAddress, ciphertext.count,
                        &output, output.count,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw CryptoError.decrypt("AES-CBC decrypt failed: \(status)")
        }
        return Array(output[0..<outLength])
    }

    private func fetchKey() async -> String? {
        let now = Date()
        if let key = cachedKey, let at = cachedKeyAt, now.timeIntervalSince(at) < 3600 {
            return key
        }
        for endpoint in Self.keyEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            guard let resp = try? await Http.shared.request(url, headers: ["User-Agent": Self.userAgent], timeout: 5), resp.ok else {
                continue
            }
            let body = resp.bodyString.trimmed
            if body.isEmpty { continue }
            // Some endpoints return JSON `{ "mega": "...hex..." }`; others return
            // the raw hex string. Handle both.
            var key: String?
            if body.hasPrefix("{") {
                if let data = body.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    key = (obj["mega"] ?? obj["megacloud"] ?? obj["key"]).map { "\($0)" }
                }
            } else {
                key = body
            }
            if let k = key, !k.isEmpty {
                cachedKey = k
                cachedKeyAt = now
                return k
            }
        }
        return Self.bundledKeyFallback
    }

    enum CryptoError: Error {
        case format(String)
        case decrypt(String)
    }
}

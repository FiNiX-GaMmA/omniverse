import Foundation

/// Scrapes the Yarrlist directory pages for live-TV / movie links.
/// Ported from yarrlist_repository.dart. HTML <a> anchors are parsed with
/// regex (no external HTML library).
final class YarrlistRepository: YarrlistRepositoryProtocol {

    private static let moviesUrl = URL(string: "https://yarrlist.net/movies-and-tv-shows")!
    private static let liveTvUrl = URL(string: "https://yarrlist.net/live-tv-list")!

    func fetchLiveTvDirectory() async throws -> [LiveTvEntry] {
        let response = try await Http.shared.request(Self.liveTvUrl)
        if response.status >= 400 {
            throw YarrlistError.message("Yarrlist returned \(response.status)")
        }
        return Self.parseDirectory(response.bodyString, Self.liveTvUrl, sourceLabel: "Yarrlist Live TV")
    }

    func fetchMoviesTvDirectory() async throws -> [LiveTvEntry] {
        let response = try await Http.shared.request(Self.moviesUrl)
        if response.status >= 400 {
            throw YarrlistError.message("Yarrlist returned \(response.status)")
        }
        return Self.parseDirectory(response.bodyString, Self.moviesUrl, sourceLabel: "Yarrlist Movies/TV")
    }

    static func parseDirectory(_ html: String, _ baseUrl: URL, sourceLabel: String) -> [LiveTvEntry] {
        var seen = Set<String>()
        var entries: [LiveTvEntry] = []

        for anchor in anchorTags(html) {
            guard let href = anchor.href?.trimmed, !href.isEmpty else { continue }
            let text = anchor.text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmed
            if text.isEmpty { continue }
            let absolute = resolve(baseUrl, href)
            let host = URL(string: absolute)?.host ?? ""
            if isNavigation(text, host) { continue }
            if !seen.insert(absolute).inserted { continue }
            entries.append(LiveTvEntry(title: cleanTitle(text), url: absolute, source: sourceLabel))
        }
        return entries
    }

    // MARK: Anchor scraping

    private struct Anchor { let href: String?; let text: String }

    /// Extract every <a ...>...</a>: the href attribute and inner text (tags stripped).
    private static func anchorTags(_ html: String) -> [Anchor] {
        var anchors: [Anchor] = []
        let pattern = "<a\\b([^>]*)>([\\s\\S]*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return anchors
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges >= 3 {
            let attrs = ns.substring(with: m.range(at: 1))
            let inner = ns.substring(with: m.range(at: 2))
            anchors.append(Anchor(href: hrefAttribute(attrs), text: stripTags(inner)))
        }
        return anchors
    }

    private static func hrefAttribute(_ attrs: String) -> String? {
        if let v = firstMatch(in: attrs, pattern: "href\\s*=\\s*\"([^\"]*)\"") { return v }
        if let v = firstMatch(in: attrs, pattern: "href\\s*=\\s*'([^']*)'") { return v }
        return nil
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func resolve(_ base: URL, _ href: String) -> String {
        if let u = URL(string: href), u.scheme != nil { return u.absoluteString }
        return URL(string: href, relativeTo: base)?.absoluteURL.absoluteString ?? href
    }

    private static func isNavigation(_ text: String, _ host: String) -> Bool {
        let lower = text.lowercased()
        let nav: Set<String> = [
            "backups", "yarrlist", "movies/tv shows", "movies tv shows", "anime",
            "manga", "live sports", "live tv", "torrents", "games", "music",
            "ebooks", "comics", "asian drama", "adult", "adblock", "adblockers",
            "vpn", "reddit",
        ]
        return nav.contains(lower)
            || host == "github.com"
            || host == "yarrlist.net"
            || host == "ahoylist.net"
    }

    private static func cleanTitle(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s*†.*$", with: "", options: .regularExpression).trimmed
    }
}

private enum YarrlistError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}

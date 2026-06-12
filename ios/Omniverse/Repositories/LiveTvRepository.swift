import Foundation

/// Fetches and parses live-TV sources (direct streams or M3U playlists).
/// Ported from live_tv_source_repository.dart (class LiveTvSourceRepository).
final class LiveTvRepository: LiveTvRepositoryProtocol {

    func fetchSource(_ source: LiveTvSource) async throws -> [LiveTvEntry] {
        if !source.enabled { return [] }
        if source.isDirectStream {
            return [LiveTvEntry(title: source.name, url: source.url, source: source.name)]
        }

        guard let uri = URL(string: source.url) else {
            return [LiveTvEntry(title: source.name, url: source.url, source: source.name)]
        }
        let response = try await Http.shared.request(uri)
        if response.status >= 400 {
            throw LiveTvError.message("\(source.name) returned \(response.status)")
        }

        // UTF8 decode (lenient — String(decoding:) never fails, matching allowMalformed).
        let body = String(decoding: response.data, as: UTF8.self)

        if leftTrimmed(body).hasPrefix("#EXTM3U") {
            let parsed = LiveTvRepository.parseM3u(body, baseUrl: uri, sourceLabel: source.name)
            if !parsed.isEmpty { return parsed }
        }

        return [LiveTvEntry(title: source.name, url: source.url, source: source.name)]
    }

    // MARK: M3U parsing

    static func parseM3u(_ content: String, baseUrl: URL, sourceLabel: String) -> [LiveTvEntry] {
        var entries: [LiveTvEntry] = []
        var pendingTitle: String?
        var pendingLogo: String?
        var pendingGroup = ""
        var pendingHeaders: [String: String] = [:]

        let lines = content.components(separatedBy: CharacterSet(charactersIn: "\n"))
            .map { $0.replacingOccurrences(of: "\r", with: "") }

        for rawLine in lines {
            let line = rawLine.trimmed
            if line.isEmpty || line == "#EXTM3U" { continue }

            if line.hasPrefix("#EXTINF") {
                pendingTitle = titleFromExtInf(line)
                pendingLogo = attribute(line, "tvg-logo")
                pendingGroup = attribute(line, "group-title") ?? ""
                pendingHeaders.removeAll()
                if let userAgent = attribute(line, "http-user-agent"), !userAgent.isEmpty {
                    pendingHeaders["User-Agent"] = userAgent
                } else {
                    pendingHeaders["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                }
                if let referrer = attribute(line, "http-referrer"), !referrer.isEmpty {
                    pendingHeaders["Referer"] = referrer
                }
                continue
            }

            if line.hasPrefix("#EXTVLCOPT:") {
                let option = String(line.dropFirst("#EXTVLCOPT:".count))
                guard let eq = option.firstIndex(of: "=") else { continue }
                let name = String(option[..<eq]).trimmed.lowercased()
                let value = String(option[option.index(after: eq)...]).trimmed
                if name == "http-user-agent" && !value.isEmpty {
                    pendingHeaders["User-Agent"] = value
                } else if name == "http-referrer" && !value.isEmpty {
                    pendingHeaders["Referer"] = value
                }
                continue
            }

            if line.hasPrefix("#") { continue }

            let url = resolve(baseUrl, line)
            let resolvedHost = URL(string: url)?.host
            let title = (pendingTitle?.isEmpty == false) ? pendingTitle! : (resolvedHost ?? "Live channel")
            entries.append(LiveTvEntry(
                title: title,
                url: url,
                source: sourceLabel,
                region: pendingGroup,
                logoUrl: pendingLogo,
                headers: pendingHeaders
            ))
            pendingTitle = nil
            pendingLogo = nil
            pendingGroup = ""
            pendingHeaders.removeAll()
        }
        return entries
    }

    private static func titleFromExtInf(_ line: String) -> String {
        guard let comma = line.lastIndex(of: ","), comma != line.index(before: line.endIndex) else {
            return attribute(line, "tvg-name") ?? "Live channel"
        }
        return String(line[line.index(after: comma)...]).trimmed
    }

    private static func attribute(_ line: String, _ name: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1)).trimmed
    }

    /// Mirror Dart `Uri.resolve`: absolute URLs pass through, relative ones
    /// resolve against the base.
    private static func resolve(_ base: URL, _ line: String) -> String {
        if let u = URL(string: line), u.scheme != nil { return u.absoluteString }
        return URL(string: line, relativeTo: base)?.absoluteURL.absoluteString ?? line
    }

    private func leftTrimmed(_ s: String) -> String {
        guard let idx = s.firstIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(s[idx...])
    }
}

private enum LiveTvError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}

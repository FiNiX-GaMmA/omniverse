import Foundation

/// Shared HTTP client. Mirrors the Flutter app's logging + permissive TLS
/// (`badCertificateCallback => true`) so scraper/stream hosts with self-signed
/// or mismatched certs still resolve.
final class Http: NSObject, URLSessionDelegate {
    static let shared = Http()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 18
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate"]
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    struct Response {
        let status: Int
        let data: Data
        var headers: [String: String] = [:]
        var finalURL: URL?
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        var bodyString: String { String(decoding: data, as: UTF8.self) }
        var ok: Bool { status < 400 }
        func json() throws -> Any { try JSONSerialization.jsonObject(with: data) }
        func jsonObject() -> [String: Any] { (try? json()) as? [String: Any] ?? [:] }
        func jsonArray() -> [Any] { (try? json()) as? [Any] ?? [] }
    }

    enum HttpError: Error, CustomStringConvertible {
        case status(Int, host: String)
        case transport(String)
        var description: String {
            switch self {
            case .status(let s, let h): return "\(h) returned \(s)"
            case .transport(let m): return m
            }
        }
    }

    @discardableResult
    func request(_ url: URL,
                 method: String = "GET",
                 headers: [String: String] = [:],
                 body: Data? = nil,
                 timeout: TimeInterval = 18,
                 followRedirects: Bool = true) async throws -> Response {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        print("[API REQUEST] \(method) \(url.absoluteString)")
        do {
            let (data, resp) = try await session.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            var headers: [String: String] = [:]
            if let fields = http?.allHeaderFields {
                for (k, v) in fields { headers["\(k)"] = "\(v)" }
            }
            print("[API RESPONSE] \(status) for \(method) \(url.absoluteString)")
            return Response(status: status, data: data, headers: headers, finalURL: http?.url)
        } catch {
            throw HttpError.transport(error.localizedDescription)
        }
    }

    // Convenience: GET JSON object.
    func getJSONObject(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 18) async throws -> [String: Any] {
        let r = try await request(url, headers: headers, timeout: timeout)
        guard r.ok else { throw HttpError.status(r.status, host: url.host ?? "") }
        return r.jsonObject()
    }
    func getJSONArray(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 18) async throws -> [Any] {
        let r = try await request(url, headers: headers, timeout: timeout)
        guard r.ok else { throw HttpError.status(r.status, host: url.host ?? "") }
        return r.jsonArray()
    }
    func postJSON(_ url: URL, json: [String: Any], headers: [String: String] = [:], timeout: TimeInterval = 18) async throws -> Response {
        var h = headers
        h["Content-Type"] = "application/json"
        h["Accept"] = "application/json"
        let body = try JSONSerialization.data(withJSONObject: json)
        return try await request(url, method: "POST", headers: h, body: body, timeout: timeout)
    }

    // Trust self-signed / mismatched certs (parity with the Flutter override).
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - JSON access helpers

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String) -> Int? {
        if let n = self[k] as? Int { return n }
        if let n = self[k] as? Double { return Int(n) }
        if let s = self[k] as? String { return Int(s) }
        return nil
    }
    func dbl(_ k: String) -> Double? {
        if let n = self[k] as? Double { return n }
        if let n = self[k] as? Int { return Double(n) }
        if let s = self[k] as? String { return Double(s) }
        return nil
    }
    func obj(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }
    func arr(_ k: String) -> [Any]? { self[k] as? [Any] }
    func strArray(_ k: String) -> [String] { (self[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
}

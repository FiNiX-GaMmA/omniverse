import Foundation
import Security

// MARK: - Keychain-backed credentials store (mirrors CredentialsStore)

struct CredentialsStore {
    private let service = "com.aryaroop.omniverse.credentials"

    private enum K {
        static let tmdbToken = "tmdb_token"
        static let tvdbKey = "tvdb_api_key"
        static let tvdbPin = "tvdb_pin"
        static let traktClientId = "trakt_client_id"
        static let traktClientSecret = "trakt_client_secret"
        static let traktAccessToken = "trakt_access_token"
        static let traktRefreshToken = "trakt_refresh_token"
        static let traktTokenExpiresAt = "trakt_token_expires_at"
        static let traktUsername = "trakt_username"
        static let pixeldrainApiKey = "pixeldrain_api_key"
        static let anilistAccessToken = "anilist_access_token"
    }

    func load() -> ApiCredentials {
        var c = ApiCredentials()
        c.tmdbToken = read(K.tmdbToken) ?? ""
        c.tvdbApiKey = read(K.tvdbKey) ?? ""
        c.tvdbPin = read(K.tvdbPin) ?? ""
        c.traktClientId = read(K.traktClientId) ?? ""
        c.traktClientSecret = read(K.traktClientSecret) ?? ""
        c.traktAccessToken = read(K.traktAccessToken) ?? ""
        c.traktRefreshToken = read(K.traktRefreshToken) ?? ""
        c.traktTokenExpiresAt = Int(read(K.traktTokenExpiresAt) ?? "") ?? 0
        c.traktUsername = read(K.traktUsername) ?? ""
        c.pixeldrainApiKey = read(K.pixeldrainApiKey) ?? ""
        c.anilistAccessToken = read(K.anilistAccessToken) ?? ""
        return c
    }

    func save(_ c: ApiCredentials) {
        write(K.tmdbToken, c.tmdbToken.trimmed)
        write(K.tvdbKey, c.tvdbApiKey.trimmed)
        write(K.tvdbPin, c.tvdbPin.trimmed)
        write(K.traktClientId, c.traktClientId.trimmed)
        write(K.traktClientSecret, c.traktClientSecret.trimmed)
        write(K.traktAccessToken, c.traktAccessToken.trimmed)
        write(K.traktRefreshToken, c.traktRefreshToken.trimmed)
        write(K.traktTokenExpiresAt, String(c.traktTokenExpiresAt))
        write(K.traktUsername, c.traktUsername.trimmed)
        write(K.pixeldrainApiKey, c.pixeldrainApiKey.trimmed)
        write(K.anilistAccessToken, c.anilistAccessToken.trimmed)
    }

    private func read(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ key: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - UserDefaults-backed settings/cache store (mirrors UserSettingsStore)

struct UserSettingsStore {
    private let d = UserDefaults.standard
    private enum K {
        static let settings = "settings"
        static let liveTvSources = "live_tv_sources"
        static let cachedCategories = "cached_categories"
        static let cachedLiveTv = "cached_live_tv"
        static let watchlist = "watchlist"
        static let watchHistory = "watch_history_v1"
    }

    func loadSettings() -> UserSettings {
        guard let data = d.data(forKey: K.settings),
              let s = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return UserSettings()
        }
        return s
    }
    func saveSettings(_ s: UserSettings) { d.set(try? JSONEncoder().encode(s), forKey: K.settings) }

    func loadLiveTvSources() -> [LiveTvSource] { decodeArray(K.liveTvSources) }
    func saveLiveTvSources(_ v: [LiveTvSource]) { encodeArray(v, K.liveTvSources) }

    func loadCachedCategories() -> [MediaCategory] { decodeArray(K.cachedCategories) }
    func saveCachedCategories(_ v: [MediaCategory]) { encodeArray(v, K.cachedCategories) }

    func loadCachedLiveTv() -> [LiveTvEntry] { decodeArray(K.cachedLiveTv) }
    func saveCachedLiveTv(_ v: [LiveTvEntry]) { encodeArray(v, K.cachedLiveTv) }

    func loadWatchlist() -> Set<String> { Set(d.stringArray(forKey: K.watchlist) ?? []) }
    func saveWatchlist(_ v: Set<String>) { d.set(v.sorted(), forKey: K.watchlist) }

    func loadWatchHistory() -> [WatchProgress] { decodeArray(K.watchHistory) }
    func saveWatchHistory(_ v: [WatchProgress]) { encodeArray(v, K.watchHistory) }

    func lastRefreshedTime() -> Int { d.integer(forKey: "last_refreshed_time") }
    func setLastRefreshedTime(_ ms: Int) { d.set(ms, forKey: "last_refreshed_time") }

    private func decodeArray<T: Decodable>(_ key: String) -> [T] {
        guard let data = d.data(forKey: key),
              let v = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return v
    }
    private func encodeArray<T: Encodable>(_ v: [T], _ key: String) {
        d.set(try? JSONEncoder().encode(v), forKey: key)
    }
}

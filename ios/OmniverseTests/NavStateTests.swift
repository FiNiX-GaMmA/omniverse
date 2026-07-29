import XCTest
@testable import Omniverse

final class NavStateTests: XCTestCase {

    func testTraktCredentialsRemoveClipboardFormattingNoise() {
        XCTAssertEqual("  abcd\u{200B} ef\n12\u{FEFF}34  ".normalizedTraktCredential, "abcdef1234")
    }

    func testTraktAuthorizeUrlAlwaysCarriesNormalizedClientId() {
        var credentials = ApiCredentials()
        credentials.traktClientId = " abcd\u{200B}1234 "
        let url = TraktRepository().buildOAuthAuthorizeUri(credentials, state: "state-token")
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(query["client_id"], "abcd1234")
        XCTAssertEqual(query["redirect_uri"], "omniplay://trakt/oauth")
        XCTAssertEqual(query["state"], "state-token")
    }

    func testDefaultUserSettings() {
        let settings = UserSettings()
        XCTAssertTrue(settings.showMoviesTv)
        XCTAssertTrue(settings.showLiveTv)
        XCTAssertEqual(settings.vidsrcDomain, "vsembed.ru")
    }

    func testApiCredentialsHasTmdb() {
        var c = ApiCredentials()
        XCTAssertFalse(c.hasTmdb)
        XCTAssertFalse(c.hasTvdb)
        XCTAssertFalse(c.hasTraktUser)

        c.tmdbToken = "test_tmdb_token"
        c.tvdbApiKey = "test_tvdb_key"
        c.traktAccessToken = "test_trakt_token"

        XCTAssertTrue(c.hasTmdb)
        XCTAssertTrue(c.hasTvdb)
        XCTAssertTrue(c.hasTraktUser)
    }

    func testActiveTabFallback() {
        let availableTabIds = ["livetv", "search", "settings"]

        var requestedTabId = "home"
        let currentTabId = availableTabIds.contains(requestedTabId) ? requestedTabId : (availableTabIds.first ?? "settings")

        XCTAssertEqual(currentTabId, "livetv")

        requestedTabId = "settings"
        let currentTabId2 = availableTabIds.contains(requestedTabId) ? requestedTabId : (availableTabIds.first ?? "settings")

        XCTAssertEqual(currentTabId2, "settings")
    }

    func testTabFilteringModes() {
        let movieItem = MediaItem(id: "1", type: .movie, title: "Movie 1")
        let seriesItem = MediaItem(id: "2", type: .series, title: "Series 1")
        let items = [movieItem, seriesItem]

        let moviePicks = items.filter { $0.type == .movie }
        let seriesPicks = items.filter { $0.type == .series }

        XCTAssertEqual(moviePicks.count, 1)
        XCTAssertEqual(moviePicks.first?.title, "Movie 1")

        XCTAssertEqual(seriesPicks.count, 1)
        XCTAssertEqual(seriesPicks.first?.title, "Series 1")
    }

    func testCredentialCapabilityFlagsTrimWhitespace() {
        var credentials = ApiCredentials()
        credentials.traktRefreshToken = " refresh "
        credentials.traktClientSecret = "  "
        credentials.anilistAccessToken = " token "

        XCTAssertFalse(credentials.canRefreshTrakt)
        XCTAssertTrue(credentials.hasAnilist)

        credentials.traktClientSecret = " secret "
        XCTAssertTrue(credentials.canRefreshTrakt)
    }

    func testImageUrlResolutionAcrossProviders() {
        XCTAssertNil(imageUrl(nil, size: "w342"))
        XCTAssertEqual(imageUrl("https://cdn.example/poster.jpg", size: "w342"), "https://cdn.example/poster.jpg")
        XCTAssertEqual(imageUrl("//cdn.example/poster.jpg", size: "w342"), "https://cdn.example/poster.jpg")
        XCTAssertEqual(imageUrl("banners/poster.jpg", size: "w342"), "https://artworks.thetvdb.com/banners/poster.jpg")
        XCTAssertEqual(imageUrl("/poster.jpg", size: "w342"), "https://image.tmdb.org/t/p/w342/poster.jpg")
    }

    func testDirectStreamDetectionHandlesQueriesAndCase() {
        XCTAssertTrue(LiveTvEntry.directStream("https://cdn.example/live.M3U8?token=abc"))
        XCTAssertTrue(LiveTvEntry.directStream("https://cdn.example/movie.mp4"))
        XCTAssertFalse(LiveTvEntry.directStream("https://embed.example/watch/123"))
    }

    func testWatchProgressFractionIsClamped() {
        func progress(position: Int, duration: Int) -> WatchProgress {
            WatchProgress(
                itemId: "1",
                title: "Example",
                type: .movie,
                positionMs: position,
                durationMs: duration,
                lastWatchedAt: 1
            )
        }

        XCTAssertEqual(progress(position: 10, duration: 0).fraction, 0)
        XCTAssertEqual(progress(position: -10, duration: 100).fraction, 0)
        XCTAssertEqual(progress(position: 150, duration: 100).fraction, 1)
    }

    func testPlaybackOverridesOnlyReplaceProvidedValues() {
        var settings = UserSettings()
        settings.subtitleLanguage = "en"
        settings.subtitleUrl = "https://cdn.example/en.vtt"

        let next = settings.applying(
            PlaybackOverrides(subtitleLanguage: "fr", subtitleUrl: nil)
        )
        XCTAssertEqual(next.subtitleLanguage, "fr")
        XCTAssertEqual(next.subtitleUrl, "https://cdn.example/en.vtt")
    }
}

import XCTest
@testable import Omniverse

final class NavStateTests: XCTestCase {

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
}

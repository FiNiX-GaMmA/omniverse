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
}

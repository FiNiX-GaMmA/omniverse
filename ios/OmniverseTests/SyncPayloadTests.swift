import XCTest
@testable import Omniverse

final class SyncPayloadTests: XCTestCase {

    func testPrefix() {
        XCTAssertEqual(SyncPayload.prefix, "OMNIVERSE-SYNC1:")
    }

    func testBuildAndParse() {
        var c = ApiCredentials()
        c.traktAccessToken = "ios_test_token"
        c.traktUsername = "ios_test_user"

        let settings = UserSettings()

        let syncStr = SyncPayload.buildSyncString(credentials: c, settings: settings)
        XCTAssertTrue(syncStr.hasPrefix(SyncPayload.prefix))

        guard let parsed = SyncPayload.parseSyncString(syncStr) else {
            XCTFail("Failed to parse built sync string")
            return
        }

        XCTAssertEqual(parsed.credentials.traktAccessToken, "ios_test_token")
        XCTAssertEqual(parsed.credentials.traktUsername, "ios_test_user")
    }

    func testBuildTrimsValuesAndOmitsBlankOrLargeFields() throws {
        var credentials = ApiCredentials()
        credentials.traktAccessToken = "  access-token  "
        credentials.traktUsername = "   "
        credentials.anilistAccessToken = "large-anilist-token"

        let syncString = SyncPayload.buildSyncString(credentials: credentials, settings: UserSettings())
        let encoded = String(syncString.dropFirst(SyncPayload.prefix.count))
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["v"] as? Int, 1)
        XCTAssertEqual(json["trakt_access_token"] as? String, "access-token")
        XCTAssertNil(json["trakt_username"])
        XCTAssertNil(json["anilist_access_token"])
        XCTAssertNil(json["settings"])
    }

    func testParserRejectsMalformedOrNonObjectPayloads() throws {
        XCTAssertNil(SyncPayload.parseSyncString("wrong-prefix"))
        XCTAssertNil(SyncPayload.parseSyncString(SyncPayload.prefix))
        XCTAssertNil(SyncPayload.parseSyncString(SyncPayload.prefix + "!!!not-base64!!!"))

        let arrayPayload = try JSONSerialization.data(withJSONObject: ["not", "an", "object"])
        XCTAssertNil(
            SyncPayload.parseSyncString(
                SyncPayload.prefix + arrayPayload.base64EncodedString()
            )
        )
    }

    func testParserAcceptsWhitespaceAndLegacySettingsObject() throws {
        var settings = UserSettings()
        settings.language = "fr-FR"
        settings.region = "FR"
        let settingsData = try JSONEncoder().encode(settings)
        let settingsJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        )
        let payload: [String: Any] = [
            "v": 1,
            "tmdb_token": "tmdb-token",
            "settings": settingsJSON,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let syncString = " \n\(SyncPayload.prefix)\(data.base64EncodedString())\t "

        let parsed = try XCTUnwrap(SyncPayload.parseSyncString(syncString))
        XCTAssertEqual(parsed.credentials.tmdbToken, "tmdb-token")
        XCTAssertEqual(parsed.settings?.language, "fr-FR")
        XCTAssertEqual(parsed.settings?.region, "FR")
    }
}

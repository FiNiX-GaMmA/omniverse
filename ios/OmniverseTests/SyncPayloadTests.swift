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
}

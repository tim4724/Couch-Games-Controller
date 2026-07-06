import XCTest

/// Smoke test + store-screenshot capture in one pass: walks home → game info sheet →
/// profile sheet → manual code entry → About, asserting each screen's key content
/// (manifest load, live/soon status, code gating, version label) and attaching a
/// full-screen PNG per stop to the result bundle.
///
/// CI extracts the PNGs with `xcrun xcresulttool export attachments`. The flow
/// deliberately avoids the QR scanner (no camera in the simulator) and never submits
/// a room code — nothing here depends on a live relay, so the test also runs offline.
final class StoreScreenshotTests: XCTestCase {

    private let playerName = "Alex"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStoreFlow() throws {
        let app = XCUIApplication()
        // First launch mints a random FunnyName — the NSArgumentDomain override pins
        // ProfileStore's UserDefaults key so assertions and screenshots are
        // deterministic. English is forced for the same reason.
        app.launchArguments += [
            "-cg_profile.name", playerName,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        // ---- Home: catalog, live status, join card, profile chip ----
        XCTAssertTrue(app.staticTexts["HexStacker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tiny Track"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Powder"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Live"].firstMatch.exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Coming soon").count, 2)
        XCTAssertTrue(app.staticTexts["Play"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Scan code"].firstMatch.exists)
        XCTAssertTrue(app.buttons[playerName].firstMatch.exists)
        snap("01-home")

        // ---- Game info sheet: manifest copy + join actions for the live game ----
        app.staticTexts["HexStacker"].firstMatch.tap()
        let players = app.staticTexts["1–8 players"]
        XCTAssertTrue(players.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scan the room code it shows to play."].exists)
        // Give the muted gameplay trailer a moment to render real frames.
        Thread.sleep(forTimeInterval: 2)
        snap("02-game-info")
        // Tap the dimmed area above the content-height sheet to dismiss it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(players.waitForNonExistence(timeout: 5))

        // ---- Profile sheet: seeded name round-trips through the field ----
        app.buttons[playerName].firstMatch.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, playerName)
        snap("03-profile")
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[playerName].firstMatch.exists)

        // ---- Manual code entry: empty-code gating; never submitted (no relay dependency) ----
        app.buttons["Enter code manually"].firstMatch.tap()
        let alert = app.alerts["Enter room code"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(alert.buttons["Play"].isEnabled)
        let codeField = alert.textFields.firstMatch
        codeField.tap()
        codeField.typeText("A3KX9p")
        XCTAssertTrue(alert.buttons["Play"].isEnabled)
        snap("04-enter-code")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        // ---- About: legal hub reachable, version label present ----
        app.buttons["About"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Privacy Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Impressum"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.0.0"].exists)
        snap("05-about")
    }

    /// Full-screen capture attached to the result bundle; extract with
    /// `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

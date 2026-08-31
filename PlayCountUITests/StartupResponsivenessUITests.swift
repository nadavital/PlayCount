import XCTest

final class StartupResponsivenessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCachedLibraryCanOpenDetailsDuringSlowRefresh() throws {
        let app = launch(cached: true)
        let song = app.buttons.matching(NSPredicate(format: "label CONTAINS 'First Light'")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(song.label.hasSuffix(", 99"), "The saved snapshot must be visible before the live scan finishes")
        capture(app, "Cached library before detail")
        song.tap()
        XCTAssertTrue(app.buttons["Play Song"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["First Light"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["99"].exists)
        capture(app, "Cached song detail")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testCachedLibraryCanScrollDuringSlowRefresh() throws {
        let app = launch(cached: true)
        let song = app.buttons.matching(NSPredicate(format: "label CONTAINS 'First Light'")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(song.label.hasSuffix(", 99"))
        capture(app, "Cached library before scroll")
        app.swipeUp()
        capture(app, "Cached library after scroll")
        let scrolledSong = try XCTUnwrap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Track '")
        ).allElementsBoundByIndex.first(where: \.isHittable))
        let labelParts = scrolledSong.label.components(separatedBy: ", ")
        let rank = try XCTUnwrap(Int(try XCTUnwrap(labelParts.first)))
        XCTAssertGreaterThan(rank, 1, "Scrolling should reveal lower-ranked songs")
        XCTAssertEqual(labelParts.last, String(100 - rank), "Scrolling must complete while the saved snapshot is still shown")
        XCTAssertTrue(app.tabBars.buttons["Recap"].isHittable)
        XCTAssertFalse(app.staticTexts["First Light"].isHittable)
    }

    func testCachedStartupCanSwitchTabsAndPreservesLiveRefresh() throws {
        let app = launch(cached: true)
        let song = app.buttons.matching(NSPredicate(format: "label CONTAINS 'First Light'")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(song.label.hasSuffix(", 99"))
        capture(app, "Cached library before tab switch")
        app.tabBars.buttons["Recap"].tap()
        XCTAssertTrue(app.tabBars.buttons["Recap"].isSelected)
        capture(app, "Cached startup recap tab")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(song.label.hasSuffix(", 99"), "Both tab switches must complete before the delayed live scan")
        capture(app, "Cached library after round-trip tab switch")
        let liveRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'First Light' AND label ENDSWITH ', 100'")
        ).firstMatch
        XCTAssertTrue(liveRow.waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "Live refresh after cached tab switch")
    }

    func testUncachedStartupCanSwitchTabsAndEventuallyShowsLibrary() throws {
        let app = launch(cached: false)
        let recap = app.tabBars.buttons["Recap"]
        XCTAssertTrue(recap.waitForExistence(timeout: 3), app.debugDescription)
        capture(app, "Uncached initial loading")
        recap.tap()
        XCTAssertTrue(recap.isSelected)
        capture(app, "Uncached recap during library read")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["First Light"].waitForExistence(timeout: 15), app.debugDescription)
        capture(app, "Uncached live library ready")
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func launch(cached: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PlayCountStartupVerification"]
        if cached { app.launchArguments.append("-PlayCountStartupCached") }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

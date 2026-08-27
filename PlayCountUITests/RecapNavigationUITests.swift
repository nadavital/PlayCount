import XCTest

final class RecapNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testYearAndMonthNavigationRemainsReachableAndUpdatesSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PlayCountScreenshotMode",
            "-PlayCountScreenshotTab", "recap"
        ]
        app.launch()

        let year = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH 'year recap'")
        ).firstMatch
        if !year.waitForExistence(timeout: 8) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Recap launch state"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("The year recap control was missing. Hierarchy: \(app.debugDescription)")
            return
        }

        let july = app.buttons["July 2026"]
        XCTAssertTrue(july.waitForExistence(timeout: 3))
        waitForAnimationsToSettle()
        let yearFrame = year.frame
        let julyFrame = july.frame
        july.tap()
        waitForSelection(of: july)
        assertFrame(july.frame, remainsAt: julyFrame, name: "July")
        assertFrame(year.frame, remainsAt: yearFrame, name: "Year")
        attach(app, named: "July selected")
        XCTAssertTrue(year.isHittable, "The pinned year control must remain reachable after choosing a month")

        let june = app.buttons["June 2026"]
        XCTAssertTrue(june.waitForExistence(timeout: 3))
        let juneFrame = june.frame
        june.tap()
        waitForSelection(of: june)
        assertFrame(june.frame, remainsAt: juneFrame, name: "June")
        assertFrame(year.frame, remainsAt: yearFrame, name: "Year")
        attach(app, named: "June selected")
        XCTAssertTrue(year.isHittable)

        year.tap()
        waitForSelection(of: year)
        attach(app, named: "Year overview")

        let sectionPicker = app.segmentedControls["yearly-recap-section"]
        XCTAssertTrue(sectionPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(sectionPicker.buttons["Overview"].isSelected)

        sectionPicker.buttons["Trends"].tap()
        waitForSelection(of: sectionPicker.buttons["Trends"])
        XCTAssertTrue(app.segmentedControls["yearly-trend-metric"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Top Songs"].exists)
        attach(app, named: "Year trends")

        sectionPicker.buttons["Months"].tap()
        waitForSelection(of: sectionPicker.buttons["Months"])
        XCTAssertTrue(app.staticTexts["Top Songs by Month"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.segmentedControls["yearly-trend-metric"].exists)
        attach(app, named: "Year by month")

        let august = app.buttons["August 2026"]
        XCTAssertTrue(august.waitForExistence(timeout: 3))
        let augustFrame = august.frame
        august.tap()
        waitForSelection(of: august)
        assertFrame(august.frame, remainsAt: augustFrame, name: "August")
        assertFrame(year.frame, remainsAt: yearFrame, name: "Year")
        XCTAssertFalse(sectionPicker.exists)
        XCTAssertTrue(year.isHittable)
        attach(app, named: "August selected")

        year.tap()
        waitForSelection(of: year)
        XCTAssertTrue(sectionPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(sectionPicker.buttons["Overview"].isSelected)
    }

    func testLoadingStatesUseBrandedContextualPresentation() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PlayCountScreenshotMode",
            "-PlayCountScreenshotLoadingState",
            "-PlayCountScreenshotTab", "recap"
        ]
        app.launch()

        let recapLoader = app.otherElements["recap-loading-shell"]
        XCTAssertTrue(recapLoader.waitForExistence(timeout: 8))
        XCTAssertTrue(recapLoader.label.contains("Loading library"))
        attach(app, named: "Recap stable loading shell")

        app.terminate()
        app.launchArguments = [
            "-PlayCountScreenshotMode",
            "-PlayCountScreenshotLoadingState",
            "-PlayCountScreenshotTab", "library"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Loading library…"].waitForExistence(timeout: 8))
        attach(app, named: "Library branded loading state")
    }

    func testRecapDiagnosticsExposeAggregateIntegrityWithoutMediaNames() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PlayCountScreenshotMode",
            "-PlayCountScreenshotTab", "search"
        ]
        app.launch()

        let integrations = app.buttons["Siri & Shortcuts"]
        XCTAssertTrue(integrations.waitForExistence(timeout: 8))
        integrations.tap()

        let diagnostics = app.buttons["Recap Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        diagnostics.tap()

        XCTAssertTrue(app.staticTexts["Month ledger"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Yearly totals"].exists)
        XCTAssertTrue(app.staticTexts["Reliability policy"].exists)
        XCTAssertFalse(app.staticTexts["Glass Rain"].exists)
        XCTAssertFalse(app.staticTexts["The Meridian"].exists)
        attach(app, named: "Recap diagnostics integrity")

        app.swipeUp()
        let shareReport = app.buttons["Share Diagnostic Report"]
        XCTAssertTrue(shareReport.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Glass Rain"].exists)
        XCTAssertFalse(app.staticTexts["The Meridian"].exists)
        attach(app, named: "Privacy-safe recap diagnostics export")
    }

    private func waitForSelection(of element: XCUIElement, timeout: TimeInterval = 3) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: timeout), .completed)
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForAnimationsToSettle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    }

    private func assertFrame(
        _ actual: CGRect,
        remainsAt expected: CGRect,
        name: String,
        accuracy: CGFloat = 1
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, "\(name) moved horizontally")
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, "\(name) moved vertically")
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, "\(name) changed width")
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, "\(name) changed height")
    }
}

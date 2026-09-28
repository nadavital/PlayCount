import XCTest

final class RecapNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSearchSelectionUpdatesDetailAndPreservesQuery() throws {
        verifySearchSelection(domain: "all")
    }

    func testScopedSongSearchUsesAdaptiveDetailAndPreservesQuery() throws {
        verifySearchSelection(domain: "songs")
    }

    func testRecapSeeAllSongsOpensDetailAndReturns() {
        let app = XCUIApplication()
        app.launchArguments = ["-PlayCountScreenshotMode", "-PlayCountScreenshotTab", "recap"]
        app.launch()
        let seeAll = app.buttons["See All"].firstMatch
        for _ in 0..<5 {
            if seeAll.exists && seeAll.isHittable && seeAll.frame.maxY < app.windows.firstMatch.frame.maxY - 150 { break }
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(seeAll.isHittable, app.debugDescription)
        seeAll.tap()
        XCTAssertTrue(app.navigationBars["Top Songs"].waitForExistence(timeout: 8), app.debugDescription)
        let song = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Glass Rain, ")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 8), app.debugDescription)
        attach(app, named: "Recap See All songs")
        song.tap()
        XCTAssertTrue(app.scrollViews.staticTexts["Glass Rain"].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        attach(app, named: "Recap ranked song detail")
        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3), app.debugDescription)
        back.tap()
        XCTAssertTrue(app.navigationBars["Top Songs"].waitForExistence(timeout: 8), app.debugDescription)
        attach(app, named: "Recap See All restored")
    }

    func testRelatedSongsFitInsideSearchDetailColumn() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PlayCountScreenshotMode", "-PlayCountScreenshotTab", "search",
            "-PlayCountScreenshotSearchQuery", "a", "-PlayCountScreenshotSearchDomain", "songs",
            "-PlayCountScreenshotSearchSelection", "-PlayCountScreenshotSongRelated"
        ]
        app.launch()
        let detail = app.scrollViews["song-detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        let albumHeading = detail.staticTexts["On This Album"].firstMatch
        XCTAssertTrue(albumHeading.waitForExistence(timeout: 8))
        let artistHeading = detail.staticTexts["More by Nova Lane"].firstMatch
        XCTAssertTrue(artistHeading.waitForExistence(timeout: 8))
        for heading in [albumHeading, artistHeading] {
            XCTAssertGreaterThanOrEqual(heading.frame.minX, detail.frame.minX)
            XCTAssertLessThanOrEqual(heading.frame.maxX, detail.frame.maxX)
        }
        if detail.frame.width < 656 {
            XCTAssertGreaterThan(artistHeading.frame.minY, albumHeading.frame.maxY,
                                 "Narrow details must stack related sections")
        }
        attach(app, named: "Related songs contained within detail")
    }

    private func verifySearchSelection(domain: String) {
        let app = XCUIApplication()
        let query = "a"
        app.launchArguments = [
            "-PlayCountScreenshotMode",
            "-PlayCountScreenshotTab", "search",
            "-PlayCountScreenshotSearchQuery", query,
            "-PlayCountScreenshotSearchDomain", domain
        ]
        app.launch()

        let firstResult = searchResult("Afterglow Drive", in: app)
        guard requireSearchElement(firstResult, in: app, named: "First \(domain) result") else { return }
        for title in ["Afterglow Drive", "Afterglow Drive", "City Lights"] {
            let result = searchResult(title, in: app)
            guard requireSearchElement(result, in: app, named: "\(domain) result \(title)") else { return }
            XCTAssertTrue(result.isHittable, "Search result must remain reachable. \(app.debugDescription)")
            result.tap()

            guard requireSearchElement(app.scrollViews.staticTexts[title].firstMatch, in: app, named: "\(title) detail heading") else { return }
            let back = app.buttons["search-back"].firstMatch
            if back.exists {
                attach(app, named: "\(domain) compact detail \(title)")
                back.tap()
                guard requireSearchElement(searchResult(title, in: app), in: app, named: "Restored \(title) result") else { return }
            } else {
                XCTAssertTrue(searchResult("Afterglow Drive", in: app).isHittable,
                              "The results column must remain usable alongside detail")
                let field = app.searchFields.firstMatch
                guard requireSearchElement(field, in: app, named: "Column search field") else { return }
                XCTAssertLessThan(field.frame.width, app.windows.firstMatch.frame.width * 0.65,
                                  "The search field must stay in the results column")
                attach(app, named: "\(domain) split detail \(title)")
            }

            let searchField = app.searchFields.firstMatch
            guard requireSearchElement(searchField, in: app, named: "Preserved search field") else { return }
            XCTAssertEqual(searchField.value as? String, query,
                           "Selecting or returning from a result must preserve the query")
        }
        attach(app, named: "\(domain) search query preserved after repeated selections")
    }

    private func searchResult(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + ", ")).firstMatch
    }

    private func requireSearchElement(_ element: XCUIElement, in app: XCUIApplication, named name: String) -> Bool {
        guard element.waitForExistence(timeout: 8) else {
            attach(app, named: "Missing \(name)")
            XCTFail("Missing \(name). Hierarchy: \(app.debugDescription)")
            return false
        }
        return true
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

        XCTAssertTrue(app.navigationBars["Siri & Shortcuts"].waitForExistence(timeout: 3))
        let diagnostics = app.buttons["Recap Diagnostics"]
        // The compact Duo display cannot show the entire settings list at once.
        for _ in 0..<3 where !diagnostics.exists || !diagnostics.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3), app.debugDescription)
        diagnostics.tap()

        XCTAssertTrue(app.navigationBars["Recap Diagnostics"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Month ledger"].exists)
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

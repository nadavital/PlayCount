import AppIntentsTesting
import XCTest

@available(iOS 27.0, *)
@MainActor
final class SiriIntegrationUITests: XCTestCase {
    private let definitions = IntentDefinitions(bundleIdentifier: "com.nadavavital.PlayCount")

    override func setUpWithError() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PlayCountScreenshotMode", "-PlayCountSiriIntegrationTests", "-PlayCountScreenshotTab", "recap"]
        app.launch()
        XCTAssertTrue(app.buttons["August 2026"].waitForExistence(timeout: 8))
    }

    func testAudioAlbumAndArtistStringQueries() async throws {
        let albums = try await onSupportedRuntime {
            try await definitions.entities["SiriAIAlbumEntity"].entities(matching: "  quiet motion  ")
        }
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(try albums[0].title, "Quiet Motion")
        let artists = try await definitions.entities["SiriAIArtistEntity"].entities(matching: "nova lane")
        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(try artists[0].name, "Nova Lane")
        let missing = try await definitions.entities["SiriAIAlbumEntity"].entities(matching: "No Such Album 73917")
        XCTAssertTrue(missing.isEmpty)
    }

    func testSongQueryMatchesAlbumAndStatsIntentReturnsSongCount() async throws {
        let songs = try await onSupportedRuntime {
            try await definitions.entities["SiriAISongEntity"].entities(matching: "Soft Geometry")
        }
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(try songs[0].title, "Paper Moon")
        let statsSongs = try await definitions.entities["SongEntity"].entities(matching: "Paper Moon")
        XCTAssertEqual(statsSongs.count, 1)
        let result = try await definitions.intents["SongPlayCountIntent"].makeIntent(song: statsSongs[0]).run()
        let plays: Int = try result.value
        XCTAssertEqual(plays, 88)
    }

    func testRecapSongRowsExposeSongEntities() async throws {
        let app = XCUIApplication()
        for _ in 0..<8 {
            let annotations = try await onSupportedRuntime {
                try await definitions.entities["SiriAISongEntity"].viewAnnotations()
            }
            if !annotations.isEmpty {
                let titles: [String] = try annotations.map { try $0.entity.title }
                XCTAssertTrue(titles.contains("Afterglow Drive"))
                XCTAssertFalse(titles.contains("Quiet Motion"), "A song annotation must not identify its album")
                return
            }
            app.swipeUp()
        }
        XCTFail("No song entity annotations were exposed while scrolling Recap")
    }
    private func onSupportedRuntime<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            let failure = error as NSError
            if (failure.domain == "AppIntentsServicesSecurityErrorDomain" && failure.code == 803)
                || failure.localizedDescription.contains("Remote threw needsInternalBuild") {
                throw XCTSkip("This simulator runtime requires an internal Apple build for AppIntentsTesting: \(failure.localizedDescription)")
            }
            throw error
        }
    }

}

import MediaPlayer
import SwiftUI
import UIKit

struct SystemIntegrationView: View {
    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.openURL) private var openURL
    @State private var indexStatus = PlayCountSearchIndexStatus(
        state: .notRun,
        lastUpdated: nil,
        songCount: 0,
        albumCount: 0,
        artistCount: 0
    )
    @State private var isRebuildingIndex = false

    var body: some View {
        List {
            Section("Status") {
                statusRow(
                    title: "Media Library",
                    detail: mediaPermissionDetail,
                    systemImage: mediaPermissionIsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    isReady: mediaPermissionIsReady
                )

                statusRow(
                    title: "Siri & Spotlight Index",
                    detail: indexStatusDetail,
                    systemImage: indexStatusIsReady ? "checkmark.circle.fill" : "sparkle.magnifyingglass",
                    isReady: indexStatusIsReady
                )

                statusRow(
                    title: "iOS 27 Entity Support",
                    detail: intelligenceEntityDetail,
                    systemImage: "apple.intelligence",
                    isReady: intelligenceEntitiesAreReady
                )
            }

            Section("Try Saying") {
                phrase("What are my top songs in PlayCount?")
                phrase("How many times have I played this song in PlayCount?")
                phrase("Show my latest PlayCount recap.")
                phrase("Who is my top artist this year in PlayCount?")
            }

            Section {
                Button(action: rebuildIndex) {
                    HStack {
                        Label("Rebuild Siri & Spotlight Index", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRebuildingIndex {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isRebuildingIndex || !mediaPermissionIsReady)

                if !mediaPermissionIsReady {
                    Button("Open PlayCount Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            } footer: {
                Text("Rebuilding refreshes the songs, albums, and artists that Siri and Spotlight can resolve. It does not change your Apple Music library.")
            }
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            repeat {
                indexStatus = await PlayCountSiriIntegration.searchIndexStatus()
                if indexStatus.state != .notRun { break }
                try? await Task.sleep(for: .milliseconds(500))
            } while !Task.isCancelled
        }
    }

    private var mediaPermissionIsReady: Bool {
        manager.authorizationStatus == .authorized
    }

    private var mediaPermissionDetail: String {
        mediaPermissionIsReady ? "Authorized" : "Permission required"
    }

    private var indexStatusIsReady: Bool {
        if case .ready = indexStatus.state { return true }
        return false
    }

    private var indexStatusDetail: String {
        switch indexStatus.state {
        case .notRun:
            return "Waiting for the first library refresh"
        case .ready:
            return "\(indexStatus.songCount) songs, \(indexStatus.albumCount) albums, \(indexStatus.artistCount) artists"
        case .failed(let message):
            return "Needs attention: \(message)"
        }
    }

    private var intelligenceEntityDetail: String {
        if #available(iOS 27.0, *) {
            return "Audio entities and now-playing relevance are supported"
        }
        return "Available after updating to iOS 27"
    }

    private var intelligenceEntitiesAreReady: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private func statusRow(title: String, detail: String, systemImage: String, isReady: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isReady ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func phrase(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "quote.bubble")
                .foregroundStyle(.secondary)
        }
    }

    private func rebuildIndex() {
        guard !isRebuildingIndex else { return }
        isRebuildingIndex = true
        Task {
            indexStatus = await PlayCountSiriIntegration.rebuildSearchIndex(
                songs: manager.topSongs,
                albums: manager.topAlbums,
                artists: manager.topArtists
            )
            isRebuildingIndex = false
        }
    }
}

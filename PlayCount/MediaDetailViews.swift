import SwiftUI
import MediaPlayer

struct SongInfoView: View {
    let song: TopSong

    private var averageListenLength: TimeInterval? {
        guard song.playCount > 0 else { return nil }
        return song.totalPlayDuration / Double(song.playCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                SongDetailHeader(song: song)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatRow(
                        icon: "number",
                        title: "Total Plays",
                        primaryText: song.playCount.detailFormatted,
                        secondaryText: nil
                    )

                    MediaDetailStatRow(
                        icon: "clock",
                        title: "Time Listened",
                        primaryText: song.totalPlayDuration.formattedPlayback,
                        secondaryText: nil
                    )

                    if let averageListenLength {
                        MediaDetailStatRow(
                            icon: "goforward",
                            title: "Average Listen Length",
                            primaryText: averageListenLength.formattedPlayback,
                            secondaryText: "Across \(song.playCount.detailFormatted) plays"
                        )
                    }

                    MediaDetailStatRow(
                        icon: "clock.arrow.circlepath",
                        title: "Last Played",
                        primaryText: song.lastPlayedDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never",
                        secondaryText: song.lastPlayedDate.map(MediaDetailFormatters.relativeDescription(for:))
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(song.title)
    }
}

struct AlbumInfoView: View {
    let album: TopAlbum
    @ObservedObject var manager: MediaLibraryManager

    private let songsDisplayLimit = 10

    private var averageListenLength: TimeInterval? {
        guard album.playCount > 0 else { return nil }
        return album.totalPlayDuration / Double(album.playCount)
    }

    private var albumSongs: [TopSong] {
        manager.songs(for: album, limit: songsDisplayLimit)
    }

    private var albumSongsExceedLimit: Bool {
        manager.songs(for: album).count > songsDisplayLimit
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                AlbumDetailHeader(album: album)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatRow(
                        icon: "number",
                        title: "Total Plays",
                        primaryText: album.playCount.detailFormatted,
                        secondaryText: nil
                    )

                    MediaDetailStatRow(
                        icon: "clock",
                        title: "Time Listened",
                        primaryText: album.totalPlayDuration.formattedPlayback,
                        secondaryText: nil
                    )

                    if let averageListenLength {
                        MediaDetailStatRow(
                            icon: "goforward",
                            title: "Average Listen Length",
                            primaryText: averageListenLength.formattedPlayback,
                            secondaryText: "Per play across the album"
                        )
                    }
                }

                MediaDetailSection(title: "Top Songs on This Album") {
                    if albumSongs.isEmpty {
                        Text("We haven't tracked individual plays for this album yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(albumSongs) { song in
                                NavigationLink {
                                    SongInfoView(song: song)
                                } label: {
                                    SongRow(song: song, sortMetric: manager.sortMetric)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if albumSongsExceedLimit {
                            Text("Showing top \(songsDisplayLimit) tracks by \(manager.sortMetric.toolbarLabel.lowercased()).")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(album.title)
    }
}

struct ArtistInfoView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager

    private let songsDisplayLimit = 10
    private let albumsDisplayLimit = 10

    private var averageListenLength: TimeInterval? {
        guard artist.playCount > 0 else { return nil }
        return artist.totalPlayDuration / Double(artist.playCount)
    }

    private var artistSongs: [TopSong] {
        manager.songs(for: artist, limit: songsDisplayLimit)
    }

    private var artistAlbums: [TopAlbum] {
        manager.albums(for: artist, limit: albumsDisplayLimit)
    }

    private var artistSongsExceedLimit: Bool {
        manager.songs(for: artist).count > songsDisplayLimit
    }

    private var artistAlbumsExceedLimit: Bool {
        manager.albums(for: artist).count > albumsDisplayLimit
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ArtistDetailHeader(artist: artist)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatRow(
                        icon: "number",
                        title: "Total Plays",
                        primaryText: artist.playCount.detailFormatted,
                        secondaryText: nil
                    )

                    MediaDetailStatRow(
                        icon: "clock",
                        title: "Time Listened",
                        primaryText: artist.totalPlayDuration.formattedPlayback,
                        secondaryText: nil
                    )

                    if let averageListenLength {
                        MediaDetailStatRow(
                            icon: "goforward",
                            title: "Average Listen Length",
                            primaryText: averageListenLength.formattedPlayback,
                            secondaryText: "Average per play across your library"
                        )
                    }
                }

                MediaDetailSection(title: "Top Songs") {
                    if artistSongs.isEmpty {
                        Text("No individual songs tracked for this artist yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(artistSongs) { song in
                                NavigationLink {
                                    SongInfoView(song: song)
                                } label: {
                                    SongRow(song: song, sortMetric: manager.sortMetric)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if artistSongsExceedLimit {
                            Text("Showing top \(songsDisplayLimit) songs by \(manager.sortMetric.toolbarLabel.lowercased()).")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                MediaDetailSection(title: "Top Albums") {
                    if artistAlbums.isEmpty {
                        Text("No album play data for this artist yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(artistAlbums) { album in
                                NavigationLink {
                                    AlbumInfoView(album: album, manager: manager)
                                } label: {
                                    AlbumRow(album: album, sortMetric: manager.sortMetric)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if artistAlbumsExceedLimit {
                            Text("Showing top \(albumsDisplayLimit) albums by \(manager.sortMetric.toolbarLabel.lowercased()).")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(artist.name)
    }
}

private struct SongDetailHeader: View {
    let song: TopSong

    var body: some View {
        VStack(spacing: 16) {
            ArtworkView(artwork: song.artwork, size: CGSize(width: 180, height: 180))

            VStack(spacing: 8) {
                Text(song.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(song.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(song.albumTitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                MetricBadge(text: "\(song.playCount.detailFormatted) plays")
                MetricBadge(text: song.totalPlayDuration.formattedPlayback)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AlbumDetailHeader: View {
    let album: TopAlbum

    var body: some View {
        VStack(spacing: 16) {
            ArtworkView(artwork: album.artwork, size: CGSize(width: 180, height: 180))

            VStack(spacing: 8) {
                Text(album.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(album.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MetricBadge(text: "\(album.playCount.detailFormatted) plays")
                MetricBadge(text: album.totalPlayDuration.formattedPlayback)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ArtistDetailHeader: View {
    let artist: TopArtist

    var body: some View {
        VStack(spacing: 16) {
            ArtistArtworkView(artwork: artist.artwork, name: artist.name, diameter: 180)

            VStack(spacing: 8) {
                Text(artist.name)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                MetricBadge(text: "\(artist.playCount.detailFormatted) plays")
                MetricBadge(text: artist.totalPlayDuration.formattedPlayback)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MediaDetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
}

private struct MediaDetailStatRow: View {
    let icon: String
    let title: String
    let primaryText: String
    let secondaryText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(primaryText)
                    .font(.body.weight(.semibold))
                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 12)
        }
    }
}

private enum MediaDetailFormatters {
    static let playCount: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = Locale.current.groupingSeparator
        return formatter
    }()

    static func relativeDescription(for date: Date) -> String {
        var formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private extension Int {
    var detailFormatted: String {
        MediaDetailFormatters.playCount.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

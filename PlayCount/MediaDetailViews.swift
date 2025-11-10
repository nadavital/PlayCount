import SwiftUI
import MediaPlayer

struct SongInfoView: View {
    let song: TopSong

    private var averageListenLength: TimeInterval? {
        guard song.playCount > 0 else { return nil }
        return song.totalPlayDuration / Double(song.playCount)
    }

    private var playbackStats: [MediaDetailStat] {
        var stats: [MediaDetailStat] = [
            MediaDetailStat(icon: "number", title: "Total Plays", value: song.playCount.detailFormatted),
            MediaDetailStat(icon: "clock", title: "Time Listened", value: song.totalPlayDuration.formattedPlayback)
        ]

        if let averageListenLength {
            stats.append(
                MediaDetailStat(
                    icon: "goforward",
                    title: "Average Listen Length",
                    value: averageListenLength.formattedPlayback,
                    caption: "Across \(song.playCount.detailFormatted) plays"
                )
            )
        }

        stats.append(
            MediaDetailStat(
                icon: "clock.arrow.circlepath",
                title: "Last Played",
                value: song.lastPlayedDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never",
                caption: song.lastPlayedDate.map(MediaDetailFormatters.relativeDescription(for:))
            )
        )

        return stats
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                SongDetailHeader(song: song)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatsGrid(stats: playbackStats)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
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

    private var trackedSongCount: Int {
        manager.songs(for: album).count
    }

    private var playbackStats: [MediaDetailStat] {
        var stats: [MediaDetailStat] = [
            MediaDetailStat(icon: "number", title: "Total Plays", value: album.playCount.detailFormatted),
            MediaDetailStat(icon: "clock", title: "Time Listened", value: album.totalPlayDuration.formattedPlayback)
        ]

        if let averageListenLength {
            stats.append(
                MediaDetailStat(
                    icon: "goforward",
                    title: "Average Listen Length",
                    value: averageListenLength.formattedPlayback,
                    caption: "Per play across the album"
                )
            )
        }

        if trackedSongCount > 0 {
            stats.append(
                MediaDetailStat(
                    icon: "music.note.list",
                    title: "Tracked Songs",
                    value: trackedSongCount.detailFormatted
                )
            )
        }

        return stats
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                AlbumDetailHeader(album: album)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatsGrid(stats: playbackStats)
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
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
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

    private var trackedSongCount: Int {
        manager.songs(for: artist).count
    }

    private var trackedAlbumCount: Int {
        manager.albums(for: artist).count
    }

    private var playbackStats: [MediaDetailStat] {
        var stats: [MediaDetailStat] = [
            MediaDetailStat(icon: "number", title: "Total Plays", value: artist.playCount.detailFormatted),
            MediaDetailStat(icon: "clock", title: "Time Listened", value: artist.totalPlayDuration.formattedPlayback)
        ]

        if let averageListenLength {
            stats.append(
                MediaDetailStat(
                    icon: "goforward",
                    title: "Average Listen Length",
                    value: averageListenLength.formattedPlayback,
                    caption: "Average per play across your library"
                )
            )
        }

        if trackedSongCount > 0 {
            stats.append(
                MediaDetailStat(
                    icon: "music.note",
                    title: "Tracked Songs",
                    value: trackedSongCount.detailFormatted
                )
            )
        }

        if trackedAlbumCount > 0 {
            stats.append(
                MediaDetailStat(
                    icon: "square.stack.3d.forward.dottedline",
                    title: "Tracked Albums",
                    value: trackedAlbumCount.detailFormatted
                )
            )
        }

        return stats
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ArtistDetailHeader(artist: artist)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatsGrid(stats: playbackStats)
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
                                .padding(.top, 4)
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
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(artist.name)
    }
}

private struct SongDetailHeader: View {
    let song: TopSong

    var body: some View {
        MediaDetailHero(artwork: song.artwork) {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    heroContent
                    heroContentVertical
                }

                HStack(spacing: 12) {
                    HeroMetricBadge(text: "\(song.playCount.detailFormatted) plays")
                    HeroMetricBadge(text: song.totalPlayDuration.formattedPlayback)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: 170, height: 170),
                cornerRadius: 28
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text(song.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.artist)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(song.albumTitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
        }
    }

    private var heroContentVertical: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: 150, height: 150),
                cornerRadius: 28
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(song.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Text(song.artist)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(song.albumTitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }
}

private struct AlbumDetailHeader: View {
    let album: TopAlbum

    var body: some View {
        MediaDetailHero(artwork: album.artwork) {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    heroContent
                    heroContentVertical
                }

                HStack(spacing: 12) {
                    HeroMetricBadge(text: "\(album.playCount.detailFormatted) plays")
                    HeroMetricBadge(text: album.totalPlayDuration.formattedPlayback)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroContent: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkView(
                artwork: album.artwork,
                size: CGSize(width: 170, height: 170),
                cornerRadius: 28
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(album.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Text(album.artist)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }

    private var heroContentVertical: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArtworkView(
                artwork: album.artwork,
                size: CGSize(width: 150, height: 150),
                cornerRadius: 28
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(album.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Text(album.artist)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }
}

private struct ArtistDetailHeader: View {
    let artist: TopArtist

    var body: some View {
        MediaDetailHero(artwork: artist.artwork) {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    heroContent
                    heroContentVertical
                }

                HStack(spacing: 12) {
                    HeroMetricBadge(text: "\(artist.playCount.detailFormatted) plays")
                    HeroMetricBadge(text: artist.totalPlayDuration.formattedPlayback)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroContent: some View {
        HStack(alignment: .center, spacing: 20) {
            ArtistArtworkView(
                artwork: artist.artwork,
                name: artist.name,
                diameter: 160
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(artist.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
    }

    private var heroContentVertical: some View {
        VStack(alignment: .leading, spacing: 16) {
            ArtistArtworkView(
                artwork: artist.artwork,
                name: artist.name,
                diameter: 140
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 16)

            Text(artist.name)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
        }
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
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediaDetailHero<Content: View>: View {
    let artwork: MPMediaItemArtwork?
    let content: Content

    init(artwork: MPMediaItemArtwork?, @ViewBuilder content: () -> Content) {
        self.artwork = artwork
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaDetailHeroBackground(artwork: artwork)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.08)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .allowsHitTesting(false)

            content
                .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct MediaDetailHeroBackground: View {
    let artwork: MPMediaItemArtwork?

    var body: some View {
        Group {
            if let artwork, let image = artwork.image(at: CGSize(width: 900, height: 900)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 70)
                    .scaleEffect(1.2)
                    .saturation(1.05)
                    .brightness(-0.15)
            } else {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.9),
                        Color.accentColor.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct HeroMetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.22))
            )
    }
}

private struct MediaDetailStat: Identifiable {
    let icon: String
    let title: String
    let value: String
    let caption: String?

    var id: String { title }

    init(icon: String, title: String, value: String, caption: String? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.caption = caption
    }
}

private struct MediaDetailStatsGrid: View {
    let stats: [MediaDetailStat]

    private var columns: [GridItem] {
        stats.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(stats) { stat in
                MediaDetailStatTile(stat: stat)
            }
        }
    }
}

private struct MediaDetailStatTile: View {
    let stat: MediaDetailStat

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: stat.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(stat.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(stat.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if let caption = stat.caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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

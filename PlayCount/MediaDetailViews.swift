import SwiftUI
import MediaPlayer
import CoreImage.CIFilterBuiltins

struct SongInfoView: View {
    let song: TopSong
    @ObservedObject var manager: MediaLibraryManager

    private var averageListenLength: TimeInterval? {
        guard song.playCount > 0 else { return nil }
        return song.totalPlayDuration / Double(song.playCount)
    }

    private var album: TopAlbum? {
        manager.album(withPersistentID: song.albumPersistentID)
    }

    private var artist: TopArtist? {
        manager.artist(withPersistentID: song.artistPersistentID)
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
            VStack(spacing: 32) {
                SongDetailHeader(song: song, album: album, artist: artist, manager: manager)

                MediaDetailSection(title: "Playback Stats") {
                    MediaDetailStatsGrid(stats: playbackStats)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .background(MediaDetailBackground(artwork: song.artwork))
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

    private var artist: TopArtist? {
        manager.artist(withPersistentID: album.artistPersistentID)
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
            VStack(spacing: 32) {
                AlbumDetailHeader(album: album, artist: artist, manager: manager)

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
                                    SongInfoView(song: song, manager: manager)
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
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .background(MediaDetailBackground(artwork: album.artwork))
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
            VStack(spacing: 32) {
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
                                    SongInfoView(song: song, manager: manager)
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
            .padding(.vertical, 32)
        }
        .background(Color(.systemGroupedBackground))
        .background(MediaDetailBackground(artwork: artist.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(artist.name)
    }
}

private struct SongDetailHeader: View {
    let song: TopSong
    let album: TopAlbum?
    let artist: TopArtist?
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        MediaDetailHeaderLayout {
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: 220, height: 220),
                cornerRadius: 26
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 12)
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text(song.title)
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(3)

                relatedDestinations

                HStack(spacing: 12) {
                    HeaderMetricBadge(text: "\(song.playCount.detailFormatted) plays")
                    HeaderMetricBadge(text: song.totalPlayDuration.formattedPlayback)
                }
            }
        }
    }

    @ViewBuilder
    private var relatedDestinations: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let album {
                NavigationLink {
                    AlbumInfoView(album: album, manager: manager)
                } label: {
                    DetailDestinationRow(icon: "rectangle.stack.fill", title: album.title, caption: "Album")
                }
                .buttonStyle(.plain)
            } else if !song.albumTitle.isEmpty {
                DetailInfoPlaceholder(icon: "rectangle.stack.fill", title: song.albumTitle, caption: "Album")
            }

            if let artist {
                NavigationLink {
                    ArtistInfoView(artist: artist, manager: manager)
                } label: {
                    DetailDestinationRow(icon: "person.crop.circle", title: artist.name, caption: "Artist")
                }
                .buttonStyle(.plain)
            } else if !song.artist.isEmpty {
                DetailInfoPlaceholder(icon: "person.crop.circle", title: song.artist, caption: "Artist")
            }
        }
    }
}

private struct AlbumDetailHeader: View {
    let album: TopAlbum
    let artist: TopArtist?
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        MediaDetailHeaderLayout {
            ArtworkView(
                artwork: album.artwork,
                size: CGSize(width: 220, height: 220),
                cornerRadius: 26
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 12)
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text(album.title)
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(3)

                if let artist {
                    NavigationLink {
                        ArtistInfoView(artist: artist, manager: manager)
                    } label: {
                        DetailDestinationRow(icon: "person.crop.circle", title: artist.name, caption: "Artist")
                    }
                    .buttonStyle(.plain)
                } else if !album.artist.isEmpty {
                    DetailInfoPlaceholder(icon: "person.crop.circle", title: album.artist, caption: "Artist")
                }

                HStack(spacing: 12) {
                    HeaderMetricBadge(text: "\(album.playCount.detailFormatted) plays")
                    HeaderMetricBadge(text: album.totalPlayDuration.formattedPlayback)
                }
            }
        }
    }
}

private struct ArtistDetailHeader: View {
    let artist: TopArtist

    var body: some View {
        MediaDetailHeaderLayout {
            ArtistArtworkView(
                artwork: artist.artwork,
                name: artist.name,
                diameter: 220
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 12)
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text(artist.name)
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(3)

                HStack(spacing: 12) {
                    HeaderMetricBadge(text: "\(artist.playCount.detailFormatted) plays")
                    HeaderMetricBadge(text: artist.totalPlayDuration.formattedPlayback)
                }
            }
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

private struct MediaDetailHeaderLayout<Artwork: View, Content: View>: View {
    private let artwork: () -> Artwork
    private let content: () -> Content

    init(@ViewBuilder artwork: @escaping () -> Artwork, @ViewBuilder content: @escaping () -> Content) {
        self.artwork = artwork
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 28) {
                artwork()

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 24) {
                artwork()
                content()
            }
        }
    }
}

private struct DetailDestinationRow: View {
    let icon: String
    let title: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(caption.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.95))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailInfoPlaceholder: View {
    let icon: String
    let title: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(caption.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.08))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeaderMetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.9))
            )
    }
}

private struct MediaDetailBackground: View {
    let artwork: MPMediaItemArtwork?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)

            if let gradientColors = gradientColors {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.9)
            }
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color]? {
        guard let components = artwork?.averageColorComponents() else {
            return nil
        }

        let start = lightenColor(components: components, amount: 0.4)
        let end = lightenColor(components: components, amount: 0.75)

        return [start.opacity(0.8), end.opacity(0.65)]
    }

    private func lightenColor(components: (Double, Double, Double), amount: Double) -> Color {
        Color(
            red: lightenComponent(components.0, amount: amount),
            green: lightenComponent(components.1, amount: amount),
            blue: lightenComponent(components.2, amount: amount)
        )
    }

    private func lightenComponent(_ component: Double, amount: Double) -> Double {
        component + (1 - component) * amount
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

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
            ForEach(stats) { stat in
                MediaDetailStatCard(stat: stat)
            }
        }
    }
}

private struct MediaDetailStatCard: View {
    let stat: MediaDetailStat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: stat.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(stat.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(stat.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let caption = stat.caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground).opacity(0.95))
        )
    }
}

private enum MediaDetailColorCalculator {
    static let context = CIContext(options: [.workingColorSpace: NSNull()])
}

private extension MPMediaItemArtwork {
    func averageColorComponents(maxDimension: CGFloat = 80) -> (Double, Double, Double)? {
        let targetSize = CGSize(width: maxDimension, height: maxDimension)

        guard let image = image(at: targetSize),
              let inputImage = CIImage(image: image) else {
            return nil
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        MediaDetailColorCalculator.context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        guard bitmap[3] > 0 else {
            return nil
        }

        return (
            Double(bitmap[0]) / 255,
            Double(bitmap[1]) / 255,
            Double(bitmap[2]) / 255
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

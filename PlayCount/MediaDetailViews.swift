import SwiftUI
import MediaPlayer
import CoreImage.CIFilterBuiltins

struct SongInfoView: View {
    let song: TopSong
    @ObservedObject var manager: MediaLibraryManager

    private var album: TopAlbum? {
        manager.album(withPersistentID: song.albumPersistentID)
    }

    private var artist: TopArtist? {
        manager.artist(withPersistentID: song.artistPersistentID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SongDetailHeader(song: song, album: album, artist: artist, manager: manager)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 60)
        }
        .background(MediaDetailBackground(artwork: song.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(song.title)
    }
}

struct AlbumInfoView: View {
    let album: TopAlbum
    @ObservedObject var manager: MediaLibraryManager

    private var artist: TopArtist? {
        manager.artist(withPersistentID: album.artistPersistentID)
    }

    private var albumSongs: [TopSong] {
        let songs = manager.songs(for: album)
        return songs.sorted { lhs, rhs in
            if lhs.trackNumber > 0 && rhs.trackNumber > 0 {
                if lhs.trackNumber == rhs.trackNumber {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.trackNumber < rhs.trackNumber
            }

            if lhs.trackNumber > 0 {
                return true
            }

            if rhs.trackNumber > 0 {
                return false
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                AlbumDetailHeader(album: album, artist: artist, manager: manager)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Songs")
                        .font(.title3.weight(.semibold))

                    if albumSongs.isEmpty {
                        Text("We haven't tracked individual plays for this album yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(albumSongs) { song in
                                NavigationLink {
                                    SongInfoView(song: song, manager: manager)
                                } label: {
                                    AlbumTrackRow(song: song)
                                }
                                .buttonStyle(.plain)

                                if song.id != albumSongs.last?.id {
                                    Divider()
                                        .overlay(Color.primary.opacity(0.1))
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 60)
        }
        .background(MediaDetailBackground(artwork: album.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(album.title)
    }
}

struct ArtistInfoView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager

    private let displayLimit = 5

    var body: some View {
        let songs = manager.songs(for: artist)
        let albums = manager.albums(for: artist)
        let topSongs = Array(songs.prefix(displayLimit))
        let topAlbums = Array(albums.prefix(displayLimit))

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ArtistDetailHeader(artist: artist, manager: manager)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Top Songs")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if songs.count > displayLimit {
                            NavigationLink {
                                ArtistSongsListView(artist: artist, manager: manager)
                            } label: {
                                Text("See All")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if topSongs.isEmpty {
                        Text("No individual songs tracked for this artist yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(topSongs) { song in
                                NavigationLink {
                                    SongInfoView(song: song, manager: manager)
                                } label: {
                                    SongRow(song: song, sortMetric: manager.sortMetric)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Top Albums")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if albums.count > displayLimit {
                            NavigationLink {
                                ArtistAlbumsListView(artist: artist, manager: manager)
                            } label: {
                                Text("See All")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if topAlbums.isEmpty {
                        Text("No album play data for this artist yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(topAlbums) { album in
                                NavigationLink {
                                    AlbumInfoView(album: album, manager: manager)
                                } label: {
                                    AlbumRow(album: album, sortMetric: manager.sortMetric)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 60)
        }
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

    private var isCurrentSong: Bool {
        manager.nowPlayingState?.song?.id == song.id
    }

    private var isPlayingCurrentSong: Bool {
        isCurrentSong && (manager.nowPlayingState?.isPlaying == true)
    }

    private var playButtonTitle: String {
        if isCurrentSong {
            return isPlayingCurrentSong ? "Pause" : "Resume"
        }
        return "Play Song"
    }

    private var playButtonIcon: String {
        if isCurrentSong {
            return isPlayingCurrentSong ? "pause.fill" : "play.fill"
        }
        return "play.fill"
    }

    var body: some View {
        VStack(spacing: 28) {
            // Hero Artwork
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: 320, height: 320),
                cornerRadius: 24
            )

            // Title, Artist Info, and Playback in Glass Card
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text(song.title)
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    VStack(spacing: 8) {
                        albumLink
                        artistLink
                    }
                }

                // Glass Play Button
                Button(action: handlePlayTapped) {
                    HStack(spacing: 10) {
                        Image(systemName: playButtonIcon)
                            .font(.body.weight(.semibold))
                        Text(playButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // Play Count Metrics - Prominent Display
            HStack(spacing: 12) {
                MediaDetailMetric(
                    title: "Plays",
                    value: song.playCount.detailFormatted,
                    subtitle: manager.playCountRank(of: song).map { "Ranked #\($0)" }
                )
                MediaDetailMetric(
                    title: "Time Listened",
                    value: song.totalPlayDuration.formattedListenTime,
                    subtitle: manager.listenTimeRank(of: song).map { "Ranked #\($0)" }
                )
            }
        }
    }

    @ViewBuilder
    private var albumLink: some View {
        if let album {
            NavigationLink {
                AlbumInfoView(album: album, manager: manager)
            } label: {
                Text(album.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } else if !song.albumTitle.isEmpty {
            Text(song.albumTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var artistLink: some View {
        if let artist {
            NavigationLink {
                ArtistInfoView(artist: artist, manager: manager)
            } label: {
                Text(artist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } else if !song.artist.isEmpty {
            Text(song.artist)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
    }

    private func handlePlayTapped() {
        if isCurrentSong {
            manager.togglePlayback()
        } else {
            manager.play(song: song)
        }
    }
}

private struct AlbumDetailHeader: View {
    let album: TopAlbum
    let artist: TopArtist?
    @ObservedObject var manager: MediaLibraryManager

    private var isCurrentAlbum: Bool {
        guard let nowPlaying = manager.nowPlayingState?.song else { return false }
        if album.id != 0 {
            return nowPlaying.albumPersistentID == album.id
        }
        return nowPlaying.albumTitle.localizedCaseInsensitiveCompare(album.title) == .orderedSame
    }

    private var isPlayingCurrentAlbum: Bool {
        isCurrentAlbum && (manager.nowPlayingState?.isPlaying == true)
    }

    private var playButtonTitle: String {
        if isCurrentAlbum {
            return isPlayingCurrentAlbum ? "Pause" : "Resume"
        }
        return "Play Album"
    }

    private var playButtonIcon: String {
        if isCurrentAlbum {
            return isPlayingCurrentAlbum ? "pause.fill" : "play.fill"
        }
        return "play.fill"
    }

    var body: some View {
        VStack(spacing: 28) {
            // Hero Artwork
            ArtworkView(
                artwork: album.artwork,
                size: CGSize(width: 320, height: 320),
                cornerRadius: 24
            )

            // Title, Artist Info, and Playback in Glass Card
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text(album.title)
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    artistLink
                }

                // Glass Play Button
                Button(action: handlePlayTapped) {
                    HStack(spacing: 10) {
                        Image(systemName: playButtonIcon)
                            .font(.body.weight(.semibold))
                        Text(playButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // Play Count Metrics - Prominent Display
            HStack(spacing: 12) {
                MediaDetailMetric(
                    title: "Plays",
                    value: album.playCount.detailFormatted,
                    subtitle: manager.playCountRank(of: album).map { "Ranked #\($0)" }
                )
                MediaDetailMetric(
                    title: "Time Listened",
                    value: album.totalPlayDuration.formattedListenTime,
                    subtitle: manager.listenTimeRank(of: album).map { "Ranked #\($0)" }
                )
            }
        }
    }

    @ViewBuilder
    private var artistLink: some View {
        if let artist {
            NavigationLink {
                ArtistInfoView(artist: artist, manager: manager)
            } label: {
                Text(artist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        } else if !album.artist.isEmpty {
            Text(album.artist)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
    }

    private func handlePlayTapped() {
        if isCurrentAlbum {
            manager.togglePlayback()
        } else {
            manager.play(album: album)
        }
    }
}

private struct ArtistDetailHeader: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager

    private var isCurrentArtist: Bool {
        guard let nowPlaying = manager.nowPlayingState?.song else { return false }
        if artist.id != 0 {
            return nowPlaying.artistPersistentID == artist.id
        }
        return nowPlaying.artist.localizedCaseInsensitiveCompare(artist.name) == .orderedSame
    }

    private var isPlayingCurrentArtist: Bool {
        isCurrentArtist && (manager.nowPlayingState?.isPlaying == true)
    }

    private var playButtonTitle: String {
        if isCurrentArtist {
            return isPlayingCurrentArtist ? "Pause" : "Resume"
        }
        return "Play Artist"
    }

    private var playButtonIcon: String {
        if isCurrentArtist {
            return isPlayingCurrentArtist ? "pause.fill" : "play.fill"
        }
        return "play.fill"
    }

    var body: some View {
        VStack(spacing: 28) {
            // Hero Artist Artwork (Circular)
            ArtistArtworkView(
                artwork: artist.artwork,
                name: artist.name,
                diameter: 320
            )

            // Artist Name and Playback in Glass Card
            VStack(spacing: 16) {
                Text(artist.name)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                // Glass Play Button
                Button(action: handlePlayTapped) {
                    HStack(spacing: 10) {
                        Image(systemName: playButtonIcon)
                            .font(.body.weight(.semibold))
                        Text(playButtonTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )

            // Play Count Metrics - Prominent Display
            HStack(spacing: 12) {
                MediaDetailMetric(
                    title: "Plays",
                    value: artist.playCount.detailFormatted,
                    subtitle: manager.playCountRank(of: artist).map { "Ranked #\($0)" }
                )
                MediaDetailMetric(
                    title: "Time Listened",
                    value: artist.totalPlayDuration.formattedListenTime,
                    subtitle: manager.listenTimeRank(of: artist).map { "Ranked #\($0)" }
                )
            }
        }
    }

    private func handlePlayTapped() {
        if isCurrentArtist {
            manager.togglePlayback()
        } else {
            manager.play(artist: artist)
        }
    }
}

private struct MediaDetailMetric: View {
    let title: String
    let value: String
    let subtitle: String?

    init(title: String, value: String, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

private struct AlbumTrackRow: View {
    let song: TopSong

    var body: some View {
        HStack(spacing: 16) {
            if song.trackNumber > 0 {
                Text("\(song.trackNumber)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            } else {
                Text("•")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(song.playCount.detailFormatted) plays • \(song.totalPlayDuration.formattedListenTime) listened")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct ArtistSongsListView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager

    private var songs: [TopSong] {
        manager.songs(for: artist)
    }

    var body: some View {
        List {
            if songs.isEmpty {
                EmptyLibrarySection(
                    systemImage: "music.note.slash",
                    title: "No Songs Tracked",
                    message: "Play songs by \(artist.name) to see them here."
                )
            } else {
                ForEach(songs) { song in
                    NavigationLink {
                        SongInfoView(song: song, manager: manager)
                    } label: {
                        SongRow(song: song, sortMetric: manager.sortMetric)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(artist.name) Songs")
    }
}

private struct ArtistAlbumsListView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager

    private var albums: [TopAlbum] {
        manager.albums(for: artist)
    }

    var body: some View {
        List {
            if albums.isEmpty {
                EmptyLibrarySection(
                    systemImage: "rectangle.stack.badge.slash",
                    title: "No Albums Tracked",
                    message: "Listen to \(artist.name) to see their albums here."
                )
            } else {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumInfoView(album: album, manager: manager)
                    } label: {
                        AlbumRow(album: album, sortMetric: manager.sortMetric)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(artist.name) Albums")
    }
}

private struct MediaDetailBackground: View {
    let artwork: MPMediaItemArtwork?

    var body: some View {
        ZStack {
            if let gradientColors = gradientColors {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(.systemGroupedBackground)
            }

            Color(.systemBackground)
                .opacity(0.12)
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color]? {
        guard let components = artwork?.averageColorComponents() else {
            return nil
        }

        let start = Color(
            red: darken(components.0, amount: 0.35),
            green: darken(components.1, amount: 0.35),
            blue: darken(components.2, amount: 0.35)
        )

        let mid = Color(
            red: boost(components.0, amount: 0.15),
            green: boost(components.1, amount: 0.15),
            blue: boost(components.2, amount: 0.15)
        )

        let end = Color(
            red: boost(components.0, amount: 0.4),
            green: boost(components.1, amount: 0.4),
            blue: boost(components.2, amount: 0.4)
        )

        return [start, mid, end]
    }

    private func darken(_ component: Double, amount: Double) -> Double {
        max(component * (1 - amount), 0)
    }

    private func boost(_ component: Double, amount: Double) -> Double {
        min(component + (1 - component) * amount, 1)
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
}

private extension Int {
    var detailFormatted: String {
        MediaDetailFormatters.playCount.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

private extension TimeInterval {
    var formattedListenTime: String {
        if self <= 0 { return "0m" }
        if self < 60 { return "<1m" }
        if let formatted = TimeInterval.listenFormatter.string(from: self) {
            return formatted
        }
        let minutes = Int(self / 60)
        return "\(minutes)m"
    }

    static let listenFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.dropAll]
        formatter.maximumUnitCount = 2
        return formatter
    }()
}


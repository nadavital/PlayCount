import SwiftUI
import MediaPlayer

struct RecapPeriodBreakdown: Identifiable {
    let id: String
    let title: String
    let songs: [MonthlyRecap.RankedSong]
}

struct RecapPeriodSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let playDelta: Int
    let listeningDuration: TimeInterval
    let artwork: MPMediaItemArtwork?
}

struct RecapDrilldownContext {
    let monthTitle: String
    let songs: [MonthlyRecap.RankedSong]
    let songSectionTitle: String
    let songsSectionTitle: String
    let periodBreakdowns: [RecapPeriodBreakdown]

    init(
        monthTitle: String,
        songs: [MonthlyRecap.RankedSong],
        songSectionTitle: String = "This Month",
        songsSectionTitle: String = "Top This Month",
        periodBreakdowns: [RecapPeriodBreakdown] = []
    ) {
        self.monthTitle = monthTitle
        self.songs = songs
        self.songSectionTitle = songSectionTitle
        self.songsSectionTitle = songsSectionTitle
        self.periodBreakdowns = periodBreakdowns
    }

    func rankedSong(for song: TopSong) -> MonthlyRecap.RankedSong? {
        songs.first { $0.id == song.id }
            ?? songs.first {
                $0.title.recapDetailMatchKey == song.title.recapDetailMatchKey &&
                    $0.artist.recapDetailMatchKey == song.artist.recapDetailMatchKey
            }
    }

    func songs(for album: TopAlbum) -> [MonthlyRecap.RankedSong] {
        sortedMonthlySongs {
            $0.albumTitle.recapDetailMatchKey == album.title.recapDetailMatchKey &&
                (album.artist.isEmpty || $0.artist.recapDetailMatchKey == album.artist.recapDetailMatchKey)
        }
    }

    func songs(for artist: TopArtist) -> [MonthlyRecap.RankedSong] {
        sortedMonthlySongs {
            $0.artist.recapDetailMatchKey == artist.name.recapDetailMatchKey
        }
    }

    func periodSummaries(for song: TopSong) -> [RecapPeriodSummary] {
        periodBreakdowns.compactMap { period in
            guard let periodSong = period.songs.first(where: {
                $0.id == song.id ||
                    ($0.title.recapDetailMatchKey == song.title.recapDetailMatchKey &&
                     $0.artist.recapDetailMatchKey == song.artist.recapDetailMatchKey)
            }) else {
                return nil
            }

            return RecapPeriodSummary(
                id: "\(period.id)-\(song.id)",
                title: period.title,
                subtitle: periodSong.artist,
                playDelta: periodSong.playDelta,
                listeningDuration: periodSong.listeningDuration,
                artwork: periodSong.artwork ?? song.artwork
            )
        }
    }

    func periodSummaries(for album: TopAlbum) -> [RecapPeriodSummary] {
        periodBreakdowns.compactMap { period in
            let songs = sortedSongs(period.songs) {
                $0.albumTitle.recapDetailMatchKey == album.title.recapDetailMatchKey &&
                    (album.artist.isEmpty || $0.artist.recapDetailMatchKey == album.artist.recapDetailMatchKey)
            }
            guard !songs.isEmpty else { return nil }

            return RecapPeriodSummary(
                id: "\(period.id)-\(album.id)",
                title: period.title,
                subtitle: songs.first?.title ?? album.artist,
                playDelta: songs.reduce(0) { $0 + $1.playDelta },
                listeningDuration: songs.reduce(0) { $0 + $1.listeningDuration },
                artwork: songs.first?.artwork ?? album.artwork
            )
        }
    }

    func periodSummaries(for artist: TopArtist) -> [RecapPeriodSummary] {
        periodBreakdowns.compactMap { period in
            let songs = sortedSongs(period.songs) {
                $0.artist.recapDetailMatchKey == artist.name.recapDetailMatchKey
            }
            guard !songs.isEmpty else { return nil }

            return RecapPeriodSummary(
                id: "\(period.id)-\(artist.id)",
                title: period.title,
                subtitle: songs.first?.title ?? "Top song",
                playDelta: songs.reduce(0) { $0 + $1.playDelta },
                listeningDuration: songs.reduce(0) { $0 + $1.listeningDuration },
                artwork: songs.first?.artwork ?? artist.artwork
            )
        }
    }

    private func sortedMonthlySongs(matching predicate: (MonthlyRecap.RankedSong) -> Bool) -> [MonthlyRecap.RankedSong] {
        sortedSongs(songs, matching: predicate)
    }

    private func sortedSongs(
        _ songs: [MonthlyRecap.RankedSong],
        matching predicate: (MonthlyRecap.RankedSong) -> Bool
    ) -> [MonthlyRecap.RankedSong] {
        songs
            .filter(predicate)
            .sorted {
                if $0.playDelta == $1.playDelta {
                    if $0.listeningDuration == $1.listeningDuration {
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    return $0.listeningDuration > $1.listeningDuration
                }
                return $0.playDelta > $1.playDelta
            }
    }
}

struct SongInfoView: View {
    let song: TopSong
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext?
    let reservesBottomAccessorySpace: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        song: TopSong,
        manager: MediaLibraryManager,
        recapContext: RecapDrilldownContext? = nil,
        reservesBottomAccessorySpace: Bool = true
    ) {
        self.song = song
        self.manager = manager
        self.recapContext = recapContext
        self.reservesBottomAccessorySpace = reservesBottomAccessorySpace
    }

    private var album: TopAlbum? {
        manager.album(withPersistentID: song.albumPersistentID)
    }

    private var artist: TopArtist? {
        manager.artist(withPersistentID: song.artistPersistentID)
    }

    private var albumCompanionSongs: [TopSong] {
        guard let album else { return [] }
        return manager.songs(for: album)
            .filter { $0.id != song.id }
            .prefix(6)
            .map { $0 }
    }

    private var artistCompanionSongs: [TopSong] {
        guard let artist else { return [] }
        return manager.songs(for: artist)
            .filter { $0.id != song.id }
            .prefix(6)
            .map { $0 }
    }

    private var additionalTopSongs: [TopSong] {
        let relatedIDs = Set(albumCompanionSongs.map(\.id) + artistCompanionSongs.map(\.id) + [song.id])
        return manager.topSongs
            .filter { !relatedIDs.contains($0.id) }
            .prefix(6)
            .map { $0 }
    }

    private var relatedColumns: [GridItem] {
        let count = isRegularWidth ? 2 : 1
        return Array(repeating: GridItem(.flexible(minimum: 280), spacing: 16, alignment: .top), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SongDetailHeader(song: song, album: album, artist: artist, manager: manager)
                    .frame(maxWidth: .infinity)

                if let monthlySong = recapContext?.rankedSong(for: song) {
                    MonthlyDetailSongSection(
                        title: recapContext?.songSectionTitle ?? "This Month",
                        periodTitle: recapContext?.monthTitle ?? "This Month",
                        song: monthlySong
                    )
                }

                if let periodSummaries = recapContext?.periodSummaries(for: song), !periodSummaries.isEmpty {
                    RecapDetailPeriodBreakdownSection(title: "By Month", summaries: periodSummaries)
                }

                relatedSongSections
            }
            .padding(.horizontal, isRegularWidth ? 36 : 24)
            .padding(.top, isRegularWidth ? 28 : 40)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: isRegularWidth ? 1080 : .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .background(MediaDetailBackground(artwork: song.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(song.title)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var bottomPadding: CGFloat {
        isRegularWidth ? (reservesBottomAccessorySpace ? 132 : 48) : 60
    }

    @ViewBuilder
    private var relatedSongSections: some View {
        if !albumCompanionSongs.isEmpty || !artistCompanionSongs.isEmpty || !additionalTopSongs.isEmpty {
            LazyVGrid(columns: relatedColumns, alignment: .leading, spacing: 16) {
                if !albumCompanionSongs.isEmpty {
                    RelatedSongsSection(title: "On This Album", songs: albumCompanionSongs, manager: manager)
                }

                if !artistCompanionSongs.isEmpty {
                    RelatedSongsSection(title: "More by \(song.artist)", songs: artistCompanionSongs, manager: manager)
                }

                if !additionalTopSongs.isEmpty {
                    RelatedSongsSection(title: "Other Top Songs", songs: additionalTopSongs, manager: manager)
                }
            }
        }
    }
}

struct AlbumInfoView: View {
    let album: TopAlbum
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext?
    let reservesBottomAccessorySpace: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        album: TopAlbum,
        manager: MediaLibraryManager,
        recapContext: RecapDrilldownContext? = nil,
        reservesBottomAccessorySpace: Bool = true
    ) {
        self.album = album
        self.manager = manager
        self.recapContext = recapContext
        self.reservesBottomAccessorySpace = reservesBottomAccessorySpace
    }

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

    private var monthlySongs: [MonthlyRecap.RankedSong] {
        recapContext?.songs(for: album) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                AlbumDetailHeader(album: album, artist: artist, manager: manager)
                    .frame(maxWidth: .infinity)

                if let recapContext, !monthlySongs.isEmpty {
                    MonthlyDetailSongsSection(
                        title: recapContext.songsSectionTitle,
                        subtitle: recapContext.monthTitle,
                        songs: monthlySongs,
                        manager: manager,
                        recapContext: recapContext
                    )
                }

                if let periodSummaries = recapContext?.periodSummaries(for: album), !periodSummaries.isEmpty {
                    RecapDetailPeriodBreakdownSection(title: "By Month", summaries: periodSummaries)
                }

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
            .padding(.horizontal, isRegularWidth ? 36 : 24)
            .padding(.top, isRegularWidth ? 28 : 40)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: isRegularWidth ? 1080 : .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .background(MediaDetailBackground(artwork: album.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(album.title)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var bottomPadding: CGFloat {
        isRegularWidth ? (reservesBottomAccessorySpace ? 132 : 48) : 60
    }
}

struct ArtistInfoView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext?
    let reservesBottomAccessorySpace: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let displayLimit = 5
    private let topSongsSectionID = "artist-detail-top-songs"

    private static var screenshotFocusesArtistContent: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotArtistContent")
        #else
        false
        #endif
    }

    init(
        artist: TopArtist,
        manager: MediaLibraryManager,
        recapContext: RecapDrilldownContext? = nil,
        reservesBottomAccessorySpace: Bool = true
    ) {
        self.artist = artist
        self.manager = manager
        self.recapContext = recapContext
        self.reservesBottomAccessorySpace = reservesBottomAccessorySpace
    }

    var body: some View {
        let songs = manager.songs(for: artist)
        let albums = manager.albums(for: artist)
        let topSongs = Array(songs.prefix(displayLimit))
        let topAlbums = Array(albums.prefix(displayLimit))
        let monthlySongs = recapContext?.songs(for: artist) ?? []

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    ArtistDetailHeader(artist: artist, manager: manager)
                        .frame(maxWidth: .infinity)

                    if let recapContext, !monthlySongs.isEmpty {
                        MonthlyDetailSongsSection(
                            title: recapContext.songsSectionTitle,
                            subtitle: recapContext.monthTitle,
                            songs: monthlySongs,
                            manager: manager,
                            recapContext: recapContext
                        )
                    }

                    if let periodSummaries = recapContext?.periodSummaries(for: artist), !periodSummaries.isEmpty {
                        RecapDetailPeriodBreakdownSection(title: "By Month", summaries: periodSummaries)
                    }

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
                    .id(topSongsSectionID)

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
                .padding(.horizontal, isRegularWidth ? 36 : 24)
                .padding(.top, isRegularWidth ? 28 : 40)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: isRegularWidth ? 1080 : .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .task {
                guard Self.screenshotFocusesArtistContent else { return }
                try? await Task.sleep(for: .milliseconds(450))
                proxy.scrollTo(topSongsSectionID, anchor: .top)
            }
        }
        .scrollIndicators(.hidden)
        .background(MediaDetailBackground(artwork: artist.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(artist.name)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var bottomPadding: CGFloat {
        isRegularWidth ? (reservesBottomAccessorySpace ? 132 : 48) : 60
    }
}

private struct SongDetailHeader: View {
    let song: TopSong
    let album: TopAlbum?
    let artist: TopArtist?
    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var artworkSize: CGFloat {
        isRegularWidth ? 260 : 320
    }

    var body: some View {
        MediaDetailGlassGroup {
            if isRegularWidth {
                HStack(alignment: .center, spacing: 28) {
                    heroArtwork
                        .frame(width: artworkSize)

                    VStack(spacing: 16) {
                        infoCard
                        metrics
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 28) {
                    heroArtwork
                    infoCard
                    metrics
                }
            }
        }
    }

    private var heroArtwork: some View {
        ArtworkView(
            artwork: song.artwork,
            size: CGSize(width: artworkSize, height: artworkSize),
            cornerRadius: isRegularWidth ? 22 : 24
        )
    }

    private var infoCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text(song.title)
                    .font(.system(size: isRegularWidth ? 30 : 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                VStack(spacing: 8) {
                    albumLink
                    artistLink
                }
            }

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
        .libraryGlassSurface(cornerRadius: 20, tintOpacity: 0.1)
    }

    private var metrics: some View {
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var artworkSize: CGFloat {
        isRegularWidth ? 260 : 320
    }

    var body: some View {
        MediaDetailGlassGroup {
            if isRegularWidth {
                HStack(alignment: .center, spacing: 28) {
                    heroArtwork
                        .frame(width: artworkSize)

                    VStack(spacing: 16) {
                        infoCard
                        metrics
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 28) {
                    heroArtwork
                    infoCard
                    metrics
                }
            }
        }
    }

    private var heroArtwork: some View {
        ArtworkView(
            artwork: album.artwork,
            size: CGSize(width: artworkSize, height: artworkSize),
            cornerRadius: isRegularWidth ? 22 : 24
        )
    }

    private var infoCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text(album.title)
                    .font(.system(size: isRegularWidth ? 30 : 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                artistLink
            }

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
        .libraryGlassSurface(cornerRadius: 20, tintOpacity: 0.1)
    }

    private var metrics: some View {
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var artworkSize: CGFloat {
        isRegularWidth ? 260 : 320
    }

    var body: some View {
        MediaDetailGlassGroup {
            if isRegularWidth {
                HStack(alignment: .center, spacing: 28) {
                    heroArtwork
                        .frame(width: artworkSize)

                    VStack(spacing: 16) {
                        infoCard
                        metrics
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 28) {
                    heroArtwork
                    infoCard
                    metrics
                }
            }
        }
    }

    private var heroArtwork: some View {
        ArtistArtworkView(
            artwork: artist.artwork,
            name: artist.name,
            diameter: artworkSize
        )
    }

    private var infoCard: some View {
        VStack(spacing: 16) {
            Text(artist.name)
                .font(.system(size: isRegularWidth ? 30 : 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(2)

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
        .libraryGlassSurface(cornerRadius: 20, tintOpacity: 0.1)
    }

    private var metrics: some View {
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
        .libraryGlassSurface(cornerRadius: 20, tintOpacity: 0.08)
    }
}

private struct MediaDetailGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                content
            }
        } else {
            content
        }
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

                Text("\(song.playCount.detailFormatted) plays • \(song.totalPlayDuration.formattedListeningMinutes) listened")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct MonthlyDetailSongSection: View {
    let title: String
    let periodTitle: String
    let song: MonthlyRecap.RankedSong

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            MonthlyDetailSongDeltaRow(song: song, subtitle: periodTitle)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
    }
}

private struct RelatedSongsSection: View {
    let title: String
    let songs: [TopSong]
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            LazyVStack(spacing: 12) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    NavigationLink {
                        SongInfoView(song: song, manager: manager)
                    } label: {
                        SongRow(song: song, sortMetric: manager.sortMetric, rank: index + 1)
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
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct MonthlyDetailSongsSection: View {
    let title: String
    let subtitle: String
    let songs: [MonthlyRecap.RankedSong]
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext

    private var visibleSongs: [MonthlyRecap.RankedSong] {
        Array(songs.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 12) {
                ForEach(visibleSongs) { song in
                    if let topSong = resolvedSong(for: song) {
                        NavigationLink {
                            SongInfoView(song: topSong, manager: manager, recapContext: recapContext)
                        } label: {
                            MonthlyDetailSongDeltaRow(song: song)
                        }
                        .buttonStyle(.plain)
                    } else {
                        MonthlyDetailSongDeltaRow(song: song)
                    }
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
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private func resolvedSong(for song: MonthlyRecap.RankedSong) -> TopSong? {
        let allSongs = manager.librarySongs + manager.topSongs
        return allSongs.first { $0.id == song.id }
            ?? allSongs.first {
                $0.title.recapDetailMatchKey == song.title.recapDetailMatchKey &&
                    $0.artist.recapDetailMatchKey == song.artist.recapDetailMatchKey
            }
    }
}

private struct RecapDetailPeriodBreakdownSection: View {
    let title: String
    let summaries: [RecapPeriodSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            LazyVStack(spacing: 0) {
                ForEach(summaries) { summary in
                    RecapDetailPeriodBreakdownRow(summary: summary)

                    if summary.id != summaries.last?.id {
                        Divider()
                            .overlay(Color.primary.opacity(0.1))
                            .padding(.leading, 70)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct RecapDetailPeriodBreakdownRow: View {
    let summary: RecapPeriodSummary

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                artwork: summary.artwork,
                size: CGSize(width: 46, height: 46),
                cornerRadius: 9
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(summary.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(summary.listeningDuration.formattedListeningMinutes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 10)

            MetricBadge(text: "+\(summary.playDelta)")
        }
        .padding(.vertical, 10)
    }
}

private struct MonthlyDetailSongDeltaRow: View {
    let song: MonthlyRecap.RankedSong
    let subtitle: String?

    init(song: MonthlyRecap.RankedSong, subtitle: String? = nil) {
        self.song = song
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: 52, height: 52),
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle ?? song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(song.listeningDuration.formattedListeningMinutes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: "+\(song.playDelta)")
        }
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
        .scrollIndicators(.hidden)
        .navigationTitle("\(artist.name) Songs")
    }
}

private extension String {
    var recapDetailMatchKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
        .scrollIndicators(.hidden)
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

private enum MediaDetailFormatters {
    static let playCount: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = Locale.current.groupingSeparator
        return formatter
    }()
}

extension Int {
    var detailFormatted: String {
        MediaDetailFormatters.playCount.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

private extension TimeInterval {
    var formattedListenTime: String {
        formattedListeningMinutes
    }
}

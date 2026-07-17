import SwiftUI
import MediaPlayer
import UIKit

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
    @State private var showsNavigationTitle = false

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
    }

    private var artistCompanionSongs: [TopSong] {
        guard let artist else { return [] }
        return manager.songs(for: artist)
    }

    private var relatedColumns: [GridItem] {
        let count = isRegularWidth ? 2 : 1
        return Array(repeating: GridItem(.flexible(minimum: 280), spacing: 16, alignment: .top), count: count)
    }

    private static let relatedSongLimit = 6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                SongDetailHeader(song: song, album: album, artist: artist, manager: manager, recapContext: recapContext)
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
            .padding(.top, isRegularWidth ? 28 : 12)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: isRegularWidth ? 1080 : .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 260
        } action: { _, shouldShowTitle in
            guard showsNavigationTitle != shouldShowTitle else { return }
            showsNavigationTitle = shouldShowTitle
        }
        .background(MediaDetailBackground(artwork: song.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(showsNavigationTitle ? song.title : "")
        .playCountSongEntityIdentifier(song)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var bottomPadding: CGFloat {
        reservesBottomAccessorySpace ? (isRegularWidth ? 132 : 148) : 48
    }

    @ViewBuilder
    private var relatedSongSections: some View {
        if !albumCompanionSongs.isEmpty || !artistCompanionSongs.isEmpty {
            LazyVGrid(columns: relatedColumns, alignment: .leading, spacing: 16) {
                if !albumCompanionSongs.isEmpty {
                    RelatedSongsSection(title: "On This Album", songs: albumCompanionSongs, manager: manager, currentSongID: song.id, displayLimit: Self.relatedSongLimit, recapContext: recapContext)
                }

                if !artistCompanionSongs.isEmpty {
                    RelatedSongsSection(title: "More by \(song.artist)", songs: artistCompanionSongs, manager: manager, currentSongID: song.id, displayLimit: Self.relatedSongLimit, recapContext: recapContext)
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
    @State private var showsNavigationTitle = false

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
        sortedSongs(manager.songs(for: album), by: manager.sortMetric)
    }

    private var monthlySongs: [MonthlyRecap.RankedSong] {
        recapContext?.songs(for: album) ?? []
    }

    private var topAlbumSongs: [TopSong] {
        albumSongs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isRegularWidth ? 32 : 24) {
                AlbumDetailHeader(album: album, artist: artist, manager: manager, recapContext: recapContext)
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

                if !topAlbumSongs.isEmpty {
                    RelatedSongsSection(title: "Top Songs on This Album", songs: topAlbumSongs, manager: manager, sortMetric: manager.sortMetric, displayLimit: 6, recapContext: recapContext)
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
                                    SongInfoView(song: song, manager: manager, recapContext: recapContext)
                                } label: {
                                    AlbumTrackRow(song: song, sortMetric: manager.sortMetric)
                                }
                                .buttonStyle(.plain)

                                if song.id != albumSongs.last?.id {
                                    Divider()
                                        .overlay(Color.primary.opacity(0.1))
                                }
                            }
                        }
                        .playCountDetailCardSurface(cornerRadius: 20)
                    }
                }
            }
            .padding(.horizontal, isRegularWidth ? 36 : 24)
            .padding(.top, isRegularWidth ? 28 : 12)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: isRegularWidth ? 1080 : .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 260
        } action: { _, shouldShowTitle in
            guard showsNavigationTitle != shouldShowTitle else { return }
            showsNavigationTitle = shouldShowTitle
        }
        .background(MediaDetailBackground(artwork: album.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(showsNavigationTitle ? album.title : "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                detailMetricPicker
            }
        }
        .playCountAlbumEntityIdentifier(album)
    }

    private var detailMetricPicker: some View {
        LibraryMetricPicker(selection: $manager.sortMetric)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var bottomPadding: CGFloat {
        reservesBottomAccessorySpace ? (isRegularWidth ? 132 : 148) : 48
    }
}

struct ArtistInfoView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext?
    let reservesBottomAccessorySpace: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsNavigationTitle = false

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
        let songs = sortedSongs(manager.songs(for: artist), by: manager.sortMetric)
        let albums = sortedAlbums(manager.albums(for: artist), by: manager.sortMetric)
        let topSongs = Array(songs.prefix(displayLimit))
        let topAlbums = Array(albums.prefix(displayLimit))
        let monthlySongs = recapContext?.songs(for: artist) ?? []

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: isRegularWidth ? 32 : 24) {
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
                                    ArtistSongsListView(artist: artist, manager: manager, sortMetric: manager.sortMetric, recapContext: recapContext)
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
                                ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                                    NavigationLink {
                                        SongInfoView(song: song, manager: manager, recapContext: recapContext)
                                    } label: {
                                        SongRow(song: song, sortMetric: manager.sortMetric, rank: index + 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .playCountDetailCardSurface(cornerRadius: 20)
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
                                    ArtistAlbumsListView(artist: artist, manager: manager, sortMetric: manager.sortMetric, recapContext: recapContext)
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
                                ForEach(Array(topAlbums.enumerated()), id: \.element.id) { index, album in
                                    NavigationLink {
                                        AlbumInfoView(album: album, manager: manager, recapContext: recapContext)
                                    } label: {
                                        AlbumRow(album: album, sortMetric: manager.sortMetric, rank: index + 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .playCountDetailCardSurface(cornerRadius: 20)
                        }
                    }
                }
                .padding(.horizontal, isRegularWidth ? 36 : 24)
                .padding(.top, isRegularWidth ? 28 : 12)
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
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 260
        } action: { _, shouldShowTitle in
            guard showsNavigationTitle != shouldShowTitle else { return }
            showsNavigationTitle = shouldShowTitle
        }
        .background(MediaDetailBackground(artwork: artist.artwork))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(showsNavigationTitle ? artist.name : "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                detailMetricPicker
            }
        }
        .playCountArtistEntityIdentifier(artist)
    }

    private var detailMetricPicker: some View {
        LibraryMetricPicker(selection: $manager.sortMetric)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var bottomPadding: CGFloat {
        reservesBottomAccessorySpace ? (isRegularWidth ? 132 : 148) : 48
    }
}

private struct SongDetailHeader: View {
    let song: TopSong
    let album: TopAlbum?
    let artist: TopArtist?
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var identityTitleSize: CGFloat = 24

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
        if isRegularWidth { return 320 }
        return dynamicTypeSize.isAccessibilitySize ? 272 : 320
    }

    var body: some View {
        MediaDetailHeaderGroup {
            if isRegularWidth {
                HStack(alignment: .center, spacing: 28) {
                    heroArtwork
                        .frame(width: artworkSize)

                    VStack(spacing: 14) {
                        identity
                        playbackButton
                        metrics
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 14) {
                    heroArtwork
                    identity
                    playbackButton
                    metrics
                }
            } else {
                VStack(spacing: 14) {
                    heroArtwork
                        .frame(width: artworkSize)
                    identity
                    playbackButton
                    metrics
                }
            }
        }
    }

    private var heroArtwork: some View {
        MediaDetailResponsiveHero(maximumSize: artworkSize) { resolvedSize in
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: resolvedSize, height: resolvedSize),
                cornerRadius: isRegularWidth ? 22 : 24
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        }
    }

    private var identity: some View {
        VStack(spacing: 5) {
            Text(song.title)
                .font(.system(size: identityTitleSize, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

            artistLink
            albumLink
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var playbackButton: some View {
        MediaDetailPlaybackButton(
            title: playButtonTitle,
            systemImage: playButtonIcon,
            action: handlePlayTapped
        )
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            MediaDetailMetric(
                title: "Plays",
                value: song.playCount.detailFormatted,
                subtitle: manager.playCountRank(of: song).map { "Ranked #\($0)" }
            )

            Divider()
                .frame(height: 34)

            MediaDetailMetric(
                title: "Time Listened",
                value: song.totalPlayDuration.formattedListenTime,
                subtitle: manager.listenTimeRank(of: song).map { "Ranked #\($0)" }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .playCountDetailCardSurface(cornerRadius: 18)
    }

    @ViewBuilder
    private var albumLink: some View {
        if let album {
            NavigationLink {
                AlbumInfoView(album: album, manager: manager, recapContext: recapContext)
            } label: {
                Text(album.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        } else if !song.albumTitle.isEmpty {
            Text(song.albumTitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
        }
    }

    @ViewBuilder
    private var artistLink: some View {
        if let artist {
            NavigationLink {
                ArtistInfoView(artist: artist, manager: manager, recapContext: recapContext)
            } label: {
                Text(artist.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        } else if !song.artist.isEmpty {
            Text(song.artist)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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
    let recapContext: RecapDrilldownContext?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var identityTitleSize: CGFloat = 24

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
        if isRegularWidth { return 320 }
        return dynamicTypeSize.isAccessibilitySize ? 272 : 320
    }

    var body: some View {
        MediaDetailHeaderGroup {
            if !isRegularWidth {
                VStack(spacing: 14) {
                    heroArtwork
                    identity
                    playbackButton
                    metricsStrip
                }
            } else {
                HStack(alignment: .center, spacing: isRegularWidth ? 28 : 16) {
                    heroArtwork
                        .frame(width: artworkSize)

                    VStack(spacing: 14) {
                        identity
                        playbackButton
                        metricsStrip
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var heroArtwork: some View {
        MediaDetailResponsiveHero(maximumSize: artworkSize) { resolvedSize in
            ArtworkView(
                artwork: album.artwork,
                size: CGSize(width: resolvedSize, height: resolvedSize),
                cornerRadius: isRegularWidth ? 22 : 24
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        }
    }

    private var identity: some View {
        VStack(spacing: 5) {
            Text(album.title)
                .font(.system(size: identityTitleSize, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

            artistLink
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var playbackButton: some View {
        MediaDetailPlaybackButton(
            title: playButtonTitle,
            systemImage: playButtonIcon,
            action: handlePlayTapped
        )
    }

    private var metricsStrip: some View {
        metrics
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .playCountDetailCardSurface(cornerRadius: 18)
    }

    private var metrics: some View {
        MediaDetailPrimaryMetric(
            sortMetric: manager.sortMetric,
            playCount: album.playCount,
            duration: album.totalPlayDuration,
            playCountRank: manager.playCountRank(of: album),
            listenTimeRank: manager.listenTimeRank(of: album)
        )
    }

    @ViewBuilder
    private var artistLink: some View {
        if let artist {
            NavigationLink {
                ArtistInfoView(artist: artist, manager: manager, recapContext: recapContext)
            } label: {
                Text(artist.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        } else if !album.artist.isEmpty {
            Text(album.artist)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var identityTitleSize: CGFloat = 26

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
        if isRegularWidth { return 320 }
        return dynamicTypeSize.isAccessibilitySize ? 260 : 304
    }

    var body: some View {
        MediaDetailHeaderGroup {
            if !isRegularWidth {
                VStack(spacing: 14) {
                    heroArtwork
                    identity
                    playbackButton
                    metricsStrip
                }
            } else {
                HStack(alignment: .center, spacing: isRegularWidth ? 28 : 16) {
                    heroArtwork
                        .frame(width: artworkSize)

                    VStack(spacing: 14) {
                        identity
                        playbackButton
                        metricsStrip
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var heroArtwork: some View {
        MediaDetailResponsiveHero(maximumSize: artworkSize) { resolvedSize in
            ArtistArtworkView(
                artwork: artist.artwork,
                name: artist.name,
                diameter: resolvedSize
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        }
    }

    private var identity: some View {
        VStack(spacing: 5) {
            Text(artist.name)
                .font(.system(size: identityTitleSize, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var playbackButton: some View {
        MediaDetailPlaybackButton(
            title: playButtonTitle,
            systemImage: playButtonIcon,
            action: handlePlayTapped
        )
    }

    private var metricsStrip: some View {
        metrics
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .playCountDetailCardSurface(cornerRadius: 18)
    }

    private var metrics: some View {
        MediaDetailPrimaryMetric(
            sortMetric: manager.sortMetric,
            playCount: artist.playCount,
            duration: artist.totalPlayDuration,
            playCountRank: manager.playCountRank(of: artist),
            listenTimeRank: manager.listenTimeRank(of: artist)
        )
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, value: String, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct MediaDetailPlaybackButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(minWidth: 132)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .modifier(MediaDetailPlaybackSurfaceModifier())
    }
}

private struct MediaDetailPlaybackSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                }
        }
    }
}

private struct MediaDetailPrimaryMetric: View {
    let sortMetric: MediaLibraryManager.SortMetric
    let playCount: Int
    let duration: TimeInterval
    let playCountRank: Int?
    let listenTimeRank: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var value: String {
        sortMetric.badgeText(playCount: playCount, duration: duration)
    }

    private var title: String {
        sortMetric.toolbarLabel
    }

    private var supportingText: String {
        sortMetric.supplementaryDescription(playCount: playCount, duration: duration)
    }

    private var rank: Int? {
        switch sortMetric {
        case .playCount:
            return playCountRank
        case .listenTime:
            return listenTimeRank
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    metricValue
                    metricDescription
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    metricValue
                    metricDescription
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricValue: some View {
        Text(value)
            .font(.system(size: 25, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }

    private var metricDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .lineLimit(1)

            Text(rank.map { "\(supportingText) • Ranked #\($0)" } ?? supportingText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediaDetailHeaderGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                content
            }
        } else {
            content
        }
    }
}

private struct MediaDetailResponsiveHero<Content: View>: View {
    let maximumSize: CGFloat
    private let content: (CGFloat) -> Content

    init(maximumSize: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.maximumSize = maximumSize
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedSize = max(1, min(maximumSize, proxy.size.width, proxy.size.height))

            content(resolvedSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: maximumSize)
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension View {
    func playCountDetailCardSurface(cornerRadius: CGFloat) -> some View {
        modifier(MediaDetailCardSurfaceModifier(cornerRadius: cornerRadius))
    }
}

private struct MediaDetailCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
        }
    }
}

private struct AlbumTrackRow: View {
    let song: TopSong
    let sortMetric: MediaLibraryManager.SortMetric

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

                Text(sortMetric.supplementaryDescription(playCount: song.playCount, duration: song.totalPlayDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            MetricBadge(text: sortMetric.badgeText(playCount: song.playCount, duration: song.totalPlayDuration))
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
                .playCountDetailCardSurface(cornerRadius: 20)
        }
    }
}

private struct RelatedSongsSection: View {
    let title: String
    let songs: [TopSong]
    @ObservedObject var manager: MediaLibraryManager
    let sortMetric: MediaLibraryManager.SortMetric
    let currentSongID: UInt64?
    let displayLimit: Int?
    let recapContext: RecapDrilldownContext?

    private struct RankedSong: Identifiable {
        let rank: Int
        let song: TopSong

        var id: UInt64 { song.id }
    }

    init(
        title: String,
        songs: [TopSong],
        manager: MediaLibraryManager,
        sortMetric: MediaLibraryManager.SortMetric? = nil,
        currentSongID: UInt64? = nil,
        displayLimit: Int? = nil,
        recapContext: RecapDrilldownContext? = nil
    ) {
        self.title = title
        self.songs = songs
        self.manager = manager
        self.sortMetric = sortMetric ?? manager.sortMetric
        self.currentSongID = currentSongID
        self.displayLimit = displayLimit
        self.recapContext = recapContext
    }

    private var visibleSongs: [RankedSong] {
        let rankedSongs = Array(songs.enumerated()).map { RankedSong(rank: $0.offset + 1, song: $0.element) }
        guard let displayLimit, rankedSongs.count > displayLimit else {
            return rankedSongs
        }

        var visibleSongs = Array(rankedSongs.prefix(displayLimit))
        if let currentSongID,
           !visibleSongs.contains(where: { $0.song.id == currentSongID }),
           let currentSong = rankedSongs.first(where: { $0.song.id == currentSongID }),
           displayLimit > 1 {
            visibleSongs = Array(rankedSongs.prefix(displayLimit - 1)) + [currentSong]
        }
        return visibleSongs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            LazyVStack(spacing: 12) {
                ForEach(visibleSongs) { rankedSong in
                    let resolvedSong = resolvedSong(for: rankedSong.song)
                    let rank = rankedSong.rank
                    if rankedSong.song.id == currentSongID {
                        currentSongRow(song: resolvedSong, rank: rank)
                    } else {
                        NavigationLink {
                            SongInfoView(song: resolvedSong, manager: manager, recapContext: recapContext)
                        } label: {
                            SongRow(song: resolvedSong, sortMetric: sortMetric, rank: rank)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .playCountDetailCardSurface(cornerRadius: 20)
        }
    }

    private func resolvedSong(for song: TopSong) -> TopSong {
        manager.song(withPersistentID: song.id)
            ?? manager.song(matchingTitle: song.title, artist: song.artist)
            ?? song
    }

    private func currentSongRow(song: TopSong, rank: Int) -> some View {
        MediaListRow(
            rank: rank,
            title: song.title,
            subtitle: "This song",
            detail: sortMetric.supplementaryDescription(playCount: song.playCount, duration: song.totalPlayDuration),
            badgeText: sortMetric.badgeText(playCount: song.playCount, duration: song.totalPlayDuration),
            subtitleProminent: true
        ) {
            ArtworkView(artwork: song.artwork)
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if songs.count > visibleSongs.count {
                    NavigationLink {
                        MonthlyDetailSongsListView(
                            title: title,
                            songs: songs,
                            manager: manager,
                            recapContext: recapContext
                        )
                    } label: {
                        Text("See All")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
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
            .playCountDetailCardSurface(cornerRadius: 20)
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

private struct MonthlyDetailSongsListView: View {
    let title: String
    let songs: [MonthlyRecap.RankedSong]
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext

    var body: some View {
        List {
            ForEach(songs) { song in
                if let topSong = resolvedSong(for: song) {
                    NavigationLink {
                        SongInfoView(song: topSong, manager: manager, recapContext: recapContext)
                    } label: {
                        MonthlyDetailSongDeltaRow(song: song)
                    }
                } else {
                    MonthlyDetailSongDeltaRow(song: song)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(title)
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
            .playCountDetailCardSurface(cornerRadius: 20)
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: "+\(song.playDelta)")
        }
    }
}

private struct ArtistSongsListView: View {
    let artist: TopArtist
    @ObservedObject var manager: MediaLibraryManager
    let sortMetric: MediaLibraryManager.SortMetric
    let recapContext: RecapDrilldownContext?

    private var songs: [TopSong] {
        sortedSongs(manager.songs(for: artist), by: sortMetric)
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
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    NavigationLink {
                        SongInfoView(song: song, manager: manager, recapContext: recapContext)
                    } label: {
                        SongRow(song: song, sortMetric: sortMetric, rank: index + 1)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("\(artist.name) Songs")
    }
}

private func sortedSongs(_ songs: [TopSong], by metric: MediaLibraryManager.SortMetric) -> [TopSong] {
    songs.sorted { lhs, rhs in
        switch metric {
        case .playCount:
            if lhs.playCount != rhs.playCount {
                return lhs.playCount > rhs.playCount
            }
            if lhs.totalPlayDuration != rhs.totalPlayDuration {
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
        case .listenTime:
            if lhs.totalPlayDuration != rhs.totalPlayDuration {
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
            if lhs.playCount != rhs.playCount {
                return lhs.playCount > rhs.playCount
            }
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private func sortedAlbums(_ albums: [TopAlbum], by metric: MediaLibraryManager.SortMetric) -> [TopAlbum] {
    albums.sorted { lhs, rhs in
        switch metric {
        case .playCount:
            if lhs.playCount != rhs.playCount {
                return lhs.playCount > rhs.playCount
            }
            if lhs.totalPlayDuration != rhs.totalPlayDuration {
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
        case .listenTime:
            if lhs.totalPlayDuration != rhs.totalPlayDuration {
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
            if lhs.playCount != rhs.playCount {
                return lhs.playCount > rhs.playCount
            }
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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
    let sortMetric: MediaLibraryManager.SortMetric
    let recapContext: RecapDrilldownContext?

    private var albums: [TopAlbum] {
        sortedAlbums(manager.albums(for: artist), by: sortMetric)
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
                ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                    NavigationLink {
                        AlbumInfoView(album: album, manager: manager, recapContext: recapContext)
                    } label: {
                        AlbumRow(album: album, sortMetric: sortMetric, rank: index + 1)
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
    @Environment(\.colorScheme) private var colorScheme

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

            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(colorScheme == .dark ? 0.08 : 0.02),
                    Color(.systemBackground).opacity(colorScheme == .dark ? 0.2 : 0.12),
                    Color(.systemBackground).opacity(colorScheme == .dark ? 0.42 : 0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color]? {
        guard let components = artwork?.averageColorComponents() else {
            return nil
        }

        let start = adjustedColor(components, darkening: colorScheme == .dark ? 0.42 : 0.1)
        let mid = adjustedColor(components, darkening: colorScheme == .dark ? 0.2 : -0.08)
        let end = adjustedColor(components, darkening: colorScheme == .dark ? 0.5 : -0.18)

        return [start, mid, end]
    }

    private func adjustedColor(
        _ components: (Double, Double, Double),
        darkening amount: Double
    ) -> Color {
        Color(
            red: adjust(components.0, darkening: amount),
            green: adjust(components.1, darkening: amount),
            blue: adjust(components.2, darkening: amount)
        )
    }

    private func adjust(_ component: Double, darkening amount: Double) -> Double {
        if amount >= 0 {
            return darken(component, amount: amount)
        }
        return boost(component, amount: -amount)
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

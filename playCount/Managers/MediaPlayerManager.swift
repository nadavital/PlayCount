//
//  MediaPlayerManager.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//


import Foundation
import MediaPlayer
import SwiftUI

@MainActor
class MediaPlayerManager: ObservableObject {
    @Published var topSongs: [MPMediaItem] = []
    @Published var topAlbums: [MPMediaItemCollection] = []
    @Published var topArtists: [MPMediaItemCollection] = []
    @Published var errorMessage: String?
    @Published var nowPlayingItem: MPMediaItem?
    @Published var playbackState: MPMusicPlaybackState = .stopped

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var nowPlayingObserver: NSObjectProtocol?
    private var playbackStateObserver: NSObjectProtocol?

    // Caching flags
    private var didLoadMediaData = false
    // Cache for aggregated counts to avoid recalculation on simple refreshes if desired
    // For now, we recalculate on each full refresh.
    // private var cachedAlbumCounts: [UInt64: Int]?
    // private var cachedArtistCounts: [UInt64: Int]?

    /// Initializes the media player manager and triggers data fetching.
    init() {
        Task {
            await loadMediaDataIfNeeded()
            await MainActor.run {
                setupNowPlayingObservers()
                updateNowPlayingInfo()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // Only fetch if not already loaded
    private func loadMediaDataIfNeeded() async {
        guard !didLoadMediaData else { return }
        didLoadMediaData = true
        await fetchAllMediaData()
    }

    // Manual refresh method
    func refreshMediaData() async {
        // Reset cache/flags if implementing caching later
        // cachedAlbumCounts = nil
        // cachedArtistCounts = nil
        didLoadMediaData = false // Force reload
        await fetchAllMediaData()
    }

    // Refactored fetching strategy
    private func fetchAllMediaData() async {
        // 1. Fetch all songs efficiently
        let allSongs = await fetchAllSongsWithPlayCounts()
        guard !allSongs.isEmpty else {
            await MainActor.run {
                self.errorMessage = "No songs found in the library."
                self.topSongs = []
                self.topAlbums = []
                self.topArtists = []
            }
            return
        }

        // 2. Calculate aggregated counts from songs
        let (albumCounts, artistCounts) = calculateAggregatedCounts(songs: allSongs)

        // 3. Fetch specific lists using aggregated data
        await withTaskGroup(of: Void.self) { group in
            // Pass allSongs directly to fetchTopSongs
            group.addTask { await self.fetchTopSongs(songs: allSongs) }
            // Pass aggregated counts to fetchTopAlbums/Artists
            group.addTask { await self.fetchTopAlbums(albumCounts: albumCounts) }
            group.addTask { await self.fetchTopArtists(artistCounts: artistCounts) }
        }
    }

    /// Fetches all songs with play counts > 0.
    private func fetchAllSongsWithPlayCounts() async -> [MPMediaItem] {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        // Fetch all items, filter locally for play count > 0
        let items = query.items?.filter { $0.playCount > 0 } ?? []
        return items
    }

    /// Calculates total play counts per album and artist from a list of songs.
    private func calculateAggregatedCounts(songs: [MPMediaItem]) -> (albumCounts: [UInt64: Int], artistCounts: [UInt64: Int]) {
        var albumCounts: [UInt64: Int] = [:]
        var artistCounts: [UInt64: Int] = [:]

        for song in songs {
            // Aggregate Album Counts
            let albumId = song.albumPersistentID
            if albumId != 0 { // Ensure valid ID
                albumCounts[albumId, default: 0] += song.playCount
            }

            // Aggregate Artist Counts
            let artistId = song.artistPersistentID
            if artistId != 0 { // Ensure valid ID
                artistCounts[artistId, default: 0] += song.playCount
            }
        }
        return (albumCounts, artistCounts)
    }


    /// Fetches top songs from a pre-fetched list, sorted by play count.
    private func fetchTopSongs(songs: [MPMediaItem]) async {
        // Songs are already filtered for playCount > 0 in fetchAllSongsWithPlayCounts
        let sortedItems = songs.sorted { $0.playCount > $1.playCount }
        let topItems = sortedItems // Removed limit

        await MainActor.run {
            self.topSongs = topItems
            if topItems.isEmpty && !songs.isEmpty {
                 self.errorMessage = "No songs with play counts found."
            } else if topItems.isEmpty {
                 self.errorMessage = "Library might be empty or no songs have play counts."
            }
        }
    }

    /// Fetches top albums using pre-calculated play counts.
    private func fetchTopAlbums(albumCounts: [UInt64: Int]) async {
        guard !albumCounts.isEmpty else {
            await MainActor.run {
                self.topAlbums = []
                self.errorMessage = "No albums with play counts found."
            }
            return
        }

        let query = MPMediaQuery.albums()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .album // Keep grouping for correct collection fetching

        // Filter collections based on pre-calculated counts
        let collections = query.collections?.filter { albumCounts[$0.representativeItem?.albumPersistentID ?? 0] ?? 0 > 0 } ?? []

        // Sort using the pre-calculated counts
        let sortedCollections = collections.sorted {
            let firstPlays = albumCounts[$0.representativeItem?.albumPersistentID ?? 0] ?? 0
            let secondPlays = albumCounts[$1.representativeItem?.albumPersistentID ?? 0] ?? 0
            return firstPlays > secondPlays
        }
        let topCollections = sortedCollections // Removed limit

        await MainActor.run {
            self.topAlbums = topCollections
            if topCollections.isEmpty && !collections.isEmpty {
                self.errorMessage = "No albums with play counts found."
            } else if topCollections.isEmpty {
                 self.errorMessage = "Library might be empty or no albums have play counts."
            }
        }
    }

    /// Fetches top artists using pre-calculated play counts.
    private func fetchTopArtists(artistCounts: [UInt64: Int]) async {
         guard !artistCounts.isEmpty else {
            await MainActor.run {
                self.topArtists = []
                self.errorMessage = "No artists with play counts found."
            }
            return
        }

        let query = MPMediaQuery.artists()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .artist // Keep grouping for correct collection fetching

        // Filter collections based on pre-calculated counts
        let collections = query.collections?.filter { artistCounts[$0.representativeItem?.artistPersistentID ?? 0] ?? 0 > 0 } ?? []

        // Sort using the pre-calculated counts
        let sortedCollections = collections.sorted {
            let firstPlays = artistCounts[$0.representativeItem?.artistPersistentID ?? 0] ?? 0
            let secondPlays = artistCounts[$1.representativeItem?.artistPersistentID ?? 0] ?? 0
            return firstPlays > secondPlays
        }
         let topCollections = sortedCollections // Removed limit

        await MainActor.run {
            self.topArtists = topCollections
            if topCollections.isEmpty && !collections.isEmpty {
                self.errorMessage = "No artists with play counts found."
            } else if topCollections.isEmpty {
                 self.errorMessage = "Library might be empty or no artists have play counts."
            }
        }
    }

    private func setupNowPlayingObservers() {
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
        NotificationCenter.default.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
        player.beginGeneratingPlaybackNotifications()
    }

    private func updateNowPlayingInfo() {
        nowPlayingItem = player.nowPlayingItem
        playbackState = player.playbackState
    }

    // Playback controls
    func play() {
        player.play()
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        updateNowPlayingInfo()
    }

    func next() {
        player.skipToNextItem()
        updateNowPlayingInfo()
    }

    func previous() {
        player.skipToPreviousItem()
        updateNowPlayingInfo()
    }

    func play(item: MPMediaItem) {
        let collection = MPMediaItemCollection(items: [item])
        player.setQueue(with: collection)
        player.nowPlayingItem = item
        player.play()
        updateNowPlayingInfo()
    }

    func play(collection: MPMediaItemCollection) {
        player.setQueue(with: collection)
        player.play()
        updateNowPlayingInfo()
    }
}

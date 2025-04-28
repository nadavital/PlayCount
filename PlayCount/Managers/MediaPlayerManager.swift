//
//  MediaPlayerManager.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import Foundation
import MediaPlayer
import SwiftUI
import os.log
import UIKit

@MainActor
class MediaPlayerManager: ObservableObject {
    @Published var topSongs: [MPMediaItem] = []
    @Published var topAlbums: [MPMediaItemCollection] = []
    @Published var topArtists: [MPMediaItemCollection] = []
    @Published var errorMessage: String?
    @Published var nowPlayingItem: MPMediaItem?
    @Published var playbackState: MPMusicPlaybackState = .stopped
    
    private let player = MPMusicPlayerController.systemMusicPlayer
    private let logger = Logger(subsystem: "com.Nadav.playCount", category: "MediaPlayerManager")
    
    init() {
        fetchTopSongs()
        fetchTopAlbums()
        fetchTopArtists()
        if topSongs.isEmpty && topAlbums.isEmpty && topArtists.isEmpty {
            errorMessage = "Library might be empty."
        } else {
            setupNowPlayingObservers()
            updateNowPlayingInfo()
        }
    }
    
    func refreshMediaData() {
        fetchTopSongs()
        fetchTopAlbums()
        fetchTopArtists()
    }
    
    private func fetchTopSongs() {
        logger.info("Starting song fetch")
        let start = Date()
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        if let items = query.items?.filter({ $0.playCount > 0 }).sorted(by: { $0.playCount > $1.playCount }) {
            topSongs = items
            logger.info("Fetched \(items.count) songs in \(Date().timeIntervalSince(start)) seconds")
        } else {
            errorMessage = "No songs with play counts found."
            logger.error("Failed to fetch songs")
        }
    }
    
    private func fetchTopAlbums() {
        logger.info("Starting album fetch")
        let start = Date()
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .album
        if let collections = query.collections?.filter({ collection in
            collection.items.contains(where: { $0.playCount > 0 })
        }).sorted(by: { firstCollection, secondCollection in
            let firstTotalPlays = firstCollection.items.reduce(0) { $0 + $1.playCount }
            let secondTotalPlays = secondCollection.items.reduce(0) { $0 + $1.playCount }
            return firstTotalPlays > secondTotalPlays
        }) {
            topAlbums = collections
            logger.info("Fetched \(collections.count) albums in \(Date().timeIntervalSince(start)) seconds")
        } else {
            errorMessage = "No albums with play counts found."
            logger.error("Failed to fetch albums")
        }
    }
    
    private func fetchTopArtists() {
        logger.info("Starting artist fetch")
        let start = Date()
        let query = MPMediaQuery.artists()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .artist
        if let collections = query.collections?.filter({ collection in
            collection.items.contains(where: { $0.playCount > 0 })
        }).sorted(by: { firstCollection, secondCollection in
            let firstTotalPlays = firstCollection.items.reduce(0) { $0 + $1.playCount }
            let secondTotalPlays = secondCollection.items.reduce(0) { $0 + $1.playCount }
            return firstTotalPlays > secondTotalPlays
        }) {
            topArtists = collections
            logger.info("Fetched \(collections.count) artists in \(Date().timeIntervalSince(start)) seconds")
        } else {
            errorMessage = "No artists with play counts found."
            logger.error("Failed to fetch artists")
        }
    }
    
    func logLibraryStats() {
        let songQuery = MPMediaQuery.songs()
        let albumQuery = MPMediaQuery.albums()
        let artistQuery = MPMediaQuery.artists()
        logger.info("Total songs: \(songQuery.items?.count ?? 0)")
        logger.info("Total albums: \(albumQuery.collections?.count ?? 0)")
        logger.info("Total artists: \(artistQuery.collections?.count ?? 0)")
        logger.info("Songs with playCount > 0: \(songQuery.items?.filter { $0.playCount > 0 }.count ?? 0)")
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

// MARK: - Gradient Artwork Helper
private extension MediaPlayerManager {
    private static func makeGradientImage(hue: CGFloat, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors = [UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0).cgColor,
                          UIColor(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 0.7, brightness: 0.8, alpha: 1.0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0,1])!
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }
}

#if DEBUG
// MARK: - Preview Mock Data

/// Fake MPMediaItem to simulate media properties
class FakeMediaItem: MPMediaItem {
    private let values: [String: Any]
    init(values: [String: Any]) {
        self.values = values
        super.init()
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func value(forProperty property: String) -> Any? {
        return values[property]
    }
    override var persistentID: MPMediaEntityPersistentID {
        return values[MPMediaItemPropertyPersistentID] as? MPMediaEntityPersistentID ?? super.persistentID
    }
    // Override key properties to ensure SwiftUI uses them
    override var title: String? {
        return values[MPMediaItemPropertyTitle] as? String
    }
    override var artist: String? {
        return values[MPMediaItemPropertyArtist] as? String
    }
    override var albumTitle: String? {
        return values[MPMediaItemPropertyAlbumTitle] as? String
    }
    override var albumArtist: String? {
        return values[MPMediaItemPropertyAlbumArtist] as? String
    }
    override var playCount: Int {
        return values[MPMediaItemPropertyPlayCount] as? Int ?? 0
    }
    override var playbackDuration: TimeInterval {
        return values[MPMediaItemPropertyPlaybackDuration] as? TimeInterval ?? 0
    }
    override var artwork: MPMediaItemArtwork? {
        return values[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
    }
}

@MainActor
extension MediaPlayerManager {
    /// A manager pre-populated with mock songs, albums, and artists for SwiftUI previews
    static var previewManager: MediaPlayerManager {
        let manager = MediaPlayerManager()
        manager.topSongs.removeAll()
        manager.topAlbums.removeAll()
        manager.topArtists.removeAll()
        manager.errorMessage = nil

        var fakeSongs: [FakeMediaItem] = []
        let artists = MockPreviewData.artistNames
        let albums = MockPreviewData.albumNames
        let titles = MockPreviewData.songTitles

        // Generate one album per artist, 5 songs per album
        for (artistIndex, artistName) in artists.enumerated() {
            let albumName = albums[artistIndex % albums.count]
            for trackNumber in 0..<5 {
                let titleIndex = (artistIndex * 5 + trackNumber) % titles.count
                let songTitle = titles[titleIndex]
                let playCount = Int.random(in: 50...200)
                let hue = CGFloat(artistIndex) / CGFloat(artists.count)
                let artworkImage = makeGradientImage(hue: hue, size: CGSize(width: 300, height: 300))
                let artwork = MPMediaItemArtwork(image: artworkImage)
                let values: [String: Any] = [
                    MPMediaItemPropertyTitle: songTitle,
                    MPMediaItemPropertyArtist: artistName,
                    MPMediaItemPropertyAlbumTitle: albumName,
                    MPMediaItemPropertyAlbumArtist: artistName,
                    MPMediaItemPropertyPersistentID: MPMediaEntityPersistentID(artistIndex * 10 + trackNumber),
                    MPMediaItemPropertyPlayCount: playCount,
                    MPMediaItemPropertyArtwork: artwork
                ]
                fakeSongs.append(FakeMediaItem(values: values))
            }
        }
        manager.topSongs = fakeSongs

        // Group into albums
        let albumsDict = Dictionary(grouping: fakeSongs) { item in
            item.value(forProperty: MPMediaItemPropertyAlbumTitle) as? String ?? ""
        }
        manager.topAlbums = albumsDict.keys.sorted().map { key in
            MPMediaItemCollection(items: albumsDict[key]!)
        }

        // Group into artists
        let artistsDict = Dictionary(grouping: fakeSongs) { item in
            item.value(forProperty: MPMediaItemPropertyArtist) as? String ?? ""
        }
        manager.topArtists = artistsDict.keys.sorted().map { key in
            MPMediaItemCollection(items: artistsDict[key]!)
        }

        return manager
    }
}
#endif
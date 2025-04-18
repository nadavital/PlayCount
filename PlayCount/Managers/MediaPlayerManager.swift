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
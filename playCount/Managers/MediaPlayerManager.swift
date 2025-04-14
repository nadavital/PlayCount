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
    
    /// Initializes the media player manager and triggers data fetching for songs, albums, and artists.
    init() {
        fetchTopSongs()
        fetchTopAlbums()
        fetchTopArtists()
    }
    
    /// Fetches top songs from the media library with non-zero play counts, sorted by play count.
    func fetchTopSongs() {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .title
        
        if let items = query.items?.filter({ $0.playCount > 0 }).sorted(by: { $0.playCount > $1.playCount }) {
            self.topSongs = items
        } else {
            self.errorMessage = "Failed to fetch top songs."
        }
    }

    /// Fetches top albums based on the total play count of their songs.
    func fetchTopAlbums() {
        let query = MPMediaQuery.albums()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .album
        
        if let collections = query.collections?.filter({ collection in
            return collection.items.contains(where: { $0.playCount > 0 })
        }).sorted(by: { firstCollection, secondCollection in
            let firstTotalPlays = firstCollection.items.reduce(0) { $0 + $1.playCount }
            let secondTotalPlays = secondCollection.items.reduce(0) { $0 + $1.playCount }
            return firstTotalPlays > secondTotalPlays
        }) {
            self.topAlbums = collections
        } else {
            self.errorMessage = "Failed to fetch top albums."
        }
    }

    /// Fetches top artists based on the total play count of their songs.
    func fetchTopArtists() {
        let query = MPMediaQuery.artists()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: MPMediaType.music.rawValue, forProperty: MPMediaItemPropertyMediaType))
        query.groupingType = .artist
        
        if let collections = query.collections?.filter({ collection in
            return collection.items.contains(where: { $0.playCount > 0 })
        }).sorted(by: { firstCollection, secondCollection in
            let firstTotalPlays = firstCollection.items.reduce(0) { $0 + $1.playCount }
            let secondTotalPlays = secondCollection.items.reduce(0) { $0 + $1.playCount }
            return firstTotalPlays > secondTotalPlays
        }) {
            self.topArtists = collections
        } else {
            self.errorMessage = "Failed to fetch top artists."
        }
    }
}

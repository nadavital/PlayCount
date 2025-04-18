//
//  SongModel.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import Foundation
import MediaPlayer

struct Song: Identifiable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let playCount: Int
    let persistentID: MPMediaEntityPersistentID
    let artwork: MPMediaItemArtwork?
    let mediaItem: MPMediaItem?

    // Initializer for use with actual media items
    init(mediaItem: MPMediaItem) {
        self.id = "\(mediaItem.persistentID)"
        self.title = mediaItem.title ?? "Unknown Title"
        self.artist = mediaItem.artist ?? "Unknown Artist"
        self.albumTitle = mediaItem.albumTitle ?? "Unknown Album"
        self.playCount = mediaItem.playCount
        self.persistentID = mediaItem.persistentID
        self.artwork = mediaItem.artwork
        self.mediaItem = mediaItem
    }

    // Preview initializer with default values
    init(
        id: String = UUID().uuidString,
        title: String = "Preview Song",
        artist: String = "Preview Artist",
        albumTitle: String = "Preview Album",
        playCount: Int = 42,
        persistentID: MPMediaEntityPersistentID = MPMediaEntityPersistentID(0),
        artwork: MPMediaItemArtwork? = nil,
        mediaItem: MPMediaItem? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.playCount = playCount
        self.persistentID = persistentID
        self.artwork = artwork
        self.mediaItem = mediaItem
    }

    // Static preview instance
    static let preview = Song()
}
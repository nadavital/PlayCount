// ...existing code...
import Foundation
import MediaPlayer

struct Album: Identifiable {
    let id: String
    let title: String
    let artist: String
    let playCount: Int
    let artwork: MPMediaItemArtwork?
    let persistentID: MPMediaEntityPersistentID
    let items: [MPMediaItem]

    init(collection: MPMediaItemCollection) {
        self.items = collection.items
        self.id = "\(collection.persistentID)"
        self.title = collection.representativeItem?.albumTitle ?? "Unknown Album"
        self.artist = collection.representativeItem?.albumArtist ?? "Unknown Artist"
        self.playCount = collection.items.reduce(0) { $0 + $1.playCount }
        self.artwork = collection.representativeItem?.artwork
        self.persistentID = collection.persistentID
    }

    // Preview initializer
    init(
        id: String = UUID().uuidString,
        title: String = "Preview Album",
        artist: String = "Preview Artist",
        playCount: Int = 42,
        artwork: MPMediaItemArtwork? = nil,
        persistentID: MPMediaEntityPersistentID = MPMediaEntityPersistentID(0),
        items: [MPMediaItem] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.playCount = playCount
        self.artwork = artwork
        self.persistentID = persistentID
        self.items = items
    }

    static let preview = Album()
}
// ...existing code...
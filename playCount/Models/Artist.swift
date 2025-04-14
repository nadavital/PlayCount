// ...existing code...
import Foundation
import MediaPlayer

struct Artist: Identifiable {
    let id: String
    let name: String
    let playCount: Int
    let artwork: MPMediaItemArtwork?
    let persistentID: MPMediaEntityPersistentID
    let items: [MPMediaItem]

    init(collection: MPMediaItemCollection) {
        self.items = collection.items
        self.id = "\(collection.persistentID)"
        self.name = collection.representativeItem?.artist ?? "Unknown Artist"
        self.playCount = collection.items.reduce(0) { $0 + $1.playCount }
        self.artwork = collection.representativeItem?.artwork
        self.persistentID = collection.persistentID
    }

    // Preview initializer
    init(
        id: String = UUID().uuidString,
        name: String = "Preview Artist",
        playCount: Int = 42,
        artwork: MPMediaItemArtwork? = nil,
        persistentID: MPMediaEntityPersistentID = MPMediaEntityPersistentID(0),
        items: [MPMediaItem] = []
    ) {
        self.id = id
        self.name = name
        self.playCount = playCount
        self.artwork = artwork
        self.persistentID = persistentID
        self.items = items
    }

    static let preview = Artist()
}
// ...existing code...
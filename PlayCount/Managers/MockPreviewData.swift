import Foundation
import UIKit

struct PreviewTrack {
    let title: String
    let artist: String
    let album: String
    let playCount: Int
}

enum MockPreviewData {
    static let artistNames: [String] = [
        "Auric Arc", "Lunar Drift", "Sonic Bloom", "Echo Forge", "Neon Harbor",
        "Solar Vale", "Velvet Spectrum", "Cobalt City", "Prism Veil", "Kinetic Realm",
        "Amber Wave", "Obsidian Sky", "Emerald Sound", "Crimson Circuit", "Phantom Neon",
        "Quantum Echo", "Spectral Glow", "Orbit Dance", "Celestial Tide", "Vortex Pulse"
    ]

    static let albumNames: [String] = [
        "Harmonic Dreams", "Radiant Visions", "Temporal Shift", "Infinite Echoes", "Chroma Fields",
        "Nebula Zone", "Fractal Waves", "Digital Canvas", "Luminous Path", "Broken Continuum",
        "Electric Vibes", "Static Motion", "Galactic Drift", "Pixel Gates", "Aurora Skies",
        "Quantum Realm", "Solar Nimbus", "Eclipse Pulse", "Virtual Horizon", "Mirage Symphony"
    ]

    static let songTitles: [String] = [
        "Silent Echo", "Crimson Moon", "Glass Horizon", "Neon Pulse", "Silver Lining",
        "Fading Light", "Golden Dreams", "Shadow Realm", "Broken Wings", "Midnight Rail",
        "Frosted Wings", "Echo Chambers", "Radiant Shine", "Whispered Secrets", "Digital Sunrise",
        "Lost Frequencies", "Velvet Nights", "Thunder Road", "Crashing Waves", "Distant Shores"
    ]
}

//
//  PlayCountAppIntents.swift
//  PlayCount
//
//  Created by Nadav Avital on 9/23/25.
//

import Foundation
import SwiftUI
import AppIntents


struct TopFiveSongsIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Get Top 5 Songs"
    
    static var description = IntentDescription("Shows your top 5 songs.")
    
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog & ShowsSnippetView {
        
        let topSongs = Array(manager.topSongs.prefix(5))
        let titles = topSongs.map(\.title)
        
        let snippet = TopFiveSongsView(songs: topSongs)
        
        let dialog = IntentDialog(full: "Your top five songs are \(titles.joined(separator: ", ")).",
                                  supporting: "Here are your top five songs.")
        
        return .result(value: titles, dialog: dialog, view: snippet)
    }
    
    @Dependency
    private var manager: MediaLibraryManager
}

struct CurrentSongPlayCountIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Get Current Song's Play Count"
    
    static var description = IntentDescription("Shows how many times you have listened to the current song.")
    
    func perform() async throws -> some IntentResult & ReturnsValue<Int?> & ProvidesDialog & ShowsSnippetView{
        let currentSong = manager.nowPlayingState
        let playCount = currentSong?.playCount ?? nil
        
        let snippet = SingleSongPlayCountView(song: currentSong)
        
        let dialog = IntentDialog(full: "You have listened to \(currentSong?.title ?? "Unknown") \(currentSong?.playCount ?? 0) times.",
                                  supporting: "\(currentSong?.playCount ?? 0) times.")
        
        return .result(value: playCount, dialog: dialog, view: snippet)
    }
    
    @Dependency
    private var manager: MediaLibraryManager
}

struct SearchPlayCountIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Find the Play Count of any Song"
    
    static var description = IntentDescription("Shows how many times you have listened to any requested song")
    
    @Parameter(title: "Song", description: "The song to get the PlayCount for")
    var songTitle: String
    @Dependency var manager: MediaLibraryManager
    
    func perform() async throws -> some IntentResult & ReturnsValue<String?> & ProvidesDialog & ShowsSnippetView {
        let song = manager.librarySongs.filter {
            $0.title.localizedCaseInsensitiveContains(songTitle) || $0.artist.localizedCaseInsensitiveContains(songTitle)
        }.first
                
        let snippet = PlainSongRow(song: song)
        
        let dialog = IntentDialog(full: "You have listened to \(song?.title ?? "Unknown Song") \(song?.playCount ?? 0) times.", supporting: "\(song?.playCount ?? 0) times.")
        
        return .result(value: song?.title, dialog: dialog, view: snippet)
    }
}

struct SingleSongPlayCountView: View {
    let song: MediaLibraryManager.NowPlayingState?
    
    var body: some View {
        HStack {
            ArtworkView(artwork: song?.artwork)
            
            Text(song?.title ?? "")
            
            Spacer(minLength: 12)
            
            Text(String(song?.playCount ?? 0))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(4)
    }
}

struct PlainSongRow: View {
    let song: TopSong?
    
    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(artwork: song?.artwork)
            
            VStack(alignment: .leading) {
                Text(song?.title ?? "Unknown Title")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(song?.artist ?? "Unknown Artist")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 12)
            
            Text(String(song?.playCount ?? 0))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(4)
    }
}


private struct TopFiveSongsView: View {
    let songs: [TopSong]
    var body: some View {
        VStack {
            ForEach(songs) { song in
                PlainSongRow(song: song)
            }
        }
    }
}

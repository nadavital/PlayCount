//
//  ContentView.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @State private var selectedSection: Section = .songs
    @State private var searchText = ""
    
    enum Section: String, CaseIterable, Identifiable {
        case songs = "Top Songs"
        case albums = "Top Albums"
        case artists = "Top Artists"
        var id: String { rawValue }
    }
    
    var searchPrompt: String {
        switch selectedSection {
        case .songs:
            return "Search Songs or Artists"
        case .albums:
            return "Search Albums or Artists"
        case .artists:
            return "Search Artists"
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch selectedSection {
                    case .songs:
                        TopSongsView(searchText: $searchText)
                    case .albums:
                        TopAlbumsView(searchText: $searchText)
                    case .artists:
                        TopArtistsView(searchText: $searchText)
                    }
                }
                Spacer(minLength: 0)
            }
            .searchable(text: $searchText, prompt: Text(searchPrompt))
            .overlay(
                VStack {
                    Spacer()
                    NowPlayingBar()
                        .environmentObject(topMusic)
                        .padding(.bottom, 8)
                }
            )
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(Section.allCases) { section in
                            Button(action: { selectedSection = section }) {
                                Text(section.rawValue)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedSection.rawValue)
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: Edge.Set.bottom)
    }
}

#Preview {
    ContentView()
        .environmentObject(MediaPlayerManager())
}

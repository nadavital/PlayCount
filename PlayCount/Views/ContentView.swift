//
//  ContentView.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI
import MediaPlayer

struct ContentView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @State private var selectedSection: Section = .songs
    @State private var searchText = ""
    @State private var isSearching = false // New state for search mode
    @State private var headerCollapsed = false
    
    enum Section: String, CaseIterable, Identifiable {
        case songs = "Top Songs"
        case albums = "Top Albums"
        case artists = "Top Artists"
        var id: String { rawValue }
        var iconName: String {
            switch self {
            case .songs:
                return "music.note"
            case .albums:
                return "square.stack"
            case .artists:
                return "music.microphone"
            }
        }
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
    
    var headerHeight: CGFloat { headerCollapsed ? 56 : 84 }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Scrollable content with offset tracking, padded to go under header
                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                    .frame(height: 0)
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
                    .padding(.top, headerHeight + (isSearching ? 56 : 0)) // Add space for search bar if visible
                    Spacer(minLength: 0)
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        headerCollapsed = value < -16
                    }
                }
                // Header overlay (blur + fading gradient + controls)
                GeometryReader { proxy in
                    let safeTop = proxy.safeAreaInsets.top
                    ZStack(alignment: .top) {
                        // Gradient blur background
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .mask(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .white, location: 0.0),
                                        .init(color: .white.opacity(0.7), location: 0.7),
                                        .init(color: .white.opacity(0.0), location: 1.0)
                                    ]),
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(height: headerHeight + safeTop + 36 + (isSearching ? 56 : 0))
                            .ignoresSafeArea(edges: .top)
                        VStack(spacing: 0) {
                            // Header content inside safe area
                            HStack(alignment: .center) {
                                Menu {
                                    ForEach(Section.allCases) { section in
                                        Button(action: { selectedSection = section }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: section.iconName)
                                                Text(section.rawValue)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedSection.rawValue)
                                            .font(headerCollapsed ? .title2.bold() : .largeTitle.bold())
                                            .foregroundColor(.primary)
                                            .scaleEffect(headerCollapsed ? 0.85 : 1.0)
                                            .animation(.easeInOut(duration: 0.2), value: headerCollapsed)
                                        Image(systemName: "chevron.down")
                                            .font(headerCollapsed ? .body : .title3)
                                            .foregroundColor(.secondary)
                                            .animation(.easeInOut(duration: 0.2), value: headerCollapsed)
                                    }
                                    .contentShape(Rectangle())
                                }
                                Spacer()
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if isSearching {
                                            searchText = ""
                                            isSearching = false
                                        } else {
                                            isSearching = true
                                        }
                                    }
                                }) {
                                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.primary)
                                        .padding(8)
                                        .background(Circle().fill(Color(.systemGray5).opacity(0.7)))
                                }
                                .animation(.easeInOut(duration: 0.2), value: isSearching)
                            }
                            .padding(.horizontal)
                            .padding(.top, headerCollapsed ? 2 : 18)
                            .padding(.bottom, headerCollapsed ? 2 : 8)
                            // Search bar below header
                            if isSearching {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                    TextField(searchPrompt, text: $searchText, onCommit: {})
                                        .textFieldStyle(.plain)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .frame(minWidth: 100)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color(.systemGray5).opacity(0.85)))
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                                .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 2)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.98, anchor: .top)),
                                                        removal: .move(edge: .top).combined(with: .opacity)))
                                .animation(.easeInOut(duration: 0.45), value: isSearching)
                            }
                        }
                        .frame(height: headerHeight + (isSearching ? 56 : 0))
                    }
                    .frame(height: headerHeight + safeTop + 12 + (isSearching ? 56 : 0))
                }
                .frame(height: headerHeight + 60 + (isSearching ? 56 : 0))
                .zIndex(1)
                .animation(.easeInOut(duration: 0.2), value: headerCollapsed)
                // NowPlayingBar overlay
                VStack {
                    Spacer()
                    NowPlayingBar()
                        .environmentObject(topMusic)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: Edge.Set.bottom)
    }
}

// Helper for scroll offset
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(MediaPlayerManager.previewManager)
}
#endif

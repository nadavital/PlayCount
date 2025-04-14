import SwiftUI

struct TopSongsView: View {
    @State private var searchText = ""
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    topSongsList(searchText: $searchText)
                        .padding(.horizontal)
                }
                .navigationTitle("Top Songs")
                .searchable(text: $searchText, prompt: "Search Songs or Artists")
            }
        }
    }
}

#Preview {
    TopSongsView()
        .environmentObject(MediaPlayerManager())
}

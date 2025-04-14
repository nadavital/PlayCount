import SwiftUI

struct TopArtistsView: View {
    @State private var searchText = ""
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    topArtistsList(searchText: $searchText)
                        .padding(.horizontal)
                }
                .navigationTitle("Top Artists")
                .searchable(text: $searchText, prompt: "Search Artists")
            }
        }
    }
}

#Preview {
    TopArtistsView()
        .environmentObject(MediaPlayerManager())
}

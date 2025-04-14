import SwiftUI

struct TopAlbumsView: View {
    @State private var searchText = ""
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    topAlbumsList(searchText: $searchText)
                        .padding(.horizontal)
                }
                .navigationTitle("Top Albums")
                .searchable(text: $searchText, prompt: "Search Albums or Artists")
            }
        }
    }
}

#Preview {
    TopAlbumsView()
        .environmentObject(MediaPlayerManager())
}

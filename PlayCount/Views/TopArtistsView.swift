import SwiftUI
import MediaPlayer

struct TopArtistsView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    var body: some View {
        VStack {
            if topMusic.topArtists.isEmpty && topMusic.errorMessage == nil {
                Spacer()
                ProgressView("Loading artists...")
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            } else if let error = topMusic.errorMessage {
                Spacer()
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    topArtistsList(searchText: $searchText)
                        .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TopArtistsView(searchText: .constant(""))
            .environmentObject(MediaPlayerManager.previewManager)
    }
}

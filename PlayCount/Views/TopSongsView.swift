import SwiftUI
import MediaPlayer

struct TopSongsView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    var body: some View {
        VStack {
            if topMusic.topSongs.isEmpty && topMusic.errorMessage == nil {
                Spacer()
                ProgressView("Loading songs...")
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
                    topSongsList(searchText: $searchText)
                        .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TopSongsView(searchText: .constant(""))
            .environmentObject(MediaPlayerManager.previewManager)
    }
}

import SwiftUI
import MediaPlayer

struct TopAlbumsView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    var body: some View {
        VStack {
            if topMusic.topAlbums.isEmpty && topMusic.errorMessage == nil {
                Spacer()
                ProgressView("Loading albums...")
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
                    topAlbumsList(searchText: $searchText)
                        .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TopAlbumsView(searchText: .constant(""))
            .environmentObject(MediaPlayerManager.previewManager)
    }
}

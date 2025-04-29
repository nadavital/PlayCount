import SwiftUI
import MediaPlayer

struct TopAlbumsView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    var body: some View {
        VStack {
            if topMusic.authorizationDenied {
                Spacer()
                Text("PlayCount needs access to your Apple Music library to display your top music.")
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Allow Access") {
                    topMusic.requestAuthorization()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 28)
                .background(.ultraThinMaterial, in: Capsule())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.top, 8)
                Spacer()
            } else if topMusic.topAlbums.isEmpty && topMusic.errorMessage == nil {
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

#if DEBUG
#Preview {
    NavigationStack {
        TopAlbumsView(searchText: .constant(""))
            .environmentObject(MediaPlayerManager.previewManager)
    }
}
#endif

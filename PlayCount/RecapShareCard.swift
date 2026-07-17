import CoreTransferable
@preconcurrency import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

struct RecapSharePayload: Transferable, @unchecked Sendable {
    let recap: MonthlyRecap
    let periodTitle: String
    let artwork: MPMediaItemArtwork?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            let image = await MainActor.run {
                RecapShareRenderer.image(
                    recap: payload.recap,
                    periodTitle: payload.periodTitle,
                    artwork: payload.artwork
                )
            }
            guard let image else { throw CocoaError(.fileWriteUnknown) }
            return try await Task.detached(priority: .userInitiated) {
                guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                return data
            }.value
        }
        .suggestedFileName("PlayCount Recap.png")
    }
}

@MainActor
enum RecapShareRenderer {
    static func image(
        recap: MonthlyRecap,
        periodTitle: String,
        artwork: MPMediaItemArtwork?
    ) -> UIImage? {
        let card = RecapShareCard(
            recap: recap,
            periodTitle: periodTitle,
            artwork: artwork
        )
        .frame(width: 390, height: 700)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct RecapShareCard: View {
    let recap: MonthlyRecap
    let periodTitle: String
    let artwork: MPMediaItemArtwork?

    private var topSong: MonthlyRecap.RankedSong? {
        recap.topSongs.first
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.08, blue: 0.22),
                    Color(red: 0.46, green: 0.18, blue: 0.38),
                    Color(red: 0.95, green: 0.48, blue: 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 330, height: 330)
                .blur(radius: 44)
                .offset(x: 150, y: -230)

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLAYCOUNT RECAP")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(periodTitle)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Image(systemName: "music.note.list")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.16), in: Circle())
                }

                if let topSong {
                    VStack(alignment: .leading, spacing: 14) {
                        ArtworkView(
                            artwork: artwork ?? topSong.artwork,
                            size: CGSize(width: 330, height: 330),
                            cornerRadius: 28
                        )

                        Text("MOST PLAYED")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(topSong.title)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(topSong.artist)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 0) {
                    shareMetric(value: recap.totalPlayDelta.formatted(), title: "PLAYS")
                    Divider().overlay(.white.opacity(0.2))
                    shareMetric(value: recap.totalListeningDuration.formattedListeningMinutes, title: "LISTENED")
                    Divider().overlay(.white.opacity(0.2))
                    shareMetric(value: recap.playedSongCount.formatted(), title: "SONGS")
                }
                .frame(height: 46)
            }
            .padding(30)
        }
        .clipShape(.rect(cornerRadius: 36))
    }

    private func shareMetric(value: String, title: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
    }
}

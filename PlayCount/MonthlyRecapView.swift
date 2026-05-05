import CoreImage.CIFilterBuiltins
import MediaPlayer
import SwiftUI

struct MonthlyRecapView: View {
    @ObservedObject var manager: MediaLibraryManager

    #if DEBUG
    @State private var reminderStatusMessage: String?
    #endif

    private var recap: MonthlyRecap {
        manager.monthlyRecap
    }

    private var artworkHighlights: [MPMediaItemArtwork] {
        let recapArtwork = recap.topSongs.compactMap(\.artwork)
        if !recapArtwork.isEmpty {
            return Array(recapArtwork.prefix(4))
        }

        return Array(manager.topSongs.compactMap(\.artwork).prefix(4))
    }

    private var heroArtwork: MPMediaItemArtwork? {
        artworkHighlights.first
    }

    var body: some View {
        ScrollView {
            if !manager.hasLoadedInitialSnapshot && recap.snapshotCount == 0 {
                VStack {
                    ProgressView()
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    RecapHeroCard(
                        monthTitle: monthTitle,
                        subtitle: heroSubtitle,
                        recap: recap,
                        artworks: artworkHighlights
                    )

                    if recap.hasActivity {
                        if let leadingSong = recap.topSongs.first {
                            RecapSpotlight(song: leadingSong)
                        }

                        if !recap.topSongs.isEmpty {
                            topSongsSection
                        }
                        if !recap.topAlbums.isEmpty {
                            topAlbumsSection
                        }
                        if !recap.topArtists.isEmpty {
                            topArtistsSection
                        }
                    } else {
                        baselineSection
                    }

                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 36)
            }
        }
        .background(RecapBackground(artwork: heroArtwork))
        .animation(.easeInOut(duration: 0.2), value: recap)
    }

    private var baselineSection: some View {
        RecapSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your baseline is set")
                    .font(.title3.weight(.semibold))
                Text("Come back after listening and your most-played songs, albums, and artists will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topSongsSection: some View {
        RecapRankingSection(title: "Top Songs") {
            ForEach(Array(recap.topSongs.prefix(8).enumerated()), id: \.element.id) { index, song in
                RecapSongRow(rank: index + 1, song: song)
            }
        }
    }

    private var topAlbumsSection: some View {
        RecapRankingSection(title: "Top Albums") {
            ForEach(Array(recap.topAlbums.prefix(6).enumerated()), id: \.element.id) { index, album in
                RecapGroupRow(rank: index + 1, group: album, systemImage: "rectangle.stack.fill")
            }
        }
    }

    private var topArtistsSection: some View {
        RecapRankingSection(title: "Top Artists") {
            ForEach(Array(recap.topArtists.prefix(6).enumerated()), id: \.element.id) { index, artist in
                RecapGroupRow(rank: index + 1, group: artist, systemImage: "person.fill")
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        RecapSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Debug")
                    .font(.headline)

            Button {
                manager.refreshForRecapSequence(reason: .manualRefresh)
            } label: {
                Label("Refresh Recap", systemImage: "arrow.clockwise")
            }
            .disabled(manager.isLoading)

            Button {
                Task {
                    let granted = await RecapNotificationScheduler.shared.requestAuthorizationAndSchedule()
                    await MainActor.run {
                        reminderStatusMessage = granted ? "Recap reminders scheduled." : "Notifications are not enabled."
                    }
                }
            } label: {
                Label("Enable Reminders", systemImage: "bell.badge")
            }

            Button {
                RecapNotificationScheduler.shared.scheduleDebugRecapNotification()
                reminderStatusMessage = "Test reminder scheduled."
            } label: {
                Label("Send Test Reminder", systemImage: "bell.and.waves.left.and.right")
            }

            Button {
                print(manager.recapDebugSummary())
                reminderStatusMessage = "Snapshot summary printed to console."
            } label: {
                Label("Print Snapshot Summary", systemImage: "doc.text.magnifyingglass")
            }

            if let reminderStatusMessage {
                Text(reminderStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    #endif

    private var monthTitle: String {
        Self.monthFormatter.string(from: recap.monthStart)
    }

    private var heroSubtitle: String {
        if recap.hasActivity {
            return "Your most-played music this month."
        }
        return "Listening insights will fill in as new plays are captured."
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

private struct RecapHeroCard: View {
    let monthTitle: String
    let subtitle: String
    let recap: MonthlyRecap
    let artworks: [MPMediaItemArtwork]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RecapArtworkStack(artworks: artworks)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(monthTitle)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            RecapGlassGroup {
                HStack(spacing: 10) {
                    RecapStatTile(title: "Plays", value: "\(recap.totalPlayDelta)", systemImage: "play.fill")
                    RecapStatTile(title: "Time", value: recap.totalListeningDuration.formattedPlayback, systemImage: "clock.fill")
                }
                HStack(spacing: 10) {
                    RecapMiniInsight(title: "Songs", value: "\(recap.topSongs.count)", systemImage: "music.note")
                    RecapMiniInsight(title: "Albums", value: "\(recap.topAlbums.count)", systemImage: "rectangle.stack.fill")
                    RecapMiniInsight(title: "Artists", value: "\(recap.topArtists.count)", systemImage: "person.2.fill")
                }
            }
        }
        .padding(18)
        .recapTileSurface(cornerRadius: 26, tintOpacity: 0.12)
    }
}

private struct RecapArtworkStack: View {
    let artworks: [MPMediaItemArtwork]

    var body: some View {
        ZStack {
            if let mainArtwork = artworks.first {
                ArtworkView(
                    artwork: mainArtwork,
                    size: CGSize(width: 176, height: 176),
                    cornerRadius: 20
                )
                .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 14)
                .rotationEffect(.degrees(-2))

                if artworks.count > 1 {
                    HStack {
                        Spacer()
                        VStack(spacing: -12) {
                            ForEach(Array(artworks.dropFirst().prefix(3).enumerated()), id: \.offset) { index, artwork in
                                ArtworkView(
                                    artwork: artwork,
                                    size: CGSize(width: 70, height: 70),
                                    cornerRadius: 12
                                )
                                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 8)
                                .rotationEffect(.degrees(index.isMultiple(of: 2) ? 5 : -5))
                            }
                        }
                    }
                    .padding(.trailing, 20)
                }
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(width: 176, height: 176)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(height: 198)
    }
}

private struct RecapSpotlight: View {
    let song: MonthlyRecap.RankedSong

    var body: some View {
        RecapSurface {
            HStack(spacing: 14) {
                ArtworkView(
                    artwork: song.artwork,
                    size: CGSize(width: 74, height: 74),
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Most Played")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(song.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(song.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                MetricBadge(text: "+\(song.playDelta)")
            }
        }
    }
}

private struct RecapRankingSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))

            RecapSurface {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct RecapStatTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 104)
        .padding(12)
        .recapTileSurface(cornerRadius: 16, tintOpacity: 0.08)
    }
}

private struct RecapMiniInsight: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .recapTileSurface(cornerRadius: 16, tintOpacity: 0.06)
    }
}

private struct RecapSongRow: View {
    let rank: Int
    let song: MonthlyRecap.RankedSong

    var body: some View {
        HStack(spacing: 12) {
            RecapRankView(rank: rank)
            ArtworkView(
                artwork: song.artwork,
                size: CGSize(width: 58, height: 58),
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(song.listeningDuration.formattedPlayback)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: "+\(song.playDelta)")
        }
        .padding(.vertical, 9)
    }
}

private struct RecapGroupRow: View {
    let rank: Int
    let group: MonthlyRecap.RankedGroup
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            RecapRankView(rank: rank)

            if systemImage == "person.fill" {
                ArtistArtworkView(artwork: group.artwork, name: group.title, diameter: 58)
            } else {
                ArtworkView(
                    artwork: group.artwork,
                    size: CGSize(width: 58, height: 58),
                    cornerRadius: 10
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(group.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(group.listeningDuration.formattedPlayback)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: "+\(group.playDelta)")
        }
        .padding(.vertical, 9)
    }
}

private struct RecapRankView: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 24, alignment: .trailing)
            .monospacedDigit()
    }
}

private struct RecapSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .recapTileSurface(cornerRadius: 20, tintOpacity: 0.08)
    }
}

private struct RecapGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 10) {
                    content
                }
            }
        } else {
            VStack(spacing: 10) {
                content
            }
        }
    }
}

private struct RecapTileSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.accentColor.opacity(tintOpacity)), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                }
        }
    }
}

private extension View {
    func recapTileSurface(cornerRadius: CGFloat, tintOpacity: Double) -> some View {
        modifier(RecapTileSurfaceModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}

private struct RecapBackground: View {
    let artwork: MPMediaItemArtwork?

    var body: some View {
        ZStack {
            if let gradientColors {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(.systemGroupedBackground)
            }

            Color(.systemBackground)
                .opacity(0.18)
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color]? {
        guard let components = artwork?.recapAverageColorComponents() else {
            return nil
        }

        return [
            Color(
                red: darken(components.0, amount: 0.45),
                green: darken(components.1, amount: 0.45),
                blue: darken(components.2, amount: 0.45)
            ),
            Color(
                red: boost(components.0, amount: 0.18),
                green: boost(components.1, amount: 0.18),
                blue: boost(components.2, amount: 0.18)
            ),
            Color(.systemGroupedBackground)
        ]
    }

    private func darken(_ component: Double, amount: Double) -> Double {
        max(component * (1 - amount), 0)
    }

    private func boost(_ component: Double, amount: Double) -> Double {
        min(component + (1 - component) * amount, 1)
    }
}

private enum RecapColorCalculator {
    static let context = CIContext(options: [.workingColorSpace: NSNull()])
}

private extension MPMediaItemArtwork {
    func recapAverageColorComponents(maxDimension: CGFloat = 80) -> (Double, Double, Double)? {
        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        guard let image = image(at: targetSize),
              let inputImage = CIImage(image: image) else {
            return nil
        }

        let extent = inputImage.extent
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = extent

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        RecapColorCalculator.context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return (
            Double(bitmap[0]) / 255.0,
            Double(bitmap[1]) / 255.0,
            Double(bitmap[2]) / 255.0
        )
    }
}

#if DEBUG
#Preview {
    MonthlyRecapView(manager: .previewPlaying)
}
#endif

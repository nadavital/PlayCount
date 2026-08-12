import CoreTransferable
@preconcurrency import MediaPlayer
import Charts
import SwiftUI
import UniformTypeIdentifiers

enum RecapShareTemplate: String, CaseIterable, Identifiable, Sendable {
    case yearInReview = "Year in Review"
    case overview = "Overview"
    case topSongs = "Top Songs"
    case topAlbums = "Top Albums"
    case topArtists = "Top Artists"
    case biggestGainers = "Gainers"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .yearInReview: "chart.bar.xaxis"
        case .overview: "rectangle.grid.2x2.fill"
        case .topSongs: "music.note"
        case .topAlbums: "square.stack.fill"
        case .topArtists: "person.2.fill"
        case .biggestGainers: "chart.line.uptrend.xyaxis"
        }
    }
}

struct RecapShareTrendPoint: Identifiable, Equatable, Sendable {
    let month: Date
    let plays: Int
    let listeningMinutes: Double
    let uniqueSongs: Int
    let uniqueArtists: Int

    init(
        month: Date,
        plays: Int,
        listeningMinutes: Double,
        uniqueSongs: Int = 0,
        uniqueArtists: Int = 0
    ) {
        self.month = month
        self.plays = plays
        self.listeningMinutes = listeningMinutes
        self.uniqueSongs = uniqueSongs
        self.uniqueArtists = uniqueArtists
    }

    var id: Date { month }
}

enum RecapShareGainerCategory: String, CaseIterable, Identifiable, Sendable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"

    var id: Self { self }
}

struct RecapSharePalette: Sendable {
    struct Components: Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }
    }

    let primary: Components
    let secondary: Components
    let tertiary: Components

    init(artworks: [MPMediaItemArtwork], fallbackSeed: UInt64) {
        let sampled = artworks.prefix(3).compactMap { $0.averageColorComponents() }
        if let first = sampled.first {
            let second = sampled.dropFirst().first ?? first
            let third = sampled.dropFirst(2).first ?? (
                (first.0 + second.0) / 2,
                (first.1 + second.1) / 2,
                (first.2 + second.2) / 2
            )
            primary = Self.components(first, saturationBoost: 0.12)
            secondary = Self.components(second, saturationBoost: 0.24)
            tertiary = Self.components(third, saturationBoost: 0.34)
        } else {
            let hue = Double(fallbackSeed % 360) / 360
            primary = Self.rgb(hue: hue, saturation: 0.62, brightness: 0.94)
            secondary = Self.rgb(hue: (hue + 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.56, brightness: 0.96)
            tertiary = Self.rgb(hue: (hue + 0.58).truncatingRemainder(dividingBy: 1), saturation: 0.46, brightness: 0.94)
        }
    }

    private static func components(
        _ rgb: (Double, Double, Double),
        saturationBoost: Double
    ) -> Components {
        let average = (rgb.0 + rgb.1 + rgb.2) / 3
        return Components(
            red: min(max(average + (rgb.0 - average) * (1 + saturationBoost), 0), 1),
            green: min(max(average + (rgb.1 - average) * (1 + saturationBoost), 0), 1),
            blue: min(max(average + (rgb.2 - average) * (1 + saturationBoost), 0), 1)
        )
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> Components {
        let uiColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return Components(red: red, green: green, blue: blue)
    }
}

struct RecapSharePayload: Transferable, @unchecked Sendable {
    let recap: MonthlyRecap
    let periodTitle: String
    let palette: RecapSharePalette
    let template: RecapShareTemplate
    let gainerCategory: RecapShareGainerCategory
    let trendPoints: [RecapShareTrendPoint]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            let image = await MainActor.run {
                RecapShareRenderer.image(
                    recap: payload.recap,
                    periodTitle: payload.periodTitle,
                    palette: payload.palette,
                    template: payload.template,
                    gainerCategory: payload.gainerCategory,
                    trendPoints: payload.trendPoints
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
    static let canvasSize = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    static func image(
        recap: MonthlyRecap,
        periodTitle: String,
        palette: RecapSharePalette,
        template: RecapShareTemplate = .overview,
        gainerCategory: RecapShareGainerCategory = .songs,
        trendPoints: [RecapShareTrendPoint] = []
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: RecapShareCard(
                recap: recap,
                periodTitle: periodTitle,
                palette: palette,
                template: template,
                gainerCategory: gainerCategory,
                trendPoints: trendPoints
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
        )
        renderer.scale = renderScale
        return renderer.uiImage
    }

    static func image(
        recap: MonthlyRecap,
        periodTitle: String,
        artwork: MPMediaItemArtwork?
    ) -> UIImage? {
        image(
            recap: recap,
            periodTitle: periodTitle,
            palette: RecapSharePalette(
                artworks: artwork.map { [$0] } ?? [],
                fallbackSeed: UInt64(max(recap.totalPlayDelta, 0))
            )
        )
    }
}

struct RecapShareStudio: View {
    let recap: MonthlyRecap
    let periodTitle: String
    let palette: RecapSharePalette
    let trendPoints: [RecapShareTrendPoint]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: RecapShareTemplate
    @State private var selectedGainerCategory: RecapShareGainerCategory = .songs

    init(
        recap: MonthlyRecap,
        periodTitle: String,
        palette: RecapSharePalette,
        trendPoints: [RecapShareTrendPoint] = []
    ) {
        self.recap = recap
        self.periodTitle = periodTitle
        self.palette = palette
        self.trendPoints = trendPoints
        _selectedTemplate = State(initialValue: trendPoints.isEmpty ? .overview : .yearInReview)

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-PlayCountScreenshotShareTemplate"),
           arguments.indices.contains(index + 1) {
            let template: RecapShareTemplate? = switch arguments[index + 1].lowercased() {
            case "year", "yearly", "yearinreview": .yearInReview
            case "overview": .overview
            case "songs", "topsongs": .topSongs
            case "albums", "topalbums": .topAlbums
            case "artists", "topartists": .topArtists
            case "gainers": .biggestGainers
            default: nil
            }
            if let template {
                _selectedTemplate = State(initialValue: template)
            }
        }
        if let index = arguments.firstIndex(of: "-PlayCountScreenshotGainerCategory"),
           arguments.indices.contains(index + 1),
           let category = RecapShareGainerCategory(rawValue: arguments[index + 1]) {
            _selectedGainerCategory = State(initialValue: category)
        }
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    RecapShareTemplatePicker(
                        templates: availableTemplates,
                        selection: $selectedTemplate
                    )

                    if selectedTemplate == .biggestGainers {
                        Picker("Gainer category", selection: $selectedGainerCategory) {
                            ForEach(availableGainerCategories) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    RecapShareCardPreview(
                        recap: recap,
                        periodTitle: periodTitle,
                        palette: palette,
                        template: selectedTemplate,
                        gainerCategory: selectedGainerCategory,
                        trendPoints: trendPoints
                    )
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                ShareLink(
                    item: payload,
                    preview: SharePreview("My \(periodTitle) PlayCount Recap")
                ) {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("Share Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { normalizeSelections() }
            .onChange(of: availableGainerCategories) { _, _ in normalizeSelections() }
        }
    }

    private var payload: RecapSharePayload {
        RecapSharePayload(
            recap: recap,
            periodTitle: periodTitle,
            palette: palette,
            template: selectedTemplate,
            gainerCategory: selectedGainerCategory,
            trendPoints: trendPoints
        )
    }

    private var availableGainerCategories: [RecapShareGainerCategory] {
        RecapShareGainerCategory.allCases.filter {
            switch $0 {
            case .songs: !recap.biggestGainers.isEmpty
            case .albums: !recap.biggestAlbumGainers.isEmpty
            case .artists: !recap.biggestArtistGainers.isEmpty
            }
        }
    }

    private var availableTemplates: [RecapShareTemplate] {
        RecapShareTemplate.allCases.filter {
            switch $0 {
            case .yearInReview: !trendPoints.isEmpty
            case .overview: true
            case .topSongs: !recap.topSongs.isEmpty
            case .topAlbums: !recap.topAlbums.isEmpty
            case .topArtists: !recap.topArtists.isEmpty
            case .biggestGainers: !availableGainerCategories.isEmpty
            }
        }
    }

    private func normalizeSelections() {
        if !availableTemplates.contains(selectedTemplate) {
            selectedTemplate = availableTemplates.first ?? .overview
        }
        if !availableGainerCategories.contains(selectedGainerCategory),
           let first = availableGainerCategories.first {
            selectedGainerCategory = first
        }
    }
}

private struct RecapShareTemplatePicker: View {
    let templates: [RecapShareTemplate]
    @Binding var selection: RecapShareTemplate

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(templates) { template in
                    Button {
                        selection = template
                    } label: {
                        Label(template.rawValue, systemImage: template.systemImage)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(
                                selection == template ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(selection == template ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == template ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Share design")
    }
}

private struct RecapShareCardPreview: View {
    let recap: MonthlyRecap
    let periodTitle: String
    let palette: RecapSharePalette
    let template: RecapShareTemplate
    let gainerCategory: RecapShareGainerCategory
    let trendPoints: [RecapShareTrendPoint]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / RecapShareRenderer.canvasSize.width
            RecapShareCard(
                recap: recap,
                periodTitle: periodTitle,
                palette: palette,
                template: template,
                gainerCategory: gainerCategory,
                trendPoints: trendPoints
            )
            .frame(width: RecapShareRenderer.canvasSize.width, height: RecapShareRenderer.canvasSize.height)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recap share preview")
    }
}

private struct RecapShareCard: View {
    let recap: MonthlyRecap
    let periodTitle: String
    let palette: RecapSharePalette
    let template: RecapShareTemplate
    let gainerCategory: RecapShareGainerCategory
    let trendPoints: [RecapShareTrendPoint]

    var body: some View {
        ZStack {
            RecapShareBackground(palette: palette)
            switch template {
            case .yearInReview:
                RecapShareYearInReview(
                    recap: recap,
                    periodTitle: periodTitle,
                    points: trendPoints,
                    palette: palette
                )
            case .overview:
                RecapShareOverview(recap: recap, periodTitle: periodTitle)
            case .topSongs:
                RecapShareRanking(
                    title: "Top Songs",
                    periodTitle: periodTitle,
                    items: recap.topSongs.prefix(10).map {
                        RecapShareRankedItem(id: "song-\($0.id)", title: $0.title, subtitle: $0.artist, detail: "+\($0.playDelta) plays", artwork: $0.artwork)
                    }
                )
            case .topAlbums:
                RecapShareRanking(
                    title: "Top Albums",
                    periodTitle: periodTitle,
                    items: recap.topAlbums.prefix(10).map {
                        RecapShareRankedItem(id: "album-\($0.id)", title: $0.title, subtitle: $0.subtitle, detail: "+\($0.playDelta) plays", artwork: $0.artwork)
                    }
                )
            case .topArtists:
                RecapShareRanking(
                    title: "Top Artists",
                    periodTitle: periodTitle,
                    items: recap.topArtists.prefix(10).map {
                        RecapShareRankedItem(id: "artist-\($0.id)", title: $0.title, subtitle: $0.subtitle, detail: "+\($0.playDelta) plays", artwork: $0.artwork)
                    }
                )
            case .biggestGainers:
                RecapShareRanking(
                    title: "Biggest \(gainerCategory.rawValue) Gainers",
                    periodTitle: periodTitle,
                    items: gainerItems
                )
            }
        }
        .environment(\.colorScheme, .light)
        .foregroundStyle(.black)
        .clipped()
    }

    private var gainerItems: [RecapShareRankedItem] {
        switch gainerCategory {
        case .songs:
            recap.biggestGainers.prefix(10).map {
                RecapShareRankedItem(id: "gainer-song-\($0.id)", title: $0.title, subtitle: $0.artist, detail: "↑\($0.rankChange) · +\($0.playDelta) plays", artwork: $0.artwork)
            }
        case .albums:
            recap.biggestAlbumGainers.prefix(10).map {
                RecapShareRankedItem(id: "gainer-album-\($0.id)", title: $0.title, subtitle: $0.subtitle, detail: "↑\($0.rankChange) · +\($0.playDelta) plays", artwork: $0.artwork)
            }
        case .artists:
            recap.biggestArtistGainers.prefix(10).map {
                RecapShareRankedItem(id: "gainer-artist-\($0.id)", title: $0.title, subtitle: $0.subtitle, detail: "↑\($0.rankChange) · +\($0.playDelta) plays", artwork: $0.artwork)
            }
        }
    }
}

private struct RecapShareBackground: View {
    let palette: RecapSharePalette

    var body: some View {
        ZStack {
            Color(red: 0.985, green: 0.978, blue: 0.965)
            RadialGradient(
                colors: [palette.primary.color.opacity(0.88), .clear],
                center: .topLeading,
                startRadius: 4,
                endRadius: 230
            )
            RadialGradient(
                colors: [palette.secondary.color.opacity(0.82), .clear],
                center: .bottomTrailing,
                startRadius: 8,
                endRadius: 250
            )
            RadialGradient(
                colors: [palette.tertiary.color.opacity(0.48), .clear],
                center: UnitPoint(x: 0.96, y: 0.2),
                startRadius: 4,
                endRadius: 160
            )
            Color.white.opacity(0.52)
        }
        .ignoresSafeArea()
    }
}

private struct RecapShareHeader: View {
    let periodTitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            PlayCountShareBrandMark(size: 28)
            VStack(alignment: .leading, spacing: -1) {
                Text("PLAYCOUNT")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(0.7)
                Text("YOUR MUSIC, COUNTED")
                    .font(.system(size: 5.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.black.opacity(0.5))
            }
            Spacer()
            Text(periodTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.black)
    }
}

private struct PlayCountShareBrandMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(Color(red: 0.65, green: 0.88, blue: 0.96))
                    Image(systemName: "medal.fill")
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.yellow, .red)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
        .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
        .accessibilityHidden(true)
    }

    private static let image: UIImage? = {
        let names = [
            "PlayCountIcon-iOS-Default-1024@1x",
            "PlayCountIcon60x60@2x",
            "PlayCountIcon76x76@2x~ipad"
        ]
        return names.lazy.compactMap { UIImage(named: $0) }.first
    }()
}

private struct RecapShareYearInReview: View {
    let recap: MonthlyRecap
    let periodTitle: String
    let points: [RecapShareTrendPoint]
    let palette: RecapSharePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecapShareHeader(periodTitle: periodTitle)

            VStack(alignment: .leading, spacing: 1) {
                Text("Your Year in Music")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text("A month-by-month view of what moved you")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.55))
            }

            HStack(spacing: 10) {
                RecapShareHeroStat(value: recap.totalPlayDelta.formatted(), label: "PLAYS")
                RecapShareHeroStat(value: recap.totalListeningDuration.formattedListeningMinutes, label: "LISTENED")
            }

            RecapShareMiniTrend(
                title: "Plays by month",
                points: points,
                value: { Double($0.plays) },
                color: palette.primary.color
            )
            RecapShareMiniTrend(
                title: "Listening minutes by month",
                points: points,
                value: { $0.listeningMinutes },
                color: palette.secondary.color
            )

            HStack(alignment: .top, spacing: 12) {
                RecapShareTopOne(title: "TOP SONG", value: recap.topSongs.first?.title, subtitle: recap.topSongs.first?.artist)
                RecapShareTopOne(title: "TOP ARTIST", value: recap.topArtists.first?.title, subtitle: recap.topArtists.first?.subtitle)
                RecapShareTopOne(title: "TOP ALBUM", value: recap.topAlbums.first?.title, subtitle: recap.topAlbums.first?.subtitle)
            }

            RecapShareArtworkStrip(artworks: artworks)
                .frame(height: 82)
        }
        .padding(20)
    }

    private var artworks: [MPMediaItemArtwork] {
        recap.topSongs.compactMap(\.artwork)
            + recap.topAlbums.compactMap(\.artwork)
            + recap.topArtists.compactMap(\.artwork)
    }
}

private struct RecapShareHeroStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 6.5, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.black.opacity(0.48))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.58), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.72), lineWidth: 1) }
    }
}

private struct RecapShareMiniTrend: View {
    let title: String
    let points: [RecapShareTrendPoint]
    let value: (RecapShareTrendPoint) -> Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
            Chart(points) { point in
                BarMark(
                    x: .value("Month", point.month, unit: .month),
                    y: .value(title, value(point))
                )
                .foregroundStyle(color.gradient)
                .clipShape(.rect(cornerRadius: 2))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                        .font(.system(size: 6, weight: .bold))
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.clear)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 66)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.white.opacity(0.52), in: .rect(cornerRadius: 14))
    }
}

private struct RecapShareTopOne: View {
    let title: String
    let value: String?
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 6, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.black.opacity(0.48))
            Text(value ?? "—")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 7, design: .rounded))
                    .foregroundStyle(.black.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RecapShareOverview: View {
    let recap: MonthlyRecap
    let periodTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecapShareHeader(periodTitle: periodTitle)

            VStack(alignment: .leading, spacing: 1) {
                Text("This was your sound")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                Text("The music you kept coming back to")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.55))
            }

            RecapShareArtworkComposition(artworks: overviewArtworks)
                .frame(height: 238)

            HStack(spacing: 10) {
                RecapShareHeroStat(value: recap.totalPlayDelta.formatted(), label: "PLAYS")
                RecapShareHeroStat(value: recap.totalListeningDuration.formattedListeningMinutes, label: "LISTENED")
                RecapShareHeroStat(value: recap.playedSongCount.formatted(), label: "SONGS")
            }

            HStack(alignment: .top, spacing: 12) {
                RecapShareOverviewList(title: "Top Songs", items: recap.topSongs.prefix(3).map { ($0.title, $0.artist) })
                RecapShareOverviewList(title: "Top Artists", items: recap.topArtists.prefix(3).map { ($0.title, $0.subtitle) })
                RecapShareOverviewList(title: "Top Albums", items: recap.topAlbums.prefix(3).map { ($0.title, $0.subtitle) })
            }
        }
        .padding(20)
    }

    private var overviewArtworks: [MPMediaItemArtwork] {
        var seen: Set<ObjectIdentifier> = []
        var result: [MPMediaItemArtwork] = []
        let candidates = recap.topSongs.compactMap(\.artwork)
            + recap.topAlbums.compactMap(\.artwork)
            + recap.topArtists.compactMap(\.artwork)
        for artwork in candidates where result.count < 3 {
            let id = ObjectIdentifier(artwork)
            guard seen.insert(id).inserted else { continue }
            result.append(artwork)
        }
        return result
    }
}

private struct RecapShareOverviewList: View {
    let title: String
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1)")
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(items[index].0)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                        Text(items[index].1)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .font(.system(size: 8.5, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RecapShareArtworkComposition: View {
    let artworks: [MPMediaItemArtwork]

    var body: some View {
        GeometryReader { proxy in
            switch artworks.count {
            case 0:
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.08))
                    .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary) }
            case 1:
                let side = min(proxy.size.width, proxy.size.height)
                RecapShareResolvedArtworkView(artwork: artworks[0], size: CGSize(width: side, height: side), cornerRadius: 28)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .shadow(color: .black.opacity(0.22), radius: 15, y: 9)
            case 2:
                let side = min(proxy.size.width * 0.64, proxy.size.height * 0.82)
                ZStack {
                    RecapShareResolvedArtworkView(artwork: artworks[1], size: CGSize(width: side, height: side), cornerRadius: 24)
                        .rotationEffect(.degrees(8))
                        .offset(x: side * 0.31, y: 8)
                    RecapShareResolvedArtworkView(artwork: artworks[0], size: CGSize(width: side, height: side), cornerRadius: 24)
                        .rotationEffect(.degrees(-7))
                        .offset(x: -side * 0.31, y: -4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.2), radius: 13, y: 8)
            default:
                let heroSide = min(proxy.size.width * 0.62, proxy.size.height * 0.86)
                let backSide = heroSide * 0.72
                ZStack {
                    RecapShareResolvedArtworkView(artwork: artworks[1], size: CGSize(width: backSide, height: backSide), cornerRadius: 20)
                        .rotationEffect(.degrees(-10))
                        .offset(x: -heroSide * 0.55, y: 15)
                    RecapShareResolvedArtworkView(artwork: artworks[2], size: CGSize(width: backSide, height: backSide), cornerRadius: 20)
                        .rotationEffect(.degrees(10))
                        .offset(x: heroSide * 0.55, y: 15)
                    RecapShareResolvedArtworkView(artwork: artworks[0], size: CGSize(width: heroSide, height: heroSide), cornerRadius: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(.white.opacity(0.72), lineWidth: 1.5)
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.22), radius: 15, y: 9)
            }
        }
    }
}

private struct RecapShareRankedItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let artwork: MPMediaItemArtwork?
}

private struct RecapShareRanking: View {
    let title: String
    let periodTitle: String
    let items: [RecapShareRankedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RecapShareHeader(periodTitle: periodTitle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(periodTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 18) {
                RecapShareRankingColumn(items: Array(items.prefix(5)), startingRank: 1)
                RecapShareRankingColumn(items: Array(items.dropFirst(5).prefix(5)), startingRank: 6)
            }

            Spacer(minLength: 8)

            RecapShareArtworkStrip(artworks: items.compactMap(\.artwork))
                .frame(height: 92)
        }
        .padding(20)
    }
}

private struct RecapShareRankingColumn: View {
    let items: [RecapShareRankedItem]
    let startingRank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items.enumerated(), id: \.element.id) { offset, item in
                HStack(alignment: .top, spacing: 7) {
                    Text("\(startingRank + offset)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.subtitle)
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(item.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                        Text(item.detail)
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RecapShareArtworkStrip: View {
    let artworks: [MPMediaItemArtwork]

    var body: some View {
        GeometryReader { proxy in
            let uniqueArtworks = uniqueArtwork
            if uniqueArtworks.isEmpty {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.black.opacity(0.07))
            } else {
                HStack(spacing: 3) {
                    ForEach(uniqueArtworks.indices, id: \.self) { index in
                        RecapShareResolvedArtworkView(
                            artwork: uniqueArtworks[index],
                            size: CGSize(
                                width: (proxy.size.width - CGFloat(uniqueArtworks.count - 1) * 3) / CGFloat(uniqueArtworks.count),
                                height: proxy.size.height
                            ),
                            cornerRadius: 5
                        )
                    }
                }
            }
        }
    }

    private var uniqueArtwork: [MPMediaItemArtwork] {
        var seen: Set<ObjectIdentifier> = []
        return artworks.filter { seen.insert(ObjectIdentifier($0)).inserted }.prefix(6).map { $0 }
    }
}

private struct RecapShareResolvedArtworkView: View {
    let artwork: MPMediaItemArtwork?
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork, let image = artwork.image(at: size) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.black.opacity(0.07))
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

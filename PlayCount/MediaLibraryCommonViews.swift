import SwiftUI
import MediaPlayer
import UIKit
import CoreImage.CIFilterBuiltins

private enum ArtworkImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func cachedImage(for artwork: MPMediaItemArtwork, size: CGSize) -> UIImage? {
        cache.object(forKey: key(for: artwork, size: size))
    }

    static func image(for artwork: MPMediaItemArtwork, size: CGSize) -> UIImage? {
        let key = key(for: artwork, size: size)

        if let image = cache.object(forKey: key) {
            return image
        }

        guard let image = artwork.image(at: size) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func key(for artwork: MPMediaItemArtwork, size: CGSize) -> NSString {
        let pixelWidth = Int(size.width.rounded(.up))
        let pixelHeight = Int(size.height.rounded(.up))
        return "\(ObjectIdentifier(artwork))-\(pixelWidth)x\(pixelHeight)" as NSString
    }
}

private final class ArtworkAverageColor {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

private enum ArtworkColorCalculator {
    static let context = CIContext(options: [.workingColorSpace: NSNull()])
    static let cache = NSCache<NSString, ArtworkAverageColor>()
}

extension MPMediaItemArtwork {
    func cachedAverageColorComponents(
        cacheKey: String,
        maxDimension: CGFloat = 80
    ) -> (Double, Double, Double)? {
        let key = averageColorCacheKey(cacheKey: cacheKey, maxDimension: maxDimension)
        guard let cached = ArtworkColorCalculator.cache.object(forKey: key) else { return nil }
        return (cached.red, cached.green, cached.blue)
    }

    func averageColorComponents(
        maxDimension: CGFloat = 80,
        cacheKey: String? = nil
    ) -> (Double, Double, Double)? {
        let key = averageColorCacheKey(cacheKey: cacheKey, maxDimension: maxDimension)
        if let cached = ArtworkColorCalculator.cache.object(forKey: key) {
            return (cached.red, cached.green, cached.blue)
        }

        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        guard let image = image(at: targetSize),
              let inputImage = CIImage(image: image) else {
            return nil
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = inputImage.extent

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ArtworkColorCalculator.context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        guard bitmap[3] > 0 else {
            return nil
        }

        let color = ArtworkAverageColor(
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255
        )
        ArtworkColorCalculator.cache.setObject(color, forKey: key)

        return (color.red, color.green, color.blue)
    }

    private func averageColorCacheKey(
        cacheKey: String?,
        maxDimension: CGFloat
    ) -> NSString {
        let pixelDimension = Int(maxDimension.rounded(.up))
        return "\(cacheKey ?? String(describing: ObjectIdentifier(self)))-\(pixelDimension)" as NSString
    }
}

struct EmptyLibrarySection: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        Section {
            VStack(spacing: 18) {
                EmptyLibraryArtworkCluster(systemImage: systemImage)

                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        }
    }
}

struct EmptyLibraryArtworkCluster: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PlayCountBrand.accent.opacity(0.28),
                            Color.pink.opacity(0.22),
                            Color.orange.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 118, height: 118)
                .rotationEffect(.degrees(-7))

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 92, height: 92)
                .rotationEffect(.degrees(8))

            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(width: 74, height: 74)
                .playCountCardSurface(cornerRadius: 18)
        }
        .frame(width: 138, height: 126)
    }
}

struct ArtworkView: View {
    let artwork: MPMediaItemArtwork?
    private let size: CGSize
    private let cornerRadius: CGFloat

    init(
        artwork: MPMediaItemArtwork?,
        size: CGSize = CGSize(width: 56, height: 56),
        cornerRadius: CGFloat = 8
    ) {
        self.artwork = artwork
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        DeferredArtworkImage(artwork: artwork, size: size) {
            artworkPlaceholder
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DeferredArtworkImage<Placeholder: View>: View {
    let artwork: MPMediaItemArtwork?
    let size: CGSize
    private let placeholder: Placeholder
    @State private var image: UIImage?

    init(
        artwork: MPMediaItemArtwork?,
        size: CGSize,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.artwork = artwork
        self.size = size
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: requestID) {
            guard let artwork else {
                image = nil
                return
            }
            if let cached = ArtworkImageCache.cachedImage(for: artwork, size: size) {
                image = cached
                return
            }
            image = nil
            let rendered = await Task.detached(priority: .utility) {
                ArtworkImageCache.image(for: artwork, size: size)
            }.value
            guard !Task.isCancelled else { return }
            image = rendered
        }
    }

    private var requestID: String {
        guard let artwork else {
            return "none-\(Int(size.width))-\(Int(size.height))"
        }
        return "\(ObjectIdentifier(artwork))-\(Int(size.width))-\(Int(size.height))"
    }
}

struct ArtistArtworkView: View {
    let artwork: MPMediaItemArtwork?
    let name: String
    private let diameter: CGFloat

    init(artwork: MPMediaItemArtwork?, name: String, diameter: CGFloat = 56) {
        self.artwork = artwork
        self.name = name
        self.diameter = diameter
    }

    private var initials: String {
        let words = name.split { $0 == " " || $0 == "\t" || $0 == "\n" }
        let characters = words.prefix(2).compactMap { $0.first }
        if characters.isEmpty {
            return "🎤"
        }
        return String(characters).uppercased()
    }

    private var renderSize: CGSize {
        CGSize(width: diameter * 2, height: diameter * 2)
    }

    var body: some View {
        Group {
            if artwork != nil {
                DeferredArtworkImage(artwork: artwork, size: renderSize) {
                    artworkPlaceholder
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Circle()
                .fill(PlayCountBrand.accent.opacity(0.15))
            Text(initials)
                .font(initials == "🎤" ? .system(size: diameter / 2.2) : .system(size: diameter / 2.2, weight: .semibold))
                .foregroundStyle(PlayCountBrand.accent)
        }
    }
}

struct MediaListRow<Artwork: View>: View {
    let rank: Int?
    let title: String
    let subtitle: String?
    let detail: String
    let badgeText: String
    let subtitleProminent: Bool
    private let artwork: Artwork
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        rank: Int? = nil,
        title: String,
        subtitle: String? = nil,
        detail: String,
        badgeText: String,
        subtitleProminent: Bool = false,
        @ViewBuilder artwork: () -> Artwork
    ) {
        self.rank = rank
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.badgeText = badgeText
        self.subtitleProminent = subtitleProminent
        self.artwork = artwork()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityLayout
        } else {
            standardLayout
        }
    }

    private var standardLayout: some View {
        HStack(spacing: 12) {
            leadingIdentity

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                subtitleLine

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MetricBadge(text: badgeText)
        }
        .frame(minHeight: 64, alignment: .center)
        .padding(.vertical, 4)
    }

    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIdentity

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                subtitleLine

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                MetricBadge(text: badgeText)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var leadingIdentity: some View {
        if let rank {
            RankBadgeView(rank: rank)
        }

        artwork
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.subheadline.weight(subtitleProminent ? .semibold : .regular))
                .foregroundStyle(subtitleProminent ? .primary : .secondary)
                .lineLimit(1)
        } else {
            Text(" ")
                .font(.subheadline)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }
}

struct MetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

struct MonthlyInsightRow<Artwork: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let metric: String
    @ViewBuilder let artwork: Artwork

    var body: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            MetricBadge(text: metric)
        }
        .padding(.vertical, 6)
    }
}

struct RankBadgeView: View {
    enum Style {
        case prominentTopThree
        case plain
    }

    let rank: Int
    let style: Style

    init(rank: Int, style: Style = .prominentTopThree) {
        self.rank = rank
        self.style = style
    }

    var body: some View {
        if style == .prominentTopThree && rank <= 3 {
            TopRankBadge(rank: rank)
        } else {
            Text("\(rank)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .center)
                .monospacedDigit()
        }
    }
}

private struct TopRankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background {
                Circle()
                    .fill(gradient)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.28))
            }
            .shadow(color: shadowColor, radius: 7, x: 0, y: 4)
            .topRankGlass()
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var colors: [Color] {
        switch rank {
        case 1:
            return [Color(red: 1, green: 0.78, blue: 0.22), Color(red: 0.96, green: 0.48, blue: 0.12)]
        case 2:
            return [Color(red: 0.86, green: 0.89, blue: 0.95), Color(red: 0.48, green: 0.56, blue: 0.68)]
        default:
            return [Color(red: 0.88, green: 0.54, blue: 0.32), Color(red: 0.56, green: 0.28, blue: 0.14)]
        }
    }

    private var shadowColor: Color {
        colors.last?.opacity(0.28) ?? Color.black.opacity(0.16)
    }
}

private extension View {
    func topRankGlass() -> some View {
        modifier(TopRankGlassModifier())
    }
}

private struct TopRankGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(0.12)), in: Circle())
        } else {
            content
        }
    }
}

struct LoadingListSection: View {
    let title: String

    var body: some View {
        Section {
            PlayCountLoadingPanel(
                title: "Getting your library ready",
                detail: title,
                markSize: 38
            )
            .listRowInsets(.init(top: 34, leading: 20, bottom: 34, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

struct PlayCountLoadingPanel: View {
    let title: String
    let detail: String
    var markSize: CGFloat = 42

    var body: some View {
        VStack(spacing: 14) {
            PlayCountLoadingMark(size: markSize)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct PlayCountLoadingMark: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pausesAnimation: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotMode") ||
            ProcessInfo.processInfo.environment["PLAYCOUNT_SCREENSHOT_MODE"] == "1"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: pausesAnimation)) { context in
            medal(phase: animationPhase(for: context.date))
        }
        .accessibilityHidden(true)
    }

    private func animationPhase(for date: Date) -> Double {
        guard !pausesAnimation else { return 0.35 }
        return date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 2.4) / 2.4
    }

    private func medal(phase: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PlayCountBrand.burgundy, PlayCountBrand.burgundy.opacity(0.76)],
                        center: UnitPoint(
                            x: 0.42 + 0.16 * cos(phase * .pi * 2),
                            y: 0.42 + 0.16 * sin(phase * .pi * 2)
                        ),
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size * 0.84, height: size * 0.84)
                .blur(radius: size * 0.035)

            loadingGlassLens

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.25, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .offset(x: size * 0.015)

            Circle()
                .trim(from: 0.03, to: 0.16)
                .stroke(
                    .white.opacity(0.52),
                    style: StrokeStyle(lineWidth: max(0.7, size * 0.025), lineCap: .round)
                )
                .frame(width: size * 0.75, height: size * 0.75)
                .rotationEffect(.degrees(phase * 360))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var loadingGlassLens: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.clear.tint(PlayCountBrand.burgundy.opacity(0.32)), in: .circle)
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay { Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.75) }
        }
    }
}

struct LibraryStatusOverlayModifier: ViewModifier {
    let isLoading: Bool
    let message: String?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let message, !isLoading {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                        .allowsHitTesting(false)
                } else {
                    EmptyView()
                }
            }
    }
}

struct LibraryMetricPicker: View {
    @Binding var selection: MediaLibraryManager.SortMetric
    var displaysIcon = true

    var body: some View {
        Menu {
            ForEach(MediaLibraryManager.SortMetric.allCases) { metric in
                Button {
                    selection = metric
                } label: {
                    Label(metric.menuTitle, systemImage: metric.systemImageName)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if displaysIcon {
                    Image(systemName: selection.systemImageName)
                        .imageScale(.medium)
                }
                Text(selection.toolbarLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .accessibilityLabel(Text("Ranking metric: \(selection.toolbarLabel)"))
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct MonthlyInsightLoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.secondary.opacity(0.14))
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text("Updating this month")
                    .font(.caption.weight(.semibold))
                Text("Your latest listening insight")
                    .font(.headline)
                Text("Preparing…")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
        .frame(minHeight: 66)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Updating this month's listening insight")
    }
}

struct CachedLibraryStatusRow: View {
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Updating rankings")
                    .font(.caption.weight(.semibold))
                if let lastUpdated {
                    Text("Showing saved data from \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                } else {
                    Text("Showing saved data")
                        .font(.caption2)
                }
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    @ViewBuilder
    func playCountSoftTopScrollEdge() -> some View {
        if #available(iOS 27.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func playCountPrimaryTitleDisplayMode() -> some View {
        if #available(iOS 27.0, *) {
            toolbarTitleDisplayMode(.inlineLarge)
        } else {
            navigationBarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    func playCountPushedTitleDisplayMode() -> some View {
        if #available(iOS 27.0, *) {
            toolbarTitleDisplayMode(.inlineLarge)
        } else {
            navigationBarTitleDisplayMode(.inline)
        }
    }

    func libraryStatusOverlay(isLoading: Bool, message: String?) -> some View {
        modifier(LibraryStatusOverlayModifier(isLoading: isLoading, message: message))
    }

    func playCountCardSurface(cornerRadius: CGFloat) -> some View {
        modifier(PlayCountCardSurfaceModifier(cornerRadius: cornerRadius))
    }
}

struct PlayCountSheetDismissButton: View {
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            dismissButton
                .buttonStyle(.glassProminent)
                .tint(PlayCountBrand.accent)
        } else {
            dismissButton
                .buttonStyle(.borderedProminent)
                .tint(PlayCountBrand.accent)
        }
    }

    private var dismissButton: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
        }
        .accessibilityLabel("Done")
    }
}

private struct PlayCountCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var neutralGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.025)
            : Color.black.opacity(0.045)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(neutralGlassTint),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                }
            }
    }
}

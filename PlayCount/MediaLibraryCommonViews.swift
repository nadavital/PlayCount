import SwiftUI
import MediaPlayer

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
                            Color.accentColor.opacity(0.28),
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
                .libraryGlassSurface(cornerRadius: 18, tintOpacity: 0.12)
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
        Group {
            if let artwork,
               let image = artwork.image(at: size) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        }
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
            if let artwork,
               let image = artwork.image(at: renderSize) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                    Text(initials)
                        .font(initials == "🎤" ? .system(size: diameter / 2.2) : .system(size: diameter / 2.2, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }
}

struct MetricBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
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
            VStack(spacing: 16) {
                EmptyLibraryArtworkCluster(systemImage: "music.note.list")
                    .opacity(0.72)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
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

extension View {
    func libraryStatusOverlay(isLoading: Bool, message: String?) -> some View {
        modifier(LibraryStatusOverlayModifier(isLoading: isLoading, message: message))
    }

    func libraryGlassSurface(cornerRadius: CGFloat, tintOpacity: Double = 0.08) -> some View {
        modifier(LibraryGlassSurfaceModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}

private struct LibraryGlassSurfaceModifier: ViewModifier {
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

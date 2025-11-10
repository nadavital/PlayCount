import SwiftUI
import MediaPlayer

struct EmptyLibrarySection: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
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
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

struct LoadingListSection: View {
    let title: String

    var body: some View {
        Section {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
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
}

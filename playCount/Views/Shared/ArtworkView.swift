//
//  ArtworkView.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI
import MediaPlayer

struct ArtworkView: View {
    let artwork: MPMediaItemArtwork?
    let fallbackSystemImage: String
    let size: CGFloat
    let cornerRadius: CGFloat

    init(artwork: MPMediaItemArtwork?, fallbackSystemImage: String = "music.note", size: CGFloat = 50, cornerRadius: CGFloat = 4) {
        self.artwork = artwork
        self.fallbackSystemImage = fallbackSystemImage
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        if let image = artwork?.image(at: CGSize(width: size, height: size)) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(radius: 10, x: 5, y: 5)
        } else {
            Image(systemName: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(radius: 10, x: 5, y: 5)
        }
    }
}

// Helper extension to get average color from UIImage
import UIKit
extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let context = CIContext(options: [.workingColorSpace: kCFNull!])
        let parameters = [kCIInputExtentKey: CIVector(cgRect: extent)]
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: CIVector(cgRect: extent)]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255,
                       green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255,
                       alpha: 1)
    }
}

#Preview {
    VStack(spacing: 20) {
        ArtworkView(artwork: Song.preview.artwork, fallbackSystemImage: "music.note", size: 50, cornerRadius: 4)
        ArtworkView(artwork: Album.preview.artwork, fallbackSystemImage: "rectangle.stack.fill", size: 120, cornerRadius: 16)
        ArtworkView(artwork: Artist.preview.artwork, fallbackSystemImage: "person.crop.square", size: 120, cornerRadius: 16)
    }
}

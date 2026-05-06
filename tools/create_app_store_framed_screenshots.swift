import AppKit
import CoreGraphics
import Foundation

struct Shot {
    let input: String
    let output: String
    let title: String
    let colors: [NSColor]
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let inputDir = root.appendingPathComponent("AppStoreScreenshots")
let outputDir = inputDir.appendingPathComponent("Framed")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let defaultBezelPath = "/tmp/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Portrait.png"
let bezelURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PLAYCOUNT_APPSTORE_BEZEL"] ?? defaultBezelPath)

let shots: [Shot] = [
    Shot(
        input: "01-top-songs.png",
        output: "01-your-music-ranked.png",
        title: "See what you actually replay",
        colors: [
            NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.97, alpha: 1),
            NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.70, alpha: 1)
        ]
    ),
    Shot(
        input: "02-top-albums.png",
        output: "02-albums-that-stick.png",
        title: "The albums you live in",
        colors: [
            NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.78, alpha: 1),
            NSColor(calibratedRed: 0.84, green: 0.90, blue: 0.82, alpha: 1)
        ]
    ),
    Shot(
        input: "03-top-artists.png",
        output: "03-top-artists.png",
        title: "Who owned your rotation?",
        colors: [
            NSColor(calibratedRed: 0.95, green: 0.93, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.97, blue: 0.94, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.84, alpha: 1)
        ]
    ),
    Shot(
        input: "04-monthly-recap.png",
        output: "04-monthly-recaps.png",
        title: "Your month in music",
        colors: [
            NSColor(calibratedRed: 0.84, green: 0.78, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.91, alpha: 1),
            NSColor(calibratedRed: 0.82, green: 0.91, blue: 1.00, alpha: 1)
        ]
    )
]

let canvasSize = CGSize(width: 1320, height: 2868)
let deviceFrame = CGRect(x: 82, y: 420, width: 1156, height: 2359)
let bezelScreenRect = CGRect(x: 75, y: 66, width: 1320, height: 2868)
let titleRect = CGRect(x: 86, y: 118, width: 1148, height: 132)

func flipped(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.origin.x, y: canvasSize.height - rect.origin.y - rect.height, width: rect.width, height: rect.height)
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor, in context: CGContext) {
    context.saveGState()
    let path = CGPath(roundedRect: flipped(rect), cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.setFillColor(color.cgColor)
    context.fillPath()
    context.restoreGState()
}

func drawText(_ text: String, rect: CGRect, font: NSFont, color: NSColor, context: CGContext, alignment: NSTextAlignment = .left, lineHeight: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: 0
    ]

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: text).draw(in: flipped(rect), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

func drawBackground(colors: [NSColor], context: CGContext) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = colors.map { $0.cgColor } as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: [0, 0.54, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvasSize.height),
        end: CGPoint(x: canvasSize.width, y: 0),
        options: []
    )

    let overlay = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor.white.withAlphaComponent(0.26).cgColor,
            NSColor.white.withAlphaComponent(0.00).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        overlay,
        startCenter: CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.18),
        startRadius: 0,
        endCenter: CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.18),
        endRadius: 950,
        options: [.drawsAfterEndLocation]
    )
}

func screenRect(in destination: CGRect, bezelSize: CGSize) -> CGRect {
    let scaleX = destination.width / bezelSize.width
    let scaleY = destination.height / bezelSize.height
    return CGRect(
        x: destination.minX + bezelScreenRect.minX * scaleX,
        y: destination.minY + bezelScreenRect.minY * scaleY,
        width: bezelScreenRect.width * scaleX,
        height: bezelScreenRect.height * scaleY
    )
}

func transparentScreenBezel(from image: CGImage) throws -> CGImage {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let bitmap = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "renderer", code: 5)
    }

    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let minX = max(0, Int(bezelScreenRect.minX))
    let maxX = min(width, Int(bezelScreenRect.maxX))
    let minY = max(0, Int(bezelScreenRect.minY))
    let maxY = min(height, Int(bezelScreenRect.maxY))

    for y in minY..<maxY {
        for x in minX..<maxX {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            let alpha = pixels[offset + 3]
            if alpha > 0 && red < 18 && green < 18 && blue < 22 {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }
    }

    guard let output = bitmap.makeImage() else {
        throw NSError(domain: "renderer", code: 6)
    }
    return output
}

func render(_ shot: Shot) throws {
    guard let context = CGContext(
        data: nil,
        width: Int(canvasSize.width),
        height: Int(canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "renderer", code: 1)
    }

    drawBackground(colors: shot.colors, context: context)

    drawText(
        shot.title,
        rect: titleRect,
        font: NSFont.systemFont(ofSize: 70, weight: .black),
        color: .black,
        context: context,
        alignment: .center,
        lineHeight: 78
    )

    guard let bezelImage = NSImage(contentsOf: bezelURL),
          let bezelCGImage = bezelImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "renderer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing Apple bezel image at \(bezelURL.path)"])
    }
    let bezelOverlay = try transparentScreenBezel(from: bezelCGImage)
    let screenDestination = screenRect(in: deviceFrame, bezelSize: CGSize(width: bezelCGImage.width, height: bezelCGImage.height))

    let inputURL = inputDir.appendingPathComponent(shot.input)
    guard let source = NSImage(contentsOf: inputURL), let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "renderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing input \(shot.input)"])
    }

    context.saveGState()
    context.addPath(CGPath(roundedRect: flipped(screenDestination), cornerWidth: 76, cornerHeight: 76, transform: nil))
    context.clip()
    context.draw(cgImage, in: flipped(screenDestination))
    context.restoreGState()
    context.draw(bezelOverlay, in: flipped(deviceFrame))

    guard let image = context.makeImage() else {
        throw NSError(domain: "renderer", code: 3)
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = canvasSize
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "renderer", code: 4)
    }
    try data.write(to: outputDir.appendingPathComponent(shot.output), options: .atomic)
}

for shot in shots {
    try render(shot)
}

print("Wrote framed screenshots to \(outputDir.path)")

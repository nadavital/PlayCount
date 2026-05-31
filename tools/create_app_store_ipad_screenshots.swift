import AppKit
import CoreGraphics
import Foundation

struct Shot {
    let input: String
    let output: String
    let title: String
    let backgroundOffset: CGFloat
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let screenshotsDir = root.appendingPathComponent("AppStoreScreenshots")
let inputDir = screenshotsDir.appendingPathComponent("iPadRaw")
let outputDir = screenshotsDir.appendingPathComponent("Framed-iPad-13")
let qaDir = screenshotsDir.appendingPathComponent("qa")

let canvasSize = CGSize(width: 2064, height: 2752)
let titleRect = CGRect(x: 116, y: 142, width: 1832, height: 170)
let deviceFrame = CGRect(x: 206, y: 430, width: 1652, height: 2202)
let screenInset: CGFloat = 52
let screenFrame = deviceFrame.insetBy(dx: screenInset, dy: screenInset)
let expectedRawScreenshotSize = CGSize(width: 2064, height: 2752)

let shots: [Shot] = [
    Shot(input: "01-all-time-dashboard.png", output: "01-your-music-ranked.png", title: "See your music ranked", backgroundOffset: 0),
    Shot(input: "02-monthly-recap.png", output: "02-monthly-recaps.png", title: "Replay your month in music", backgroundOffset: 1),
    Shot(input: "03-artist-detail.png", output: "03-artist-detail.png", title: "Explore each artist's top plays", backgroundOffset: 2),
    Shot(input: "04-song-playback.png", output: "04-song-playback.png", title: "Play music from your stats", backgroundOffset: 3),
    Shot(input: "05-search-library.png", output: "05-search-library.png", title: "Search your listening history", backgroundOffset: 4)
]

let rgbaBitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func flipped(_ rect: CGRect, canvasSize: CGSize) -> CGRect {
    CGRect(x: rect.minX, y: canvasSize.height - rect.maxY, width: rect.width, height: rect.height)
}

func drawText(_ text: String, rect: CGRect, context: CGContext, canvasSize: CGSize) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.minimumLineHeight = 104
    paragraph.maximumLineHeight = 104

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 96, weight: .black),
        .foregroundColor: NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.04, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: 0
    ]

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: text).draw(in: flipped(rect, canvasSize: canvasSize), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

func drawBackground(offset: CGFloat, context: CGContext, canvasSize: CGSize) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(calibratedRed: 0.96, green: 0.93, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.86, green: 0.94, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.75, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.89, green: 0.96, blue: 0.88, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.92, alpha: 1).cgColor
    ] as CFArray

    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.25, 0.50, 0.75, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: -canvasSize.width * (0.35 + offset * 0.35), y: canvasSize.height),
        end: CGPoint(x: canvasSize.width * (1.45 + offset * 0.35), y: 0),
        options: []
    )

    context.saveGState()
    context.setBlendMode(.softLight)
    for index in 0..<6 {
        let rect = CGRect(
            x: -920 + CGFloat(index * 150) - offset * 260,
            y: CGFloat(390 + index * 370),
            width: 3200,
            height: 190
        )
        let path = CGPath(roundedRect: flipped(rect, canvasSize: canvasSize), cornerWidth: 95, cornerHeight: 95, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.18 : 0.10).cgColor)
        context.fillPath()
    }
    context.restoreGState()
}

func drawDeviceFrame(context: CGContext, canvasSize: CGSize) {
    let framePath = CGPath(roundedRect: flipped(deviceFrame, canvasSize: canvasSize), cornerWidth: 76, cornerHeight: 76, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 54, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    context.addPath(framePath)
    context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    let highlightPath = CGPath(roundedRect: flipped(deviceFrame.insetBy(dx: 5, dy: 5), canvasSize: canvasSize), cornerWidth: 72, cornerHeight: 72, transform: nil)
    context.addPath(highlightPath)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    context.setLineWidth(4)
    context.strokePath()
}

func drawScreenshot(_ image: CGImage, context: CGContext, canvasSize: CGSize) {
    let clipPath = CGPath(roundedRect: flipped(screenFrame, canvasSize: canvasSize), cornerWidth: 36, cornerHeight: 36, transform: nil)
    context.saveGState()
    context.addPath(clipPath)
    context.clip()
    context.draw(image, in: flipped(screenFrame, canvasSize: canvasSize))
    context.restoreGState()
}

func writePNG(_ image: CGImage, size: CGSize, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = size
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ipad-renderer", code: 4)
    }
    try data.write(to: url, options: .atomic)
}

func render(_ shot: Shot) throws {
    guard let context = CGContext(
        data: nil,
        width: Int(canvasSize.width),
        height: Int(canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "ipad-renderer", code: 1)
    }

    guard let screenshot = NSImage(contentsOf: inputDir.appendingPathComponent(shot.input)),
          let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "ipad-renderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing input \(shot.input)"])
    }
    guard CGSize(width: cgImage.width, height: cgImage.height) == expectedRawScreenshotSize else {
        throw NSError(
            domain: "ipad-renderer",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey: "\(shot.input) is \(cgImage.width)x\(cgImage.height), expected \(Int(expectedRawScreenshotSize.width))x\(Int(expectedRawScreenshotSize.height))"
            ]
        )
    }

    drawBackground(offset: shot.backgroundOffset, context: context, canvasSize: canvasSize)
    drawText(shot.title, rect: titleRect, context: context, canvasSize: canvasSize)
    drawDeviceFrame(context: context, canvasSize: canvasSize)
    drawScreenshot(cgImage, context: context, canvasSize: canvasSize)

    guard let image = context.makeImage() else {
        throw NSError(domain: "ipad-renderer", code: 3)
    }

    try writePNG(image, size: canvasSize, to: outputDir.appendingPathComponent(shot.output))
}

func makeContactSheet() throws {
    let thumbWidth: CGFloat = 412
    let thumbHeight: CGFloat = 550
    let gap: CGFloat = 32
    let labelHeight: CGFloat = 44
    let sheetSize = CGSize(width: gap + CGFloat(shots.count) * thumbWidth + CGFloat(shots.count - 1) * gap + gap, height: gap + thumbHeight + labelHeight + gap)

    guard let context = CGContext(
        data: nil,
        width: Int(sheetSize.width),
        height: Int(sheetSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "ipad-renderer", code: 5)
    }

    context.setFillColor(NSColor(calibratedWhite: 0.96, alpha: 1).cgColor)
    context.fill(CGRect(origin: .zero, size: sheetSize))

    for (index, shot) in shots.enumerated() {
        let imageURL = outputDir.appendingPathComponent(shot.output)
        guard let source = NSImage(contentsOf: imageURL),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let x = gap + CGFloat(index) * (thumbWidth + gap)
        let imageRect = CGRect(x: x, y: gap, width: thumbWidth, height: thumbHeight)
        context.draw(cgImage, in: flipped(imageRect, canvasSize: sheetSize))
        drawSmallLabel("\(index + 1). \(shot.output)", rect: CGRect(x: x, y: gap + thumbHeight + 8, width: thumbWidth, height: 32), context: context, canvasSize: sheetSize)
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "ipad-renderer", code: 6)
    }
    try writePNG(image, size: sheetSize, to: qaDir.appendingPathComponent("ipad-13-contact-sheet.png"))
}

func drawSmallLabel(_ text: String, rect: CGRect, context: CGContext, canvasSize: CGSize) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingMiddle
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: text).draw(in: flipped(rect, canvasSize: canvasSize), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: qaDir, withIntermediateDirectories: true)

for shot in shots {
    try render(shot)
}
try makeContactSheet()

print("Wrote \(shots.count) iPad screenshots to \(outputDir.path)")
print("Wrote contact sheet to \(qaDir.appendingPathComponent("ipad-13-contact-sheet.png").path)")

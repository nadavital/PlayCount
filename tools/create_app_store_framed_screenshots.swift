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
let inputDir = root.appendingPathComponent("AppStoreScreenshots")
let outputDir = inputDir.appendingPathComponent("Framed")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let defaultBezelPath = "/tmp/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Portrait.png"
let bezelURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PLAYCOUNT_APPSTORE_BEZEL"] ?? defaultBezelPath)

let shots: [Shot] = [
    Shot(
        input: "01-top-songs.png",
        output: "01-your-music-ranked.png",
        title: "See your all-time favorites",
        backgroundOffset: 0
    ),
    Shot(
        input: "02-top-albums.png",
        output: "02-albums-that-stick.png",
        title: "Find your top albums",
        backgroundOffset: 1
    ),
    Shot(
        input: "03-top-artists.png",
        output: "03-top-artists.png",
        title: "Track your top artists",
        backgroundOffset: 2
    ),
    Shot(
        input: "04-monthly-recap.png",
        output: "04-monthly-recaps.png",
        title: "Replay your month",
        backgroundOffset: 3
    )
]

let canvasSize = CGSize(width: 1320, height: 2868)
let deviceFrame = CGRect(x: 145, y: 530, width: 1030, height: 2190)
let titleRect = CGRect(x: 104, y: 160, width: 1112, height: 190)
let rgbaBitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func flipped(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.origin.x, y: canvasSize.height - rect.origin.y - rect.height, width: rect.width, height: rect.height)
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

func drawBackground(offset: CGFloat, context: CGContext) {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = [
        NSColor(calibratedRed: 0.96, green: 0.93, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.86, green: 0.94, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.75, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.89, green: 0.96, blue: 0.88, alpha: 1).cgColor,
        NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.92, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: [0, 0.25, 0.50, 0.75, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: -canvasSize.width * (0.55 + offset * 0.45), y: canvasSize.height),
        end: CGPoint(x: canvasSize.width * (1.65 + offset * 0.45), y: 0),
        options: []
    )

    context.saveGState()
    context.setBlendMode(.softLight)
    for index in 0..<5 {
        let rect = CGRect(
            x: -760 + CGFloat(index * 120) - offset * 300,
            y: CGFloat(430 + index * 430),
            width: 2100,
            height: 170
        )
        let path = CGPath(roundedRect: flipped(rect), cornerWidth: 85, cornerHeight: 85, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.18 : 0.10).cgColor)
        context.fillPath()
    }
    context.restoreGState()
}

struct BezelCompositeAssets {
    let overlay: CGImage
    let screenMask: CGImage
    let screenBounds: CGRect
    let visibleBounds: CGRect
}

func makeBezelCompositeAssets(from image: CGImage) throws -> BezelCompositeAssets {
    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    var maskPixels = [UInt8](repeating: 0, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let bitmap = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "renderer", code: 5)
    }

    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func isScreenCutout(_ x: Int, _ y: Int) -> Bool {
        let offset = y * bytesPerRow + x * bytesPerPixel
        return pixels[offset + 3] < 10
    }

    var startPoint: (x: Int, y: Int)?
    var bestDistance = Int.max
    let centerX = width / 2
    let centerY = height / 2
    for y in 0..<height {
        for x in 0..<width where isScreenCutout(x, y) {
            let distance = abs(x - centerX) + abs(y - centerY)
            if distance < bestDistance {
                bestDistance = distance
                startPoint = (x, y)
            }
        }
    }

    guard let startPoint else {
        throw NSError(domain: "renderer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not find transparent screen pixels in Apple bezel"])
    }

    var visited = [Bool](repeating: false, count: width * height)
    var stack = [startPoint]
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0
    var visibleMinX = width
    var visibleMinY = height
    var visibleMaxX = 0
    var visibleMaxY = 0

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            guard pixels[offset + 3] > 10 else { continue }
            visibleMinX = min(visibleMinX, x)
            visibleMinY = min(visibleMinY, y)
            visibleMaxX = max(visibleMaxX, x)
            visibleMaxY = max(visibleMaxY, y)
        }
    }

    while let point = stack.popLast() {
        guard point.x >= 0, point.x < width, point.y >= 0, point.y < height else { continue }
        let index = point.y * width + point.x
        guard !visited[index] else { continue }
        visited[index] = true
        guard isScreenCutout(point.x, point.y) else { continue }

        maskPixels[index] = 255
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)

        stack.append((point.x + 1, point.y))
        stack.append((point.x - 1, point.y))
        stack.append((point.x, point.y + 1))
        stack.append((point.x, point.y - 1))
    }

    guard minX < maxX, minY < maxY else {
        throw NSError(domain: "renderer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not detect Apple bezel screen area"])
    }

    guard let overlay = bitmap.makeImage(),
          let maskProvider = CGDataProvider(data: Data(maskPixels) as CFData),
          let mask = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: maskProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) else {
        throw NSError(domain: "renderer", code: 6)
    }

    return BezelCompositeAssets(
        overlay: overlay,
        screenMask: mask,
        screenBounds: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
        visibleBounds: CGRect(
            x: visibleMinX,
            y: visibleMinY,
            width: visibleMaxX - visibleMinX + 1,
            height: visibleMaxY - visibleMinY + 1
        )
    )
}

func makeScreenshotLayer(screenshot: CGImage, bezelSize: CGSize, screenBounds: CGRect, screenMask: CGImage) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: Int(bezelSize.width),
        height: Int(bezelSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "renderer", code: 9)
    }

    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: bezelSize.width, height: bezelSize.height), mask: screenMask)
    context.draw(screenshot, in: CGRect(x: screenBounds.minX, y: screenBounds.minY, width: screenBounds.width, height: screenBounds.height))
    context.restoreGState()

    guard let output = context.makeImage() else {
        throw NSError(domain: "renderer", code: 10)
    }
    return output
}

func makeDeviceComposite(screenshotLayer: CGImage, bezelOverlay: CGImage, bezelSize: CGSize, visibleBounds: CGRect) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: Int(bezelSize.width),
        height: Int(bezelSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: rgbaBitmapInfo
    ) else {
        throw NSError(domain: "renderer", code: 11)
    }

    context.draw(screenshotLayer, in: CGRect(x: 0, y: 0, width: bezelSize.width, height: bezelSize.height))
    context.draw(bezelOverlay, in: CGRect(x: 0, y: 0, width: bezelSize.width, height: bezelSize.height))

    guard let fullDevice = context.makeImage(),
          let croppedDevice = fullDevice.cropping(to: visibleBounds) else {
        throw NSError(domain: "renderer", code: 12)
    }
    return croppedDevice
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
        throw NSError(domain: "renderer", code: 1)
    }

    drawBackground(offset: shot.backgroundOffset, context: context)

    drawText(
        shot.title,
        rect: titleRect,
        font: NSFont.systemFont(ofSize: 64, weight: .bold),
        color: NSColor(calibratedRed: 0.83, green: 0.18, blue: 0.22, alpha: 1),
        context: context,
        alignment: .center,
        lineHeight: 72
    )

    guard let bezelImage = NSImage(contentsOf: bezelURL),
          let bezelCGImage = bezelImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "renderer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing Apple bezel image at \(bezelURL.path)"])
    }
    let bezelSize = CGSize(width: bezelCGImage.width, height: bezelCGImage.height)
    let bezelAssets = try makeBezelCompositeAssets(from: bezelCGImage)

    let inputURL = inputDir.appendingPathComponent(shot.input)
    guard let source = NSImage(contentsOf: inputURL), let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "renderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing input \(shot.input)"])
    }

    let screenshotLayer = try makeScreenshotLayer(
        screenshot: cgImage,
        bezelSize: bezelSize,
        screenBounds: bezelAssets.screenBounds,
        screenMask: bezelAssets.screenMask
    )
    let deviceComposite = try makeDeviceComposite(
        screenshotLayer: screenshotLayer,
        bezelOverlay: bezelAssets.overlay,
        bezelSize: bezelSize,
        visibleBounds: bezelAssets.visibleBounds
    )

    context.draw(deviceComposite, in: flipped(deviceFrame))

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

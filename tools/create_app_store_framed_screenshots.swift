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

let shots: [Shot] = [
    Shot(
        input: "01-top-songs.png",
        output: "01-your-music-ranked.png",
        title: "Your music, ranked",
        colors: [
            NSColor(calibratedRed: 0.97, green: 0.92, blue: 0.96, alpha: 1),
            NSColor(calibratedRed: 0.82, green: 0.91, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.83, blue: 0.58, alpha: 1)
        ]
    ),
    Shot(
        input: "02-top-albums.png",
        output: "02-albums-that-stick.png",
        title: "Albums you play most",
        colors: [
            NSColor(calibratedRed: 0.92, green: 0.96, blue: 0.99, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.73, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.86, blue: 0.78, alpha: 1)
        ]
    ),
    Shot(
        input: "03-top-artists.png",
        output: "03-top-artists.png",
        title: "Artists on repeat",
        colors: [
            NSColor(calibratedRed: 0.94, green: 0.92, blue: 1.00, alpha: 1),
            NSColor(calibratedRed: 0.82, green: 0.95, blue: 0.91, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.79, blue: 0.76, alpha: 1)
        ]
    ),
    Shot(
        input: "04-monthly-recap.png",
        output: "04-monthly-recaps.png",
        title: "Monthly recaps, made visual",
        colors: [
            NSColor(calibratedRed: 0.80, green: 0.74, blue: 0.88, alpha: 1),
            NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.88, alpha: 1),
            NSColor(calibratedRed: 0.78, green: 0.89, blue: 1.00, alpha: 1)
        ]
    )
]

let canvasSize = CGSize(width: 1320, height: 2868)
let phoneOuter = CGRect(x: 132, y: 468, width: 1056, height: 2294)
let phoneBezel = phoneOuter.insetBy(dx: 18, dy: 18)
let phoneInner = phoneOuter.insetBy(dx: 50, dy: 50)

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

    context.saveGState()
    context.setBlendMode(.softLight)
    for index in 0..<7 {
        let width = CGFloat(560 + index * 88)
        let x = CGFloat(-180 + index * 182)
        let y = CGFloat(260 + index * 238)
        let rect = CGRect(x: x, y: y, width: width, height: 250)
        let path = CGPath(roundedRect: flipped(rect), cornerWidth: 80, cornerHeight: 80, transform: nil)
        context.addPath(path)
        context.setFillColor(NSColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.20 : 0.11).cgColor)
        context.fillPath()
    }
    context.restoreGState()
}

func drawPhoneShadow(context: CGContext) {
    context.saveGState()
    let shadowRect = phoneOuter.offsetBy(dx: 0, dy: 34)
    context.setShadow(offset: CGSize(width: 0, height: -34), blur: 82, color: NSColor.black.withAlphaComponent(0.24).cgColor)
    let path = CGPath(roundedRect: flipped(shadowRect), cornerWidth: 150, cornerHeight: 150, transform: nil)
    context.addPath(path)
    context.setFillColor(NSColor.black.withAlphaComponent(0.64).cgColor)
    context.fillPath()
    context.restoreGState()
}

func drawDeviceFrame(context: CGContext) {
    func sideButton(_ rect: CGRect, radius: CGFloat) {
        let buttonPath = CGPath(roundedRect: flipped(rect), cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(buttonPath)
        context.setFillColor(NSColor(calibratedWhite: 0.09, alpha: 1).cgColor)
        context.fillPath()
    }

    context.saveGState()
    sideButton(CGRect(x: phoneOuter.minX - 13, y: phoneOuter.minY + 328, width: 14, height: 128), radius: 7)
    sideButton(CGRect(x: phoneOuter.minX - 13, y: phoneOuter.minY + 510, width: 14, height: 206), radius: 7)
    sideButton(CGRect(x: phoneOuter.maxX - 1, y: phoneOuter.minY + 456, width: 14, height: 260), radius: 7)
    context.restoreGState()

    drawRoundedRect(phoneOuter, radius: 156, color: NSColor(calibratedWhite: 0.015, alpha: 1), in: context)
    drawRoundedRect(phoneBezel, radius: 140, color: NSColor(calibratedWhite: 0.07, alpha: 1), in: context)
    drawRoundedRect(phoneInner.insetBy(dx: -7, dy: -7), radius: 124, color: NSColor(calibratedWhite: 0.012, alpha: 1), in: context)

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    context.setLineWidth(5)
    context.addPath(CGPath(roundedRect: flipped(phoneOuter.insetBy(dx: 5, dy: 5)), cornerWidth: 150, cornerHeight: 150, transform: nil))
    context.strokePath()
    context.setStrokeColor(NSColor.black.withAlphaComponent(0.42).cgColor)
    context.setLineWidth(3)
    context.addPath(CGPath(roundedRect: flipped(phoneBezel.insetBy(dx: 2, dy: 2)), cornerWidth: 136, cornerHeight: 136, transform: nil))
    context.strokePath()
    context.restoreGState()
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
        rect: CGRect(x: 86, y: 128, width: 1148, height: 150),
        font: NSFont.systemFont(ofSize: 82, weight: .black),
        color: .black,
        context: context,
        alignment: .center,
        lineHeight: 92
    )

    drawPhoneShadow(context: context)
    drawDeviceFrame(context: context)
    drawRoundedRect(phoneInner, radius: 110, color: .white, in: context)

    let inputURL = inputDir.appendingPathComponent(shot.input)
    guard let source = NSImage(contentsOf: inputURL), let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "renderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing input \(shot.input)"])
    }

    context.saveGState()
    context.addPath(CGPath(roundedRect: flipped(phoneInner), cornerWidth: 110, cornerHeight: 110, transform: nil))
    context.clip()
    context.draw(cgImage, in: flipped(phoneInner))
    context.restoreGState()

    context.saveGState()
    context.setBlendMode(.overlay)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    context.setLineWidth(3)
    context.addPath(CGPath(roundedRect: flipped(phoneInner.insetBy(dx: -3, dy: -3)), cornerWidth: 116, cornerHeight: 116, transform: nil))
    context.strokePath()
    context.restoreGState()

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

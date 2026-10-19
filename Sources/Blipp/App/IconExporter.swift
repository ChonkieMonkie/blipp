import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders the app icon into an .iconset folder (used by scripts/build.sh).
enum IconExporter {
    static func exportIconset(to path: String) throws {
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            try writePNG(renderIcon(pixels: pixels), to: folder.appendingPathComponent("\(name).png"))
        }
    }

    static func renderIcon(pixels: Int) -> CGImage {
        let context = makeContext(width: pixels, height: pixels)
        let scale = CGFloat(pixels) / 1024
        context.scaleBy(x: scale, y: scale)

        // macOS icon grid: an 824 pt rounded square centered in 1024.
        let tile = CGRect(x: 100, y: 92, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: Painter.color(0x000000, 0.25))
        context.addPath(shape)
        context.setFillColor(Painter.color(0xBFEBD8))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let colors = [Painter.color(0xEAF9F1), Painter.color(0xB4E6CF)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
        }
        context.restoreGState()

        var scene = BlippScene()
        scene.face = .sunglasses
        BlippRenderer.draw(scene, in: context, origin: CGPoint(x: 197, y: 230), size: 630, time: 0)

        return context.makeImage()!
    }

    /// A bitmap context with a top-left origin, matching the design coordinates.
    static func makeContext(width: Int, height: Int) -> CGContext {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

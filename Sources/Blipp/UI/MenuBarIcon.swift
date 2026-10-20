// Blipp, a menu bar sidekick that shows how your Mac is doing.
// Copyright (C) 2026  Anton Gedda
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit

/// Builds the status item image: Blipp, and left of him a speech bubble when something is worth
/// saying (one thing at a time, see `MoodEngine.bubble`).
///
/// The bubble's spot is always kept, empty while he has nothing to say, so the item never changes
/// width. (When it does, macOS resizes it from the left and only moves it back a frame later,
/// which made Blipp jump.) The empty spot is on the left, where it reads as ordinary spacing.
enum MenuBarIcon {
    static let height: CGFloat = 18

    /// Space between the bubble's tail and Blipp.
    private static let gap: CGFloat = 2
    private static let symbolBubbleWidth: CGFloat = 17
    private static let textFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 8, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 8) } ?? base
        let digits = rounded.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: digits, size: 8) ?? rounded
    }()
    /// Wide enough for the longest values ("888 KB/s", "Offline"), so the bubble keeps its width.
    private static let valueBubbleWidth: CGFloat = {
        let widest = ["888 KB/s", "888 Mb/s", "88.8 GB", "Offline", "100%", "888 °C"]
            .map { ($0 as NSString).size(withAttributes: [.font: textFont]).width }
            .max() ?? 30
        return (13.5 + widest + 3.5).rounded(.up)
    }()

    /// The bubble actually shown for a setting: none when off, except for emergencies.
    static func shownBubble(_ bubble: MenuBubble?, style: SpeechBubble) -> MenuBubble? {
        style == .off ? (bubble?.emergency == true ? bubble : nil) : bubble
    }

    /// The bubble's spot, tail included. Fixed per setting, whatever the bubble says.
    private static func bubbleSpot(for style: SpeechBubble, showing bubble: MenuBubble?) -> CGFloat {
        switch style {
        case .symbol: return symbolBubbleWidth + 2.6 + gap
        case .symbolAndValue: return valueBubbleWidth + 2.6 + gap
        // Off keeps no spot; a rare emergency then makes room for itself.
        case .off: return bubble?.emergency == true ? symbolBubbleWidth + 2.6 + gap : 0
        }
    }

    static func image(
        scene: BlippScene,
        style: IconStyle,
        bubble: MenuBubble?,
        bubbleStyle: SpeechBubble,
        darkMenuBar: Bool,
        time: Double
    ) -> NSImage {
        let shown = shownBubble(bubble, style: bubbleStyle)
        // With "off", an emergency still shows, as a symbol.
        let withValue = bubbleStyle == .symbolAndValue
        let mono = style == .monochrome
        // An emergency keeps its red bubble in monochrome, so that image can't be a template:
        // Blipp is then drawn in the menu bar's own text color instead.
        let template = mono && shown?.emergency != true
        let monoInk: UInt32 = template ? 0x000000 : (darkMenuBar ? 0xFFFFFF : 0x000000)
        let spot = bubbleSpot(for: bubbleStyle, showing: bubble)

        let image = NSImage(size: NSSize(width: spot + height, height: height), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            if let shown {
                drawBubble(shown, in: cg, withValue: withValue, mono: mono, monoInk: monoInk)
            }
            cg.translateBy(x: spot, y: 0)
            MenuBarRenderer.draw(scene, in: cg, size: height, template: mono, monoInk: monoInk, time: time)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = shown.map { "Blipp: \(spokenName($0.kind)) \($0.value)" } ?? "Blipp"
        return image
    }

    /// A still Blipp for the Style picker in Settings.
    static func preview(style: IconStyle) -> NSImage {
        image(scene: BlippScene(), style: style, bubble: nil, bubbleStyle: .off, darkMenuBar: false, time: MenuBarRenderer.stillTime)
    }

    private static func spokenName(_ kind: MenuBubble.Kind) -> String {
        switch kind {
        case .empty: return "battery empty"
        case .heat: return "critical heat"
        case .low: return "battery low"
        case .offline: return "offline"
        case .swap: return "swapping"
        case .memory: return "memory high"
        case .charging: return "charging"
        case .download: return "downloading"
        case .upload: return "uploading"
        case .disk: return "disk busy"
        }
    }

    // MARK: Bubble

    private static func drawBubble(_ bubble: MenuBubble, in cg: CGContext, withValue: Bool, mono: Bool, monoInk: UInt32) {
        let p = Painter(cg: cg)
        let bx: CGFloat = 0.5
        let w = withValue ? valueBubbleWidth : symbolBubbleWidth
        // A rounded box with its tail at the bottom right, pointing at Blipp.
        let r = bx + w
        let path = "M\(bx + 4) 2H\(r - 4)A4 4 0 0 1 \(r) 6V11A4 4 0 0 1 \(r - 0.6) 12.6L\(r + 1.6) 16.6L\(r - 4.5) 15H\(bx + 4)A4 4 0 0 1 \(bx) 11V6A4 4 0 0 1 \(bx + 4) 2Z"

        // Colors: red for emergencies (even in monochrome), the panel's colors otherwise,
        // or plain ink for a monochrome template.
        let palette: SymbolColors
        if bubble.emergency {
            p.shape(path, fill: 0xFFF0F0, stroke: Palette.red, width: 0.8)
            palette = SymbolColors(all: Palette.red)
        } else if mono {
            p.stroke(path, monoInk, width: 0.8)
            palette = SymbolColors(all: monoInk, outlineOnly: true)
        } else {
            p.shape(path, fill: Palette.white, stroke: Palette.ink, width: 0.8)
            palette = .color
        }

        let center = withValue ? CGPoint(x: bx + 7.2, y: 8.5) : CGPoint(x: bx + w / 2, y: 8.5)
        let scale: CGFloat = withValue ? 1.25 : 1.35
        p.group(CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)) {
            drawSymbol(bubble.kind, p, palette)
        }

        if withValue {
            let textColor: NSColor = bubble.emergency
                ? NSColor(srgbRed: 0.78, green: 0.09, blue: 0.11, alpha: 1)
                : (mono ? nsColor(monoInk) : nsColor(Palette.ink))
            drawValue(bubble.value, in: cg, x: bx + 13.5, maxWidth: w - 13.5 - 2.5, color: textColor)
        }
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(cgColor: Painter.color(hex)) ?? .black
    }

    private static func drawValue(_ text: String, in cg: CGContext, x: CGFloat, maxWidth: CGFloat, color: NSColor) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        defer { NSGraphicsContext.current = previous }
        var font = textFont
        var string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        // Rare long values shrink a little rather than spill out of the bubble.
        while string.size().width > maxWidth, font.pointSize > 6 {
            font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize - 0.5) ?? font
            string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        let size = string.size()
        string.draw(at: CGPoint(x: x, y: 8.5 - size.height / 2))
    }

    private struct SymbolColors {
        var ink: UInt32 = Palette.ink
        var red: UInt32 = Palette.red
        var download: UInt32 = Palette.download
        var upload: UInt32 = Palette.upload
        var write: UInt32 = Palette.write
        var bolt: UInt32 = Palette.juice
        var balls: [UInt32] = [Palette.ballPink, Palette.download, 0xEAB308]
        var box: (front: UInt32, top: UInt32, side: UInt32, tape: UInt32, label: UInt32)? =
            (Palette.cardboard, Palette.cardboardLight, Palette.cardboardDark, Palette.tape, Palette.white)

        static let color = SymbolColors()

        init() {}

        init(all hex: UInt32, outlineOnly: Bool = false) {
            ink = hex
            red = hex
            download = hex
            upload = hex
            write = hex
            bolt = hex
            balls = [hex, hex, hex]
            box = outlineOnly ? nil : (0xFFE3E3, 0xFFF0F0, 0xFFD2D2, 0xFFF0F0, 0xFFFFFF)
        }
    }

    /// The bubble's symbols, in a ±3 point box around their center.
    private static func drawSymbol(_ kind: MenuBubble.Kind, _ p: Painter, _ c: SymbolColors) {
        switch kind {
        case .memory:
            for (index, (x, y)) in [(-1.9, 1.0), (0.0, -1.3), (1.9, 1.0)].enumerated() {
                p.circle(CGFloat(x), CGFloat(y), 1, fill: c.balls[index])
            }
        case .download:
            p.stroke("M0 -2.5V2.2M-1.8 0.5L0 2.4L1.8 0.5", c.download, width: 1.2)
        case .upload:
            p.stroke("M0 2.5V-2.2M-1.8 -0.5L0 -2.4L1.8 -0.5", c.upload, width: 1.2)
        case .disk:
            p.stroke("M-1.2 -2.4H1.2A0.6 0.6 0 0 1 1.8 -1.8V1.8A0.6 0.6 0 0 1 1.2 2.4H-1.2A0.6 0.6 0 0 1 -1.8 1.8V-1.8A0.6 0.6 0 0 1 -1.2 -2.4Z", c.ink, width: 0.7)
            p.stroke("M-0.9 -0.9H0.9M-0.9 0.4H0.9M-0.9 1.6H0.3", c.write, width: 0.6)
        case .offline:
            p.stroke("M-2.7 1.4A1.4 1.4 0 0 1 -1.7 -0.9A1.9 1.9 0 0 1 1.8 -1.1A1.4 1.4 0 0 1 2.7 1.4Z", c.ink, width: 0.7)
            p.stroke("M-2.4 2.6L2.4 -2.6", c.red, width: 1)
        case .low, .empty:
            p.stroke("M-2.1 -1.4H1.4A0.6 0.6 0 0 1 2 -0.8V0.8A0.6 0.6 0 0 1 1.4 1.4H-2.1A0.6 0.6 0 0 1 -2.7 0.8V-0.8A0.6 0.6 0 0 1 -2.1 -1.4Z", c.red, width: 0.8)
            p.fill("M2.1 -0.6H2.8V0.6H2.1Z", c.red)
            if kind == .low {
                p.fill("M-2.1 -0.8H-0.9V0.8H-2.1Z", c.red)
            } else {
                p.stroke("M-0.35 -0.75V0.2M-0.35 0.75V0.8", c.red, width: 0.6)
            }
        case .heat:
            p.stroke("M-0.75 -2.25A0.75 0.75 0 0 1 0.75 -2.25V0.65A0.75 0.75 0 0 1 -0.75 0.65Z", c.red, width: 0.7)
            p.circle(0, 1.9, 1.35, fill: c.red)
            p.stroke("M0 -0.8V1.5", c.red, width: 0.7)
        case .swap:
            p.group(CGAffineTransform(translationX: -0.1, y: -0.4)) {
                let top = "M-3.4 -0.6L-2 -2H3.6L2.2 -0.6Z"
                let side = "M2.2 -0.6L3.6 -2V1.6L2.2 3Z"
                let front = "M-3.4 -0.6H2.2V3H-3.4Z"
                if let box = c.box {
                    p.shape(top, fill: box.top, stroke: c.ink, width: 0.4)
                    p.shape(side, fill: box.side, stroke: c.ink, width: 0.4)
                    p.shape(front, fill: box.front, stroke: c.ink, width: 0.5)
                    p.fill("M-1.05 -0.6L0.35 -2H1.35L-0.05 -0.6Z", box.tape)
                    p.fill("M-1.05 -0.6H-0.05V3H-1.05Z", box.tape)
                    p.shape("M0.45 0.6H1.8V1.6H0.45Z", fill: box.label, stroke: c.ink, width: 0.25)
                } else {
                    p.stroke(top, c.ink, width: 0.45)
                    p.stroke(side, c.ink, width: 0.45)
                    p.stroke(front, c.ink, width: 0.5)
                    p.stroke("M-0.55 -0.6V3", c.ink, width: 0.35)
                }
                p.stroke("M-2.3 2.2V0.4M-2.9 1L-2.3 0.35L-1.7 1", c.ink, width: 0.3)
            }
        case .charging:
            p.shape("M0.7 -2.9L-1.7 0.4H-0.1L-0.8 2.9L1.7 -0.5H0.1Z", fill: c.bolt, stroke: c.ink, width: 0.45)
        }
    }
}

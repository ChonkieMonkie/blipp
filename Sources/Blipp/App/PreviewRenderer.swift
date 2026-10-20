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
import SwiftUI

/// Developer tool: `Blipp --render-gallery <folder>` writes PNGs of every Blipp state,
/// the menu bar icons and the live panel, so the artwork can be checked without clicking around.
@MainActor
enum PreviewRenderer {
    static let states: [(String, BlippScene)] = {
        func scene(_ build: (inout BlippScene) -> Void) -> BlippScene {
            var scene = BlippScene()
            build(&scene)
            return scene
        }
        return [
            ("Sleeping", scene { $0.color = Palette.chilly; $0.face = .sleeping; $0.head = .zzz }),
            ("Chilling", scene { $0.face = .smile }),
            ("Sunglasses", scene { $0.face = .sunglasses }),
            ("Busy", scene { $0.face = .focused; $0.work = .light; $0.head = .gear }),
            ("Straining", scene { $0.face = .sweaty; $0.work = .strong }),
            ("Maxed out", scene { $0.face = .panic; $0.work = .strong; $0.shake = true }),
            ("Warm", scene { $0.color = Palette.warm }),
            ("Hot", scene { $0.color = Palette.orange; $0.heat = .sweat }),
            ("Very hot", scene { $0.color = Palette.hot; $0.heat = .steam }),
            ("Memory busy", scene { $0.head = .juggle3 }),
            ("Memory high", scene { $0.head = .juggle5 }),
            ("Swapping", scene { $0.head = .swapBox }),
            ("Downloading", scene { $0.network = .download }),
            ("Uploading", scene { $0.network = .upload }),
            ("Both ways", scene { $0.network = .both }),
            ("Offline", scene { $0.network = .offline }),
            ("Reading", scene { $0.disk = .read }),
            ("Writing", scene { $0.disk = .write }),
            ("Reading + writing", scene { $0.disk = .both }),
            ("Charging", scene { $0.sticker = .juice }),
            ("Cookie", scene { $0.sticker = .cookie }),
            ("Charge limit", scene { $0.sticker = .limit }),
            ("Low battery", scene { $0.sticker = .low }),
            ("Battery empty", scene { $0.shape = .puddle; $0.color = Palette.melted; $0.face = .dead; $0.sticker = .low }),
            ("Critical heat", scene { $0.color = Palette.boiling; $0.face = .boiling; $0.heat = .fire; $0.shake = true }),
            // Everything at once, to check nothing overlaps.
            ("Everything", scene {
                $0.color = Palette.orange; $0.face = .panic; $0.work = .strong; $0.heat = .sweat; $0.head = .swapBox
                $0.network = .both; $0.disk = .both; $0.sticker = .juice
            }),
            ("Busy day", scene {
                $0.color = Palette.warm; $0.face = .focused; $0.work = .light; $0.head = .juggle3
                $0.network = .download; $0.disk = .write; $0.sticker = .cookie
            }),
        ]
    }()

    static func renderGallery(to path: String) {
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Full-size states
        let columns = 6
        let cell = 200
        let rows = (states.count + columns - 1) / columns
        let context = IconExporter.makeContext(width: columns * cell, height: rows * cell)
        // Checkerboard, so anything that should be see-through shows up as such.
        for row in 0..<(rows * cell / 20) {
            for column in 0..<(columns * cell / 20) {
                context.setFillColor(Painter.color((row + column) % 2 == 0 ? 0xF5F7FA : 0xC9D2E0))
                context.fill(CGRect(x: column * 20, y: row * 20, width: 20, height: 20))
            }
        }
        for (index, (_, scene)) in states.enumerated() {
            let x = CGFloat(index % columns * cell)
            let y = CGFloat(index / columns * cell)
            BlippRenderer.draw(scene, in: context, origin: CGPoint(x: x + 36, y: y + 52), size: 128, time: 0.4)
        }
        try? IconExporter.writePNG(context.makeImage()!, to: folder.appendingPathComponent("states.png"))

        // Menu bar icons at 4×, color on dark and light, then monochrome.
        let iconScale: CGFloat = 4
        let iconCell = Int(30 * iconScale)
        let iconRows = 3
        let menu = IconExporter.makeContext(width: states.count * iconCell, height: iconRows * iconCell)
        for row in 0..<iconRows {
            let background: UInt32 = row == 1 ? 0xF2F3F5 : 0x1A2232
            menu.setFillColor(Painter.color(background))
            menu.fill(CGRect(x: 0, y: row * iconCell, width: states.count * iconCell, height: iconCell))
        }
        for (index, (_, scene)) in states.enumerated() {
            for row in 0..<iconRows {
                menu.saveGState()
                menu.translateBy(x: CGFloat(index * iconCell) + 6 * iconScale, y: CGFloat(row * iconCell) + 6 * iconScale)
                menu.scaleBy(x: iconScale, y: iconScale)
                if row == 2 {
                    // Monochrome: render as a template and tint white like the dark menu bar does.
                    menu.beginTransparencyLayer(auxiliaryInfo: nil)
                    MenuBarRenderer.draw(scene, in: menu, size: 18, template: true, time: MenuBarRenderer.stillTime)
                    menu.setBlendMode(.sourceIn)
                    menu.setFillColor(Painter.color(0xFFFFFF))
                    menu.fill(CGRect(x: -2, y: -2, width: 22, height: 22))
                    menu.endTransparencyLayer()
                } else {
                    MenuBarRenderer.draw(scene, in: menu, size: 18, template: false, time: MenuBarRenderer.stillTime)
                }
                menu.restoreGState()
            }
        }
        try? IconExporter.writePNG(menu.makeImage()!, to: folder.appendingPathComponent("menubar.png"))

        renderBubbles(to: folder.appendingPathComponent("bubbles.png"))

        try? IconExporter.writePNG(IconExporter.renderIcon(pixels: 512), to: folder.appendingPathComponent("icon.png"))

        renderPanel(to: folder.appendingPathComponent("panel.png"))
    }

    /// Every speech bubble the menu bar can show, in both bubble styles, in color and monochrome,
    /// on a dark and a light menu bar, at 4×.
    private static func renderBubbles(to url: URL) {
        let bubbles: [(MenuBubble, BlippScene)] = {
            let calm = BlippScene()
            var melted = BlippScene()
            melted.shape = .puddle
            melted.color = Palette.melted
            melted.face = .dead
            var boiling = BlippScene()
            boiling.color = Palette.boiling
            boiling.face = .boiling
            boiling.heat = .fire
            return [
                (MenuBubble(kind: .empty, value: "3%", emergency: true), melted),
                (MenuBubble(kind: .heat, value: "104 °C", emergency: true), boiling),
                (MenuBubble(kind: .low, value: "15%"), calm),
                (MenuBubble(kind: .offline, value: "Offline"), calm),
                (MenuBubble(kind: .swap, value: "6.1 GB"), calm),
                (MenuBubble(kind: .memory, value: "82%"), calm),
                (MenuBubble(kind: .charging, value: "64%"), calm),
                (MenuBubble(kind: .download, value: "12.4 MB/s"), calm),
                (MenuBubble(kind: .upload, value: "880 KB/s"), calm),
                (MenuBubble(kind: .disk, value: "180 MB/s"), calm),
            ]
        }()
        let scale: CGFloat = 4
        let cellWidth = MenuBarIcon.image(scene: BlippScene(), style: .color, bubble: nil, bubbleStyle: .symbolAndValue, darkMenuBar: true, time: 0).size.width + 8
        let rows: [(SpeechBubble, IconStyle, Bool)] = [
            (.symbol, .color, true), (.symbol, .color, false), (.symbolAndValue, .color, true), (.symbolAndValue, .color, false),
            (.symbol, .monochrome, true), (.symbolAndValue, .monochrome, true), (.symbolAndValue, .monochrome, false),
        ]
        let rowHeight: CGFloat = 26
        let width = Int(CGFloat(bubbles.count) * cellWidth * scale)
        let height = Int(CGFloat(rows.count) * rowHeight * scale)
        let context = IconExporter.makeContext(width: width, height: height)
        context.scaleBy(x: scale, y: scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }
        for (row, (bubbleStyle, style, dark)) in rows.enumerated() {
            let top = CGFloat(row) * rowHeight
            context.setFillColor(Painter.color(dark ? 0x1A2232 : 0xF2F3F5))
            context.fill(CGRect(x: 0, y: top, width: CGFloat(bubbles.count) * cellWidth, height: rowHeight))
            for (index, (bubble, scene)) in bubbles.enumerated() {
                let image = MenuBarIcon.image(scene: scene, style: style, bubble: bubble, bubbleStyle: bubbleStyle, darkMenuBar: dark, time: MenuBarRenderer.stillTime)
                let rect = CGRect(x: CGFloat(index) * cellWidth + 4, y: top + 4, width: image.size.width, height: image.size.height)
                if image.isTemplate {
                    // Tint like the menu bar does: white on dark, black on light.
                    context.beginTransparencyLayer(auxiliaryInfo: nil)
                    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    context.setBlendMode(.sourceIn)
                    context.setFillColor(Painter.color(dark ? 0xFFFFFF : 0x000000))
                    context.fill(rect.insetBy(dx: -2, dy: -2))
                    context.endTransparencyLayer()
                } else {
                    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
        }
        try? IconExporter.writePNG(context.makeImage()!, to: url)
    }

    /// Runs the real monitor for a few seconds, then snapshots the panel with everything expanded.
    private static func renderPanel(to url: URL) {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "io.github.chonkiemonkie.blipp.preview") ?? .standard)
        prefs.graphInterval = 0.5
        let monitor = SystemMonitor(prefs: prefs)
        RunLoop.main.run(until: Date().addingTimeInterval(4))

        let view = PanelPreview(monitor: monitor, prefs: prefs)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.cgImage {
            try? IconExporter.writePNG(image, to: url)
        }
    }
}

/// The panel with both sections open, for previews only.
private struct PanelPreview: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var prefs: Preferences

    var body: some View {
        PanelView(
            monitor: monitor,
            prefs: prefs,
            actions: PanelActions(openActivityMonitor: {}, openSettings: {}, quit: {}),
            startExpanded: true
        )
    }
}

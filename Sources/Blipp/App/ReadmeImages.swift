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

/// Developer tool: `Blipp --render-readme <folder>` renders the still pictures used in
/// README.md: every signal from calm to extreme, the menu bar with its speech bubble, the app
/// icon, and the real panel in light and dark mode (sampled from this Mac for 65 s, so the
/// one-minute graphs are full). The animations come from `ReadmeAnimations`.
@MainActor
enum ReadmeImages {
    static func render(to path: String) {
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        renderSignals(to: folder.appendingPathComponent("signals.png"))
        renderMenuBar(to: folder.appendingPathComponent("menubar.png"))
        try? IconExporter.writePNG(IconExporter.renderIcon(pixels: 512), to: folder.appendingPathComponent("icon.png"))
        renderPanels(into: folder)
    }

    // MARK: Scenes

    private static func scene(_ build: (inout BlippScene) -> Void) -> BlippScene {
        var scene = BlippScene()
        build(&scene)
        return scene
    }

    // MARK: Signals

    /// One row per signal, from calm to extreme, each on the part of Blipp it owns.
    private static let signals: [(String, String, [(String, BlippScene)])] = [
        ("CPU", "Face and speed lines", [
            ("Sleeping", scene { $0.face = .sleeping; $0.head = .zzz }),
            ("Chilling", scene { $0.face = .smile }),
            ("Busy", scene { $0.face = .focused; $0.work = .light; $0.head = .gear }),
            ("Straining", scene { $0.face = .sweaty; $0.work = .strong }),
            ("Maxed out", scene { $0.face = .panic; $0.work = .strong }),
        ]),
        ("Temperature", "Body color, sweat and steam", [
            ("Chilly", scene { $0.color = Palette.chilly }),
            ("Cool", scene { _ in }),
            ("Warm", scene { $0.color = Palette.warm }),
            ("Hot", scene { $0.color = Palette.orange; $0.heat = .sweat }),
            ("Very hot", scene { $0.color = Palette.hot; $0.heat = .steam }),
            ("Critical", scene { $0.color = Palette.boiling; $0.face = .boiling; $0.heat = .fire }),
        ]),
        ("Memory", "Above his head", [
            ("Plenty", scene { _ in }),
            ("Busy", scene { $0.head = .juggle3 }),
            ("High", scene { $0.head = .juggle5 }),
            ("Swapping", scene { $0.head = .swapBox }),
        ]),
        ("Network", "Left hand", [
            ("Downloading", scene { $0.network = .download }),
            ("Uploading", scene { $0.network = .upload }),
            ("Both ways", scene { $0.network = .both }),
            ("Offline", scene { $0.network = .offline }),
        ]),
        ("Disk", "Right hand", [
            ("Reading", scene { $0.disk = .read }),
            ("Writing", scene { $0.disk = .write }),
            ("Both", scene { $0.disk = .both }),
        ]),
        ("Battery", "At his feet", [
            ("Charging", scene { $0.sticker = .juice }),
            ("Charge limit", scene { $0.sticker = .limit }),
            ("Low", scene { $0.sticker = .low }),
            ("Empty", scene { $0.shape = .puddle; $0.color = Palette.melted; $0.face = .dead; $0.sticker = .low }),
        ]),
    ]

    private static func renderSignals(to url: URL) {
        let scale: CGFloat = 2
        let labelWidth: CGFloat = 196
        let cellWidth: CGFloat = 122
        let rowHeight: CGFloat = 136
        let gap: CGFloat = 10
        let columns = signals.map(\.2.count).max() ?? 0
        let width = labelWidth + CGFloat(columns) * cellWidth + 12
        let height = CGFloat(signals.count) * rowHeight + CGFloat(signals.count - 1) * gap

        let context = IconExporter.makeContext(width: Int(width * scale), height: Int(height * scale))
        context.scaleBy(x: scale, y: scale)
        for (row, (name, part, states)) in signals.enumerated() {
            let top = CGFloat(row) * (rowHeight + gap)
            card(in: context, CGRect(x: 0, y: top, width: width, height: rowHeight))
            drawLabel(name, in: context, x: 22, y: top + rowHeight / 2 - 22, size: 18)
            drawLabel(part, in: context, x: 22, y: top + rowHeight / 2 + 2, size: 13, weight: .regular, color: secondaryText)
            for (column, (label, scene)) in states.enumerated() {
                let x = labelWidth + CGFloat(column) * cellWidth
                let size: CGFloat = 68
                BlippRenderer.draw(scene, in: context, origin: CGPoint(x: x + (cellWidth - size) / 2, y: top + 24), size: size, time: 0.4)
                drawLabel(label, in: context, centerX: x + cellWidth / 2, y: top + rowHeight - 30, size: 13)
            }
        }
        try? IconExporter.writePNG(context.makeImage()!, to: url)
    }

    // MARK: Drawing helpers

    private static let primaryText = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.2, alpha: 1)
    private static let secondaryText = NSColor(srgbRed: 0.42, green: 0.46, blue: 0.53, alpha: 1)

    private static func card(in context: CGContext, _ rect: CGRect) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20, transform: nil))
        context.setFillColor(Painter.color(0xF5F7FA))
        context.fillPath()
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        return NSAttributedString(string: text, attributes: [.font: rounded, .foregroundColor: color])
    }

    private static func drawLabel(_ text: String, in context: CGContext, centerX: CGFloat? = nil, x: CGFloat = 0, y: CGFloat,
                                  size: CGFloat = 15, weight: NSFont.Weight = .semibold, color: NSColor? = nil) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }
        let string = label(text, size: size, weight: weight, color: color ?? primaryText)
        let left = centerX.map { $0 - string.size().width / 2 } ?? x
        string.draw(at: CGPoint(x: left, y: y))
    }

    // MARK: Menu bar

    /// Slices of a menu bar with Blipp and his speech bubble, at 2× scale: symbols on a dark and
    /// a light menu bar, then symbols with values, then monochrome.
    private static func renderMenuBar(to url: URL) {
        let calm = BlippScene()
        let items: [(BlippScene, MenuBubble?)] = [
            (calm, nil),
            (scene { $0.face = .focused; $0.work = .light; $0.network = .download }, MenuBubble(kind: .download, value: "12.4 MB/s")),
            (scene { $0.head = .juggle5 }, MenuBubble(kind: .memory, value: "86%")),
            (scene { $0.sticker = .juice }, MenuBubble(kind: .charging, value: "64%")),
            (scene { $0.sticker = .low }, MenuBubble(kind: .low, value: "15%")),
            (scene { $0.network = .offline }, MenuBubble(kind: .offline, value: "Offline")),
            (scene { $0.color = Palette.boiling; $0.face = .boiling; $0.heat = .fire }, MenuBubble(kind: .heat, value: "104 °C", emergency: true)),
        ]
        let rows: [(SpeechBubble, IconStyle, Bool)] = [
            (.symbol, .color, true), (.symbol, .color, false), (.symbolAndValue, .color, true), (.symbol, .monochrome, false),
        ]
        let scale: CGFloat = 2
        let barHeight: CGFloat = 26
        let rowGap: CGFloat = 8
        let padding: CGFloat = 12
        let itemGap: CGFloat = 12

        func images(_ bubbleStyle: SpeechBubble, _ style: IconStyle, _ dark: Bool) -> [NSImage] {
            items.map { scene, bubble in
                var shown = MenuBarIcon.shownBubble(bubble, style: bubbleStyle)
                if bubbleStyle != .symbolAndValue { shown?.value = "" }
                return MenuBarIcon.image(scene: scene, style: style, bubble: shown, bubbleStyle: bubbleStyle,
                                         darkMenuBar: dark, time: MenuBarRenderer.stillTime)
            }
        }
        let rendered = rows.map { images($0.0, $0.1, $0.2) }
        func rowWidth(_ images: [NSImage]) -> CGFloat {
            let icons: CGFloat = images.reduce(0) { $0 + $1.size.width }
            return padding * 2 + icons + CGFloat(images.count - 1) * itemGap
        }
        let width: CGFloat = rendered.map(rowWidth).max() ?? 0
        let height = CGFloat(rows.count) * barHeight + CGFloat(rows.count - 1) * rowGap

        let context = IconExporter.makeContext(width: Int(width * scale), height: Int(height * scale))
        context.scaleBy(x: scale, y: scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }
        for (row, (_, _, dark)) in rows.enumerated() {
            let top = CGFloat(row) * (barHeight + rowGap)
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: top, width: width, height: barHeight), cornerWidth: 7, cornerHeight: 7, transform: nil))
            context.setFillColor(Painter.color(dark ? 0x1E2433 : 0xEEF0F3))
            context.fillPath()
            // Right-aligned, like the right end of a real menu bar.
            var x = width - padding
            for image in rendered[row].reversed() {
                x -= image.size.width
                let rect = CGRect(x: x, y: top + (barHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
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
                x -= itemGap
            }
        }
        try? IconExporter.writePNG(context.makeImage()!, to: url)
    }

    // MARK: Panel

    private static func renderPanels(into folder: URL) {
        let defaults = UserDefaults(suiteName: "io.github.chonkiemonkie.blipp.readme") ?? .standard
        let prefs = Preferences(defaults: defaults)
        prefs.graphInterval = 0.5
        prefs.graphSpan = 60
        prefs.networkUnit = .bytes
        let monitor = SystemMonitor(prefs: prefs)
        // Generic examples, so the pictures never show the processes of whoever renders them.
        monitor.useExampleProcesses([
            ProcessUsage(pid: 1, name: "Safari", cpu: 9),
            ProcessUsage(pid: 2, name: "Music", cpu: 4),
            ProcessUsage(pid: 3, name: "Mail", cpu: 2),
        ])
        // A few downloads with a little upload alongside, and disk bursts, quiet at the end so
        // Blipp's mood in the picture isn't about traffic.
        let start = ProcessInfo.processInfo.systemUptime
        monitor.useExampleTraffic { now in
            let t = now - start
            func burst(_ at: Double, _ width: Double, _ height: Double) -> Double {
                max(0, 1 - abs(t - at) / width) * height
            }
            let down = 30_000 + burst(12, 2, 3_800_000) + burst(31, 3, 2_400_000) + burst(48, 2, 4_500_000)
            let up = 8_000 + burst(13, 2, 600_000) + burst(32, 4, 1_400_000) + burst(49, 1.5, 500_000)
            let read = 150_000 + burst(8, 1.5, 22_000_000) + burst(33, 2, 14_000_000)
            let write = 200_000 + burst(20, 2, 9_000_000) + burst(40, 3, 16_000_000) + burst(56, 1.5, 6_000_000)
            return (down, up, read, write)
        }
        monitor.setPanelVisible(true)
        RunLoop.main.run(until: Date().addingTimeInterval(65))

        for (name, appearance) in [("panel-light.png", NSAppearance.Name.aqua), ("panel-dark.png", NSAppearance.Name.darkAqua)] {
            if let image = snapshotPanel(monitor: monitor, prefs: prefs, appearance: appearance) {
                try? IconExporter.writePNG(image, to: folder.appendingPathComponent(name))
            }
        }
    }

    /// Draws the real panel (AppKit controls, Blipp's layer and all) in an offscreen window.
    private static func snapshotPanel(monitor: SystemMonitor, prefs: Preferences, appearance: NSAppearance.Name) -> CGImage? {
        let panel = PanelView(
            monitor: monitor,
            prefs: prefs,
            actions: PanelActions(openActivityMonitor: {}, openSettings: {}, quit: {}),
            startExpanded: true
        )
        .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: panel)
        hosting.appearance = NSAppearance(named: appearance)
        let height = max(300, hosting.fittingSize.height)
        let frame = NSRect(x: 0, y: 0, width: 344, height: height)
        hosting.frame = frame

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        hosting.layoutSubtreeIfNeeded()
        hosting.display()

        defer { window.orderOut(nil) }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap.cgImage
    }
}

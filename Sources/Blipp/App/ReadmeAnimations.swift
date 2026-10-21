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

/// Developer tool: `Blipp --render-animations <folder>` writes the frames of the README's two
/// animations, `states/` (Blipp going through his states) and `demo/` (the app in a menu bar,
/// opening its panel). Each folder gets numbered PNGs and a `delays.txt` in hundredths of a
/// second; `scripts/make-gif.py` turns a folder into a GIF.
@MainActor
enum ReadmeAnimations {
    static func render(to path: String) {
        let folder = URL(fileURLWithPath: path)
        renderStates(into: folder.appendingPathComponent("states"))
        renderDemo(into: folder.appendingPathComponent("demo"))
    }

    // MARK: Frames

    private final class FrameWriter {
        private let folder: URL
        private var delays: [Int] = []

        init(folder: URL) {
            self.folder = folder
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        func add(_ image: CGImage, seconds: Double) {
            let name = String(format: "frame-%04d.png", delays.count)
            try? IconExporter.writePNG(image, to: folder.appendingPathComponent(name))
            delays.append(max(2, Int((seconds * 100).rounded())))
        }

        func finish() {
            let text = delays.map(String.init).joined(separator: "\n") + "\n"
            try? text.write(to: folder.appendingPathComponent("delays.txt"), atomically: true, encoding: .utf8)
        }
    }

    private static let scale: CGFloat = 2
    private static let frameTime = 0.08

    private static func scene(_ build: (inout BlippScene) -> Void) -> BlippScene {
        var scene = BlippScene()
        build(&scene)
        return scene
    }

    // MARK: States

    private struct State {
        var title: String
        var headline: String
        var scene: BlippScene
        var bubble: MenuBubble?
        var intro: BlippIntro.Kind
    }

    /// A day in Blipp's life, from a quiet night to his worst moments.
    private static let states: [State] = [
        State(title: "Sleeping", headline: "Dreaming of electric sheep",
              scene: scene { $0.color = Palette.chilly; $0.face = .sleeping; $0.head = .zzz }, intro: .stretch),
        State(title: "Chilling", headline: "Cool as a cucumber", scene: scene { $0.face = .smile }, intro: .wave),
        State(title: "Busy", headline: "In the zone",
              scene: scene { $0.face = .focused; $0.work = .light; $0.head = .gear }, intro: .nod),
        State(title: "Downloading", headline: "Special delivery!",
              scene: scene { $0.face = .focused; $0.work = .light; $0.head = .gear; $0.network = .download },
              bubble: MenuBubble(kind: .download, value: "12.4 MB/s"), intro: .hop),
        State(title: "Writing to disk", headline: "Scribbling away",
              scene: scene { $0.face = .smile; $0.disk = .write }, bubble: MenuBubble(kind: .disk, value: "180 MB/s"), intro: .heart),
        State(title: "Memory high", headline: "Juggling way too much",
              scene: scene { $0.face = .smile; $0.head = .juggle5 }, bubble: MenuBubble(kind: .memory, value: "86%"), intro: .toss),
        State(title: "Swapping", headline: "Moving boxes to the basement",
              scene: scene { $0.face = .sweaty; $0.work = .strong; $0.head = .swapBox }, bubble: MenuBubble(kind: .swap, value: "6.1 GB"), intro: .wipe),
        State(title: "Charging", headline: "Mmm, juice!",
              scene: scene { $0.face = .smile; $0.sticker = .juice }, bubble: MenuBubble(kind: .charging, value: "64%"), intro: .slurp),
        State(title: "Running hot", headline: "Breaking a sweat!",
              scene: scene { $0.color = Palette.orange; $0.face = .sweaty; $0.work = .strong; $0.heat = .sweat }, intro: .wipe),
        State(title: "Maxed out", headline: "Full throttle!",
              scene: scene { $0.color = Palette.hot; $0.face = .panic; $0.work = .strong; $0.heat = .steam; $0.shake = true }, intro: .shiver),
        State(title: "Critical heat", headline: "Somebody call the fan!",
              scene: scene { $0.color = Palette.boiling; $0.face = .boiling; $0.heat = .fire; $0.shake = true },
              bubble: MenuBubble(kind: .heat, value: "104 °C", emergency: true), intro: .shiver),
        State(title: "Battery empty", headline: "Melting… I need power!",
              scene: scene { $0.shape = .puddle; $0.color = Palette.melted; $0.face = .dead; $0.sticker = .low; $0.bobPeriod = 3 },
              bubble: MenuBubble(kind: .empty, value: "3%", emergency: true), intro: .lookAround),
    ]

    private static func renderStates(into folder: URL) {
        let writer = FrameWriter(folder: folder)
        let width: CGFloat = 600
        let height: CGFloat = 330
        let perState = 2.2
        let framesPerState = Int((perState / frameTime).rounded())

        for (index, state) in states.enumerated() {
            for frame in 0..<framesPerState {
                let local = Double(frame) * frameTime
                let time = Double(index) * perState + local
                let context = IconExporter.makeContext(width: Int(width * scale), height: Int(height * scale))
                context.scaleBy(x: scale, y: scale)

                context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerWidth: 24, cornerHeight: 24, transform: nil))
                context.setFillColor(Painter.color(0xF5F7FA))
                context.fillPath()

                let intro = local < BlippIntro.duration ? BlippIntro(kind: state.intro, progress: local / BlippIntro.duration) : nil
                BlippRenderer.draw(state.scene, in: context, origin: CGPoint(x: 52, y: 92), size: 150, time: time, intro: intro)

                let left: CGFloat = 268
                drawText(state.title, in: context, x: left, y: 70, size: 30)
                drawText("“\(state.headline)”", in: context, x: left, y: 112, size: 16, weight: .regular, color: secondaryText)

                drawText("IN THE MENU BAR", in: context, x: left, y: 170, size: 11, weight: .semibold, color: secondaryText)
                // Half again as big as the real thing, so the symbols read in the README.
                context.saveGState()
                context.translateBy(x: left, y: 190)
                context.scaleBy(x: 1.5, y: 1.5)
                drawMenuBar(in: context, rect: CGRect(x: 0, y: 0, width: 200, height: 26), scene: state.scene,
                            bubble: state.bubble, time: time)
                context.restoreGState()

                // Where we are in the day.
                let dot: CGFloat = 7
                let spacing: CGFloat = 14
                let dotsWidth = CGFloat(states.count - 1) * spacing + dot
                for i in states.indices {
                    let x = (width - dotsWidth) / 2 + CGFloat(i) * spacing
                    context.addEllipse(in: CGRect(x: x, y: height - 34, width: dot, height: dot))
                    context.setFillColor(Painter.color(i == index ? 0x1B2433 : 0xCDD3DC))
                    context.fillPath()
                }

                writer.add(context.makeImage()!, seconds: frameTime)
            }
        }
        writer.finish()
    }

    /// A slice of a dark menu bar with Blipp and his bubble at the right end, next to a clock.
    private static func drawMenuBar(in context: CGContext, rect: CGRect, scene: BlippScene, bubble: MenuBubble?, time: Double) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.setFillColor(Painter.color(0x1E2433))
        context.fillPath()

        let clock = label("9:41", size: 13, weight: .medium, color: .white)
        let clockX = rect.maxX - 12 - clock.size().width
        withAppKit(context) { clock.draw(at: CGPoint(x: clockX, y: rect.midY - clock.size().height / 2)) }

        var shown = MenuBarIcon.shownBubble(bubble, style: .symbol)
        shown?.value = ""
        let image = MenuBarIcon.image(scene: scene, style: .color, bubble: shown, bubbleStyle: .symbol, darkMenuBar: true, time: time)
        let iconRect = CGRect(x: clockX - 14 - image.size.width, y: rect.midY - image.size.height / 2,
                              width: image.size.width, height: image.size.height)
        withAppKit(context) {
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: Demo

    /// The real app: Blipp in a menu bar, a download starts, his bubble pops up, the panel opens
    /// with its greeting and live graphs, then closes again as the download finishes.
    private static func renderDemo(into folder: URL) {
        let defaults = UserDefaults(suiteName: "io.github.chonkiemonkie.blipp.readme") ?? .standard
        let prefs = Preferences(defaults: defaults)
        prefs.graphInterval = 0.5
        prefs.graphSpan = 60
        prefs.moodInterval = 1
        prefs.speechBubble = .symbol
        prefs.networkUnit = .bytes
        prefs.iconStyle = .color
        prefs.animateMenuBar = true
        let monitor = SystemMonitor(prefs: prefs)
        monitor.useExampleProcesses([
            ProcessUsage(pid: 1, name: "Safari", cpu: 9),
            ProcessUsage(pid: 2, name: "Music", cpu: 4),
            ProcessUsage(pid: 3, name: "Mail", cpu: 2),
        ])

        // The demo starts after a minute of warm-up, so the one-minute graphs are full.
        let warmUp = 62.0
        let start = ProcessInfo.processInfo.systemUptime
        let demoStart = start + warmUp
        let downloadFrom = 1.2
        let downloadUntil = 11.0
        monitor.useExampleTraffic { now in
            let t = now - start
            let d = now - demoStart
            func burst(_ at: Double, _ width: Double, _ height: Double) -> Double {
                max(0, 1 - abs(t - at) / width) * height
            }
            var down = 30_000 + burst(14, 2, 2_600_000) + burst(38, 3, 1_800_000)
            var up = 8_000 + burst(15, 2, 400_000) + burst(39, 3, 900_000)
            let read = 150_000 + burst(10, 1.5, 22_000_000) + burst(33, 2, 14_000_000) + (d > 6 && d < 7.5 ? 26_000_000 : 0)
            let write = 200_000 + burst(22, 2, 9_000_000) + burst(48, 3, 16_000_000) + (d > 8 && d < 10 ? 34_000_000 : 0)
            if d >= downloadFrom && d < downloadUntil {
                // A download that ramps up, wobbles a little and stops.
                let ramp = min(1, (d - downloadFrom) / 1.2)
                down += ramp * (11_500_000 + 1_400_000 * sin(d * 2.3))
                up += ramp * 180_000
            }
            return (down, up, read, write)
        }
        // A Mac with a few apps open, a little busier while the download runs.
        monitor.useExampleLoad { now in
            let d = now - demoStart
            let downloading = d >= downloadFrom && d < downloadUntil ? 6.0 : 0
            return 17 + downloading + 3 * sin(now * 0.9)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(warmUp - (ProcessInfo.processInfo.systemUptime - start)))

        let width: CGFloat = 540
        let menuBarHeight: CGFloat = 26
        let panelTop = menuBarHeight + 14

        // The panel, built fresh when it opens like in the app, in an offscreen window.
        var hosting: NSHostingView<AnyView>?
        var window: NSWindow?
        func openPanel() {
            monitor.setPanelVisible(true)
            let view = PanelView(monitor: monitor, prefs: prefs,
                                 actions: PanelActions(openActivityMonitor: {}, openSettings: {}, quit: {}))
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: AnyView(view))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(x: 0, y: 0, width: 344, height: max(300, host.fittingSize.height))
            let panelWindow = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panelWindow.appearance = NSAppearance(named: .darkAqua)
            panelWindow.contentView = host
            panelWindow.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            panelWindow.orderFrontRegardless()
            hosting = host
            window = panelWindow
        }
        func closePanel() {
            window?.orderOut(nil)
            window = nil
            hosting = nil
            monitor.setPanelVisible(false)
        }

        // Size the canvas for the panel once.
        openPanel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let panelHeight = hosting?.fittingSize.height ?? 560
        closePanel()
        let height = panelTop + panelHeight + 24

        // Blipp's status item sits near the right end of the menu bar; the panel hangs below it.
        let blippCenterX: CGFloat = width - 152
        let panelX = min(width - 344 - 16, max(16, blippCenterX - 172))

        let openAt = 4.4
        let closeAt = 12.6
        let length = 16.0
        let cursorRest = CGPoint(x: width * 0.42, y: height * 0.55)
        let cursorOnBlipp = CGPoint(x: blippCenterX + 6, y: menuBarHeight / 2 + 2)
        let cursorOnTile = CGPoint(x: panelX + 290, y: panelTop + panelHeight - 250)

        func cursor(at t: Double) -> CGPoint {
            func ease(_ x: Double) -> CGFloat { let c = min(1, max(0, x)); return CGFloat(c * c * (3 - 2 * c)) }
            func mix(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k) }
            if t < 3.0 { return cursorRest }
            if t < openAt { return mix(cursorRest, cursorOnBlipp, ease((t - 3.0) / (openAt - 3.2))) }
            if t < 6.5 { return cursorOnBlipp }
            if t < 8.0 { return mix(cursorOnBlipp, cursorOnTile, ease((t - 6.5) / 1.5)) }
            if t < 11.0 { return cursorOnTile }
            if t < closeAt { return mix(cursorOnTile, cursorOnBlipp, ease((t - 11.0) / (closeAt - 11.2))) }
            if t < 13.6 { return cursorOnBlipp }
            return mix(cursorOnBlipp, cursorRest, ease((t - 13.6) / 2.0))
        }

        let writer = FrameWriter(folder: folder)
        var last = ProcessInfo.processInfo.systemUptime
        var frame = 0
        while true {
            let target = demoStart + Double(frame) * frameTime
            let wait = target - ProcessInfo.processInfo.systemUptime
            if wait > 0 { RunLoop.main.run(until: Date().addingTimeInterval(wait)) }
            let now = ProcessInfo.processInfo.systemUptime
            let t = now - demoStart
            if t >= length { break }

            if hosting == nil && t >= openAt && t < closeAt { openPanel() }
            if hosting != nil && t >= closeAt { closePanel() }

            let context = IconExporter.makeContext(width: Int(width * scale), height: Int(height * scale))
            context.scaleBy(x: scale, y: scale)
            drawWallpaper(in: context, width: width, height: height)
            drawDemoMenuBar(in: context, width: width, height: menuBarHeight, blippCenterX: blippCenterX,
                            mood: monitor.mood, highlighted: hosting != nil, time: now)

            if let hosting, let snapshot = snapshot(hosting) {
                let shown = min(1, (t - openAt) / 0.18)
                let rect = CGRect(x: panelX, y: panelTop, width: 344, height: panelHeight)
                drawPanel(snapshot, in: context, rect: rect, arrowX: blippCenterX, alpha: CGFloat(shown))
            }

            // A click ripple when the cursor presses Blipp.
            for clickAt in [openAt, closeAt] where t >= clickAt - 0.05 && t < clickAt + 0.35 {
                let k = CGFloat((t - clickAt + 0.05) / 0.4)
                let r = 6 + 12 * k
                context.addEllipse(in: CGRect(x: cursorOnBlipp.x - r, y: cursorOnBlipp.y - r, width: 2 * r, height: 2 * r))
                context.setFillColor(NSColor(white: 1, alpha: 0.35 * (1 - k)).cgColor)
                context.fillPath()
            }
            drawCursor(in: context, at: cursor(at: t))

            writer.add(context.makeImage()!, seconds: now - last > 0.5 ? frameTime : max(frameTime, now - last))
            last = now
            frame += 1
        }
        closePanel()
        writer.finish()
    }

    private static func snapshot(_ view: NSView) -> CGImage? {
        view.layoutSubtreeIfNeeded()
        view.display()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage
    }

    /// A soft, generic gradient instead of anyone's real desktop.
    private static func drawWallpaper(in context: CGContext, width: CGFloat, height: CGFloat) {
        let colors = [Painter.color(0x7F9CF5), Painter.color(0xB794F4), Painter.color(0xF6AD9F)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: width, y: height), options: [])
    }

    private static func drawDemoMenuBar(in context: CGContext, width: CGFloat, height: CGFloat, blippCenterX: CGFloat,
                                        mood: Mood, highlighted: Bool, time: Double) {
        context.setFillColor(Painter.color(0x1A1F2B, 0.88))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        withAppKit(context) {
            var x: CGFloat = 16
            for (index, item) in ["Notes", "File", "Edit", "View", "Window"].enumerated() {
                let text = label(item, size: 13, weight: index == 0 ? .bold : .regular, color: .white)
                text.draw(at: CGPoint(x: x, y: (height - text.size().height) / 2))
                x += text.size().width + 18
            }

            let clock = label("Tue 9:41", size: 13, weight: .regular, color: .white)
            var right = width - 14 - clock.size().width
            clock.draw(at: CGPoint(x: right, y: (height - clock.size().height) / 2))
            for symbol in ["switch.2", "wifi"] {
                guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { continue }
                right -= 14 + image.size.width
                tinted(image, color: .white).draw(in: CGRect(x: right, y: (height - image.size.height) / 2,
                                                            width: image.size.width, height: image.size.height),
                                                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }

        var bubble = MenuBarIcon.shownBubble(mood.bubble, style: .symbol)
        bubble?.value = ""
        let image = MenuBarIcon.image(scene: mood.scene, style: .color, bubble: bubble, bubbleStyle: .symbol, darkMenuBar: true, time: time)
        // The image's right part is Blipp (18 pt); the bubble's spot sits to his left.
        let rect = CGRect(x: blippCenterX + 9 - image.size.width, y: (height - image.size.height) / 2,
                          width: image.size.width, height: image.size.height)
        if highlighted {
            context.addPath(CGPath(roundedRect: rect.insetBy(dx: -5, dy: -2), cornerWidth: 5, cornerHeight: 5, transform: nil))
            context.setFillColor(NSColor(white: 1, alpha: 0.2).cgColor)
            context.fillPath()
        }
        withAppKit(context) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// The popover: the panel snapshot in a rounded window with a little arrow toward Blipp.
    private static func drawPanel(_ image: CGImage, in context: CGContext, rect: CGRect, arrowX: CGFloat, alpha: CGFloat) {
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let shape = CGMutablePath()
        shape.addRoundedRect(in: rect, cornerWidth: 12, cornerHeight: 12)
        shape.move(to: CGPoint(x: arrowX - 9, y: rect.minY + 0.5))
        shape.addLine(to: CGPoint(x: arrowX, y: rect.minY - 9))
        shape.addLine(to: CGPoint(x: arrowX + 9, y: rect.minY + 0.5))
        shape.closeSubpath()

        // No soft shadow: a GIF's 256 colors would turn it into rings.
        context.addPath(shape)
        context.setFillColor(Painter.color(0x2B2B2D))
        context.fillPath()

        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.clip()
        // The context is flipped; draw the image upright.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()

        context.addPath(shape)
        context.setStrokeColor(NSColor(white: 0, alpha: 0.35).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// A classic arrow pointer.
    private static func drawCursor(in context: CGContext, at point: CGPoint) {
        let path = CGMutablePath()
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: point.x + x, y: point.y + y) }
        path.move(to: p(0, 0))
        path.addLine(to: p(0, 17))
        path.addLine(to: p(4.2, 13.2))
        path.addLine(to: p(7, 19.5))
        path.addLine(to: p(9.6, 18.4))
        path.addLine(to: p(6.9, 12.2))
        path.addLine(to: p(12.4, 12.2))
        path.closeSubpath()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: NSColor(white: 0, alpha: 0.4).cgColor)
        context.addPath(path)
        context.setFillColor(.black)
        context.fillPath()
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(.white)
        context.setLineWidth(1.3)
        context.setLineJoin(.round)
        context.strokePath()
        context.addPath(path)
        context.setFillColor(.black)
        context.fillPath()
    }

    // MARK: Text and AppKit drawing

    private static let primaryText = NSColor(srgbRed: 0.106, green: 0.141, blue: 0.2, alpha: 1)
    private static let secondaryText = NSColor(srgbRed: 0.42, green: 0.46, blue: 0.53, alpha: 1)

    private static func withAppKit(_ context: CGContext, _ body: () -> Void) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.current = previous
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        return NSAttributedString(string: text, attributes: [.font: rounded, .foregroundColor: color])
    }

    private static func drawText(_ text: String, in context: CGContext, x: CGFloat, y: CGFloat, size: CGFloat,
                                 weight: NSFont.Weight = .semibold, color: NSColor? = nil) {
        let string = label(text, size: size, weight: weight, color: color ?? primaryText)
        withAppKit(context) { string.draw(at: CGPoint(x: x, y: y)) }
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
        return result
    }
}

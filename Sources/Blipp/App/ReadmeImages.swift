import AppKit
import SwiftUI

/// Developer tool: `Blipp --render-readme <folder>` renders the pictures used in README.md:
/// a labelled mood gallery, the menu bar icons, the app icon, and the real panel in light and
/// dark mode (sampled from this Mac for ~40 s so the graphs have something to show).
@MainActor
enum ReadmeImages {
    static func render(to path: String) {
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        renderMoods(to: folder.appendingPathComponent("moods.png"))
        renderMenuBar(to: folder.appendingPathComponent("menubar.png"))
        try? IconExporter.writePNG(IconExporter.renderIcon(pixels: 512), to: folder.appendingPathComponent("icon.png"))
        renderPanels(into: folder)
    }

    // MARK: Moods

    private static let moods: [(String, String)] = [
        ("Sleeping", "Sleeping"), ("Chilling", "Chilling"), ("Working", "Working"),
        ("Sweating", "Sweating"), ("Burning", "On fire"), ("Juice", "Charging"),
        ("At limit", "Charge limit"), ("Tired", "Low battery"), ("Juggling", "Busy memory"),
        ("Hot", "Running hot"), ("Offline", "Offline"), ("Melted", "Battery empty"),
    ]

    private static func renderMoods(to url: URL) {
        let scale: CGFloat = 2
        let columns = 6
        let cellWidth: CGFloat = 150
        let cellHeight: CGFloat = 176
        let gap: CGFloat = 12
        let rows = (moods.count + columns - 1) / columns
        let width = CGFloat(columns) * cellWidth + CGFloat(columns - 1) * gap
        let height = CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap

        let context = IconExporter.makeContext(width: Int(width * scale), height: Int(height * scale))
        context.scaleBy(x: scale, y: scale)
        let scenes = Dictionary(uniqueKeysWithValues: PreviewRenderer.states.map { ($0.0, $0.1) })

        for (index, (key, label)) in moods.enumerated() {
            guard let scene = scenes[key] else { continue }
            let x = CGFloat(index % columns) * (cellWidth + gap)
            let y = CGFloat(index / columns) * (cellHeight + gap)
            let card = CGPath(roundedRect: CGRect(x: x, y: y, width: cellWidth, height: cellHeight), cornerWidth: 20, cornerHeight: 20, transform: nil)
            context.addPath(card)
            context.setFillColor(Painter.color(0xF5F7FA))
            context.fillPath()

            let size: CGFloat = 92
            BlippRenderer.draw(scene, in: context, origin: CGPoint(x: x + (cellWidth - size) / 2, y: y + 30), size: size, time: 0.4)
            drawLabel(label, in: context, centerX: x + cellWidth / 2, y: y + cellHeight - 34)
        }
        try? IconExporter.writePNG(context.makeImage()!, to: url)
    }

    private static func drawLabel(_ text: String, in context: CGContext, centerX: CGFloat, y: CGFloat) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 15) } ?? font
        let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: NSColor(srgbRed: 0.106, green: 0.141, blue: 0.2, alpha: 1)]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: centerX - size.width / 2, y: y))
    }

    // MARK: Menu bar

    /// A slice of a menu bar, dark and light, with Blipp in a few moods at 2× scale.
    private static func renderMenuBar(to url: URL) {
        let keys = ["Chilling", "Working", "Sweating", "Burning", "Juice", "Tired", "Juggling", "Sleeping"]
        let scenes = Dictionary(uniqueKeysWithValues: PreviewRenderer.states.map { ($0.0, $0.1) })
        let scale: CGFloat = 2
        let iconSpacing: CGFloat = 30
        let barHeight: CGFloat = 26
        let padding: CGFloat = 14
        let width = padding * 2 + CGFloat(keys.count) * iconSpacing - (iconSpacing - 18)
        let height = barHeight * 2 + 8

        let context = IconExporter.makeContext(width: Int(width * scale), height: Int(height * scale))
        context.scaleBy(x: scale, y: scale)
        for (row, (background, template)) in [(UInt32(0x1E2433), false), (UInt32(0xEEF0F3), false)].enumerated() {
            let top = CGFloat(row) * (barHeight + 8)
            let bar = CGPath(roundedRect: CGRect(x: 0, y: top, width: width, height: barHeight), cornerWidth: 7, cornerHeight: 7, transform: nil)
            context.addPath(bar)
            context.setFillColor(Painter.color(background))
            context.fillPath()
            for (index, key) in keys.enumerated() {
                guard let scene = scenes[key] else { continue }
                context.saveGState()
                context.translateBy(x: padding + CGFloat(index) * iconSpacing, y: top + (barHeight - 18) / 2)
                MenuBarRenderer.draw(scene, in: context, size: 18, template: template, time: MenuBarRenderer.stillTime)
                context.restoreGState()
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
        let monitor = SystemMonitor(prefs: prefs)
        // Generic examples, so the pictures never show the processes of whoever renders them.
        monitor.useExampleProcesses([
            ProcessUsage(pid: 1, name: "Safari", cpu: 9),
            ProcessUsage(pid: 2, name: "Music", cpu: 4),
            ProcessUsage(pid: 3, name: "Mail", cpu: 2),
        ])
        monitor.setPanelVisible(true)
        RunLoop.main.run(until: Date().addingTimeInterval(40))

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

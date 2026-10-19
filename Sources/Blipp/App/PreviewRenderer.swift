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
            ("Sleeping", scene { $0.shape = .squished; $0.color = Palette.sleepy; $0.face = .sleeping; $0.overhead = .zzz }),
            ("Chilling", scene { $0.face = .sunglasses }),
            ("Working", scene { $0.color = Palette.lime; $0.face = .focused; $0.overhead = .gear }),
            ("Sweating", scene { $0.color = Palette.yellow; $0.face = .sweaty; $0.sweat = true }),
            ("Burning", scene { $0.color = Palette.hot; $0.face = .panic; $0.overhead = .flame; $0.sweat = true }),
            ("Juice", scene { $0.face = .happyClosed; $0.hands = .juice }),
            ("Cookie", scene { $0.face = .chewing; $0.hands = .cookie }),
            ("Full", scene { $0.shape = .round; $0.face = .content; $0.overhead = .sparkles }),
            ("At limit", scene { $0.face = .pleased; $0.hands = .juiceAside; $0.overhead = .batteryCheck }),
            ("Tired", scene { $0.color = Palette.tired; $0.face = .tired; $0.overhead = .lowBattery }),
            ("Melted", scene { $0.shape = .puddle; $0.color = Palette.melted; $0.face = .dead; $0.overhead = .emptyBattery }),
            ("Juggling", scene { $0.face = .lookingUp; $0.overhead = .juggle3 }),
            ("Dropping", scene { $0.face = .dizzy; $0.overhead = .juggle5; $0.sweat = true }),
            ("Swapping", scene { $0.face = .determined; $0.hands = .packBox }),
            ("Warm", scene { $0.color = Palette.warm; $0.face = .relieved; $0.hands = .fan }),
            ("Hot", scene { $0.color = Palette.orange; $0.face = .licking; $0.hands = .iceCream; $0.sweat = true }),
            ("Boiling", scene { $0.color = Palette.boiling; $0.face = .boiling; $0.hands = .thermometer; $0.overhead = .steam }),
            ("Download", scene { $0.face = .excited; $0.hands = .catchBox }),
            ("Upload", scene { $0.face = .wink; $0.hands = .plane }),
            ("Offline", scene { $0.color = Palette.offline; $0.face = .sad; $0.overhead = .cloudOffline; $0.tear = true }),
            ("Disk busy", scene { $0.face = .focused; $0.hands = .papers }),
            ("Disk full", scene { $0.shape = .wide; $0.face = .surprised }),
            // Combinations that have caused overlaps before.
            ("Sleeping + cookie", scene { $0.shape = .squished; $0.color = Palette.sleepy; $0.face = .sleeping; $0.overhead = .zzz; $0.hands = .cookie }),
            ("Working + cookie", scene { $0.color = Palette.lime; $0.face = .focused; $0.overhead = .gear; $0.hands = .cookie }),
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

        try? IconExporter.writePNG(IconExporter.renderIcon(pixels: 512), to: folder.appendingPathComponent("icon.png"))

        renderPanel(to: folder.appendingPathComponent("panel.png"))
    }

    /// Runs the real monitor for a few seconds, then snapshots the panel with everything expanded.
    private static func renderPanel(to url: URL) {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "app.blipp.preview") ?? .standard)
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

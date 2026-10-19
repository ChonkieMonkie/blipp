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

/// Builds the status item image: Blipp, plus an optional accessory or mini bars.
enum MenuBarIcon {
    static let height: CGFloat = 18

    enum Accessory: Equatable {
        case none, bolt, lowBattery
    }

    static func image(
        scene: BlippScene,
        style: IconStyle,
        accessory: Accessory,
        bars: (cpu: Double, memory: Double)?,
        time: Double
    ) -> NSImage {
        let template = style == .monochrome
        let accessoryWidth: CGFloat = accessory == .none ? 0 : 8
        let barsWidth: CGFloat = bars == nil ? 0 : 11
        let width = height + accessoryWidth + barsWidth

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            MenuBarRenderer.draw(scene, in: cg, size: height, template: template, time: time)

            var x = height
            if accessory != .none {
                drawAccessory(accessory, in: cg, x: x + 1, template: template)
                x += accessoryWidth
            }
            if let bars {
                drawBars(bars, in: cg, x: x + 2, template: template)
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Blipp"
        return image
    }

    /// A still Blipp for the Style picker in Settings.
    static func preview(style: IconStyle) -> NSImage {
        image(scene: BlippScene(), style: style, accessory: .none, bars: nil, time: MenuBarRenderer.stillTime)
    }

    private static func drawAccessory(_ accessory: Accessory, in cg: CGContext, x: CGFloat, template: Bool) {
        let p = Painter(cg: cg)
        cg.saveGState()
        cg.translateBy(x: x, y: 2)
        switch accessory {
        case .bolt:
            let bolt = "M4.5 0L0 7.5H3.2L1.8 14L6.5 5.8H3.4L4.5 0Z"
            if template {
                p.fill(bolt, 0x000000)
            } else {
                p.fill(bolt, Palette.juice)
                p.stroke(bolt, Palette.ink, width: 0.8)
            }
        case .lowBattery:
            let outline: UInt32 = template ? 0x000000 : Palette.ink
            p.rect(0.5, 2, 5.5, 10, radius: 1.2, fill: 0xFFFFFF, stroke: outline, width: 1)
            p.rect(2, 0.6, 2.5, 1.6, radius: 0.4, fill: outline, stroke: nil)
            p.rect(1.6, 9, 3.3, 2, radius: 0.4, fill: template ? 0x000000 : Palette.red, stroke: nil)
            if template {
                cg.setBlendMode(.clear)
                p.rect(1.5, 3, 3.5, 5.5, radius: 0.5, fill: 0x000000, stroke: nil)
                cg.setBlendMode(.normal)
            }
        case .none:
            break
        }
        cg.restoreGState()
    }

    private static func drawBars(_ bars: (cpu: Double, memory: Double), in cg: CGContext, x: CGFloat, template: Bool) {
        let p = Painter(cg: cg)
        let top: CGFloat = 2
        let barHeight: CGFloat = 14
        for (index, value) in [bars.cpu, bars.memory].enumerated() {
            let barX = x + CGFloat(index) * 5
            let track: UInt32 = 0x000000
            cg.saveGState()
            cg.setAlpha(template ? 0.35 : 0.25)
            p.rect(barX, top, 3.5, barHeight, radius: 1.2, fill: template ? track : 0x8A94A6, stroke: nil)
            cg.restoreGState()
            let filled = max(1.5, barHeight * CGFloat(min(1, max(0, value))))
            let color: UInt32 = template ? 0x000000 : (index == 0 ? cpuColor(value * 100) : 0x9B6CF0)
            p.rect(barX, top + barHeight - filled, 3.5, filled, radius: 1.2, fill: color, stroke: nil)
        }
    }

    private static func cpuColor(_ percent: Double) -> UInt32 {
        switch percent {
        case ..<50: return 0x22A06B
        case ..<75: return 0xEAB308
        case ..<90: return 0xF97316
        default: return 0xE5484D
        }
    }
}

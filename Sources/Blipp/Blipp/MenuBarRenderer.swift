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

import CoreGraphics
import Foundation

/// The menu bar version of Blipp: redrawn (not shrunk) with thicker lines and fewer
/// details so it stays readable at 18 pt. In template mode the face is cut out of a
/// solid silhouette so macOS can tint it like any system icon.
enum MenuBarRenderer {
    private enum Eyes { case dots, focused, closed, happy, squint, glasses, panic, dead, wink }
    private enum Mouth { case smile, open, small, flat, frown, wavy, oval }

    static let blinkPeriod = 6.0
    static let blinkLength = 0.14
    static let sweatPeriod = 1.4
    static let sweatFrames = 8
    /// A moment with open eyes, for still icons (animation off, previews).
    static let stillTime = 0.0

    /// Blinks land at a slightly different moment in every 6 s window (4–8 s apart),
    /// which looks more natural than a metronome. Deterministic, so frames are reproducible.
    private static func blinkStart(window: Double) -> Double {
        var hash = UInt64(bitPattern: Int64(window)) &* 0x9E37_79B9_7F4A_7C15
        hash ^= hash >> 31
        let jitter = Double(hash % 1000) / 1000  // 0…1
        return window * blinkPeriod + 1 + jitter * (blinkPeriod - 2)
    }

    static func isBlinking(at t: Double) -> Bool {
        let start = blinkStart(window: (t / blinkPeriod).rounded(.down))
        return t >= start && t < start + blinkLength
    }

    /// The animation frame the icon shows at `time`. The status item only redraws when this changes:
    /// two redraws per blink, about six a second while sweating.
    static func frame(for scene: BlippScene, time t: Double) -> Int {
        let blinking = isBlinking(at: t) ? 1 : 0
        let sweat = scene.sweat ? Int((t / sweatPeriod).truncatingRemainder(dividingBy: 1) * Double(sweatFrames)) + 1 : 0
        return blinking + sweat * 2
    }

    /// When `frame(for:time:)` will next change, so the caller can sleep until then.
    static func nextFrameChange(for scene: BlippScene, after t: Double) -> Double {
        let window = (t / blinkPeriod).rounded(.down)
        let start = blinkStart(window: window)
        var next: Double
        if t < start {
            next = start
        } else if t < start + blinkLength {
            next = start + blinkLength
        } else {
            next = blinkStart(window: window + 1)
        }
        if scene.sweat {
            let step = sweatPeriod / Double(sweatFrames)
            next = min(next, ((t / step).rounded(.down) + 1) * step)
        }
        return next
    }

    /// `template` draws a solid silhouette in `monoInk` with the face cut out, like a system icon.
    static func draw(_ scene: BlippScene, in cg: CGContext, size: CGFloat, template: Bool, monoInk: UInt32 = 0x000000, time t: Double) {
        cg.saveGState()
        cg.scaleBy(x: size / 64, y: size / 64)
        let p = Painter(cg: cg)
        let ink = template ? monoInk : Palette.ink

        let puddle = scene.shape == .puddle
        let body = puddle
            ? "M4 60C4 50 12 46 18 46C19 36 26 32 32 32C38 32 45 36 46 46C52 46 60 50 60 60Z"
            : "M32 8C49 8 58 20 58 36C58 51 47 59 32 59C17 59 6 51 6 36C6 20 15 8 32 8Z"

        if template {
            p.fill(body, monoInk)
        } else {
            p.fill(body, scene.color)
            p.stroke(body, Palette.ink, width: 3.5)
        }

        // Features: cut out in template mode, ink otherwise.
        if template { cg.setBlendMode(.clear) }
        let (eyes, mouth) = features(for: scene.face)
        let dy: CGFloat = puddle ? 12 : 0
        p.group(CGAffineTransform(translationX: 0, y: dy)) {
            drawEyes(p, eyes, ink: ink, template: template, t: t)
            drawMouth(p, mouth, ink: ink)
        }
        cg.setBlendMode(.normal)

        // Sweat means hot, in color and in monochrome alike.
        if scene.sweat {
            let step = floor((t / sweatPeriod).truncatingRemainder(dividingBy: 1) * Double(sweatFrames))
            let c = CGFloat(step / Double(sweatFrames))
            p.group(CGAffineTransform(translationX: 0, y: 6 * c), alpha: c < 0.8 ? 1 : (1 - c) / 0.2) {
                let drop = "M55 4C55 4 60 10 60 13A5 5 0 0 1 50 13C50 10 55 4 55 4Z"
                if template {
                    p.fill(drop, monoInk)
                } else {
                    p.shape(drop, fill: Palette.sweat, width: 2.5)
                }
            }
        }
        cg.restoreGState()
    }

    private static func features(for face: BlippScene.Face) -> (Eyes, Mouth) {
        switch face {
        case .smile: return (.dots, .smile)
        case .sleeping: return (.closed, .small)
        case .sunglasses: return (.glasses, .smile)
        case .focused: return (.focused, .flat)
        case .sweaty: return (.squint, .open)
        case .panic: return (.panic, .oval)
        case .dead: return (.dead, .wavy)
        case .boiling: return (.squint, .wavy)
        case .happyClosed: return (.happy, .small)
        case .wink: return (.wink, .smile)
        case .excited: return (.dots, .open)
        case .yawn: return (.closed, .oval)
        case .relieved: return (.happy, .smile)
        case .surprised: return (.panic, .small)
        }
    }

    private static func drawEyes(_ p: Painter, _ eyes: Eyes, ink: UInt32, template: Bool, t: Double) {
        // A quick blink every few seconds keeps the icon alive without being distracting.
        let blinking = isBlinking(at: t)
        switch eyes {
        case .dots, .focused:
            let y: CGFloat = eyes == .focused ? 36 : 35
            if eyes == .focused {
                p.stroke("M17 26L28 29M47 26L36 29", ink, width: 4.2)
            }
            if blinking {
                p.stroke("M19 \(y)H29M35 \(y)H45", ink, width: 4)
            } else {
                p.circle(24, y, 5, fill: ink)
                p.circle(40, y, 5, fill: ink)
            }
        case .closed:
            p.stroke("M19 38Q24 42 29 38M35 38Q40 42 45 38", ink, width: 4.5)
        case .happy:
            p.stroke("M18 37Q24 29 30 37M34 37Q40 29 46 37", ink, width: 4.5)
        case .squint:
            p.stroke("M20 30L28 35L20 40M44 30L36 35L44 40", ink, width: 4.5)
        case .glasses:
            p.fill("M15 30H30V35A5 5 0 0 1 25 40H20A5 5 0 0 1 15 35Z", ink)
            p.fill("M34 30H49V35A5 5 0 0 1 44 40H39A5 5 0 0 1 34 35Z", ink)
            p.stroke("M30 32H34", ink, width: 3)
        case .panic:
            if template {
                p.circle(24, 35, 6.5, fill: ink)
                p.circle(40, 35, 6.5, fill: ink)
                p.cg.setBlendMode(.normal)
                p.circle(24, 35, 2.5, fill: ink)
                p.circle(40, 35, 2.5, fill: ink)
                p.cg.setBlendMode(.clear)
            } else {
                p.circle(24, 35, 6.5, fill: Palette.white, stroke: ink, width: 2.5)
                p.circle(40, 35, 6.5, fill: Palette.white, stroke: ink, width: 2.5)
                p.circle(24, 35, 2.5, fill: ink)
                p.circle(40, 35, 2.5, fill: ink)
            }
        case .dead:
            p.stroke("M20 31L28 39M28 31L20 39M36 31L44 39M44 31L36 39", ink, width: 4)
        case .wink:
            if blinking {
                p.stroke("M19 35H29", ink, width: 4)
            } else {
                p.circle(24, 35, 5, fill: ink)
            }
            p.stroke("M35 37Q40 31 45 37", ink, width: 4.5)
        }
    }

    private static func drawMouth(_ p: Painter, _ mouth: Mouth, ink: UInt32) {
        switch mouth {
        case .smile: p.stroke("M26 45Q32 51 38 45", ink, width: 4.5)
        case .open: p.fill("M25 44H39Q39 53 32 53Q25 53 25 44Z", ink)
        case .small: p.circle(32, 47, 3.5, fill: ink)
        case .flat: p.stroke("M27 46H37", ink, width: 4.5)
        case .frown: p.stroke("M26 49Q32 43 38 49", ink, width: 4.5)
        case .wavy: p.stroke("M25 48Q28.5 45 32 48Q35.5 51 39 48", ink, width: 4)
        case .oval: p.ellipse(32, 49, 5, 5.5, fill: ink)
        }
    }
}

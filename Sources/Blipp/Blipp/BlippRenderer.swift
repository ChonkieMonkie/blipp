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

/// Thin helpers over CGContext that speak the design's 64 × 64 coordinate system.
struct Painter {
    let cg: CGContext

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    func fill(_ data: String, _ hex: UInt32, alpha: CGFloat = 1) {
        cg.addPath(SVGPath.path(data))
        cg.setFillColor(Painter.color(hex, alpha))
        cg.fillPath()
    }

    func stroke(_ data: String, _ hex: UInt32 = Palette.ink, width: CGFloat = 2, alpha: CGFloat = 1, dash: [CGFloat] = []) {
        cg.addPath(SVGPath.path(data))
        strokeCurrent(hex, width: width, alpha: alpha, dash: dash)
    }

    /// Fill, then outline — the sticker look every Blipp part uses.
    func shape(_ data: String, fill: UInt32, stroke: UInt32 = Palette.ink, width: CGFloat = 2) {
        self.fill(data, fill)
        self.stroke(data, stroke, width: width)
    }

    /// Same sticker look for a ready-made path; even-odd, so inner subpaths become holes.
    func shape(_ path: CGPath, fill: UInt32, stroke: UInt32? = Palette.ink, width: CGFloat = 2) {
        cg.addPath(path)
        cg.setFillColor(Painter.color(fill))
        cg.fillPath(using: .evenOdd)
        if let stroke {
            cg.addPath(path)
            strokeCurrent(stroke, width: width)
        }
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, fill: UInt32, alpha: CGFloat = 1, stroke: UInt32? = nil, width: CGFloat = 2) {
        let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        cg.addEllipse(in: rect)
        cg.setFillColor(Painter.color(fill, alpha))
        cg.fillPath()
        if let stroke {
            cg.addEllipse(in: rect)
            strokeCurrent(stroke, width: width, alpha: alpha)
        }
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, fill: UInt32, alpha: CGFloat = 1, stroke: UInt32? = nil, width: CGFloat = 2) {
        ellipse(cx, cy, r, r, fill: fill, alpha: alpha, stroke: stroke, width: width)
    }

    func ring(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ hex: UInt32 = Palette.ink, width: CGFloat = 2, dash: [CGFloat] = []) {
        cg.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        strokeCurrent(hex, width: width, dash: dash)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, fill: UInt32, stroke: UInt32? = Palette.ink, width: CGFloat = 2) {
        let path = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.addPath(path)
        cg.setFillColor(Painter.color(fill))
        cg.fillPath()
        if let stroke {
            cg.addPath(path)
            strokeCurrent(stroke, width: width)
        }
    }

    func group(_ transform: CGAffineTransform = .identity, alpha: CGFloat = 1, _ body: () -> Void) {
        cg.saveGState()
        cg.concatenate(transform)
        if alpha < 1 { cg.setAlpha(max(0, alpha)) }
        body()
        cg.restoreGState()
    }

    private func strokeCurrent(_ hex: UInt32, width: CGFloat, alpha: CGFloat = 1, dash: [CGFloat] = []) {
        cg.setStrokeColor(Painter.color(hex, alpha))
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setLineDash(phase: 0, lengths: dash)
        cg.strokePath()
    }
}

// MARK: - Animation helpers

/// 0 → 1 → 0 over one period, eased.
private func pulse(_ t: Double, _ period: Double, phase: Double = 0) -> CGFloat {
    CGFloat(0.5 - 0.5 * cos(2 * .pi * (t / period + phase)))
}

/// 0 → 1 sawtooth over one period.
private func cycle(_ t: Double, _ period: Double, delay: Double = 0) -> CGFloat {
    let value = (t - delay) / period
    return CGFloat(value - floor(value))
}

private func fadeInOut(_ c: CGFloat, fadeIn: CGFloat = 0.15, holdUntil: CGFloat = 0.8) -> CGFloat {
    if c < fadeIn { return c / fadeIn }
    if c < holdUntil { return 1 }
    return max(0, (1 - c) / (1 - holdUntil))
}

private extension CGAffineTransform {
    static func about(_ x: CGFloat, _ y: CGFloat, _ change: (CGAffineTransform) -> CGAffineTransform) -> CGAffineTransform {
        change(CGAffineTransform(translationX: x, y: y)).translatedBy(x: -x, y: -y)
    }

    static func rotation(_ degrees: CGFloat, around x: CGFloat, _ y: CGFloat) -> CGAffineTransform {
        about(x, y) { $0.rotated(by: degrees * .pi / 180) }
    }

    static func scale(_ sx: CGFloat, _ sy: CGFloat, around x: CGFloat, _ y: CGFloat) -> CGAffineTransform {
        about(x, y) { $0.scaledBy(x: sx, y: sy) }
    }
}

// MARK: - Full-size Blipp

/// A short animation Blipp plays when the panel opens. Several fit each state, so it's
/// rarely the same twice.
struct BlippIntro: Equatable {
    enum Kind: CaseIterable {
        case hop, peek, spin, wave, heart, stretch, nod, shiver, wipe, slurp, toss, lookAround
    }

    var kind: Kind
    /// 0 at the start, 1 when it's over.
    var progress: Double

    static let duration = 1.5

    /// The animations that make sense for what Blipp is doing right now.
    static func candidates(for scene: BlippScene) -> [Kind] {
        if scene.shape == .puddle || scene.face == .boiling { return [.shiver, .lookAround] }
        var kinds: [Kind] = []
        switch scene.face {
        case .sleeping: kinds += [.stretch, .nod, .peek]
        case .smile, .sunglasses: kinds += [.hop, .spin, .heart, .peek]
        case .focused: kinds += [.nod, .lookAround, .hop]
        case .sweaty, .panic: kinds += [.wipe, .shiver, .hop]
        default: kinds += [.hop, .heart]
        }
        if scene.network == .none || scene.disk == .none { kinds.append(.wave) }
        if scene.color == Palette.chilly { kinds.append(.shiver) }
        if scene.heat != .none { kinds.append(.wipe) }
        if scene.sticker == .juice || scene.sticker == .cookie { kinds += [.slurp, .slurp] }
        if [.juggle3, .juggle5].contains(scene.head) { kinds += [.toss, .toss] }
        if scene.network == .offline { kinds += [.lookAround, .lookAround] }
        return kinds
    }

    static func random(for scene: BlippScene, varied: Bool) -> Kind {
        let kinds = candidates(for: scene)
        return (varied ? kinds.randomElement() : kinds.first) ?? .hop
    }
}

enum BlippRenderer {
    /// Draws Blipp with the 64-unit design box placed at `origin` and scaled to `size` points.
    /// Some parts (juggling balls, the swap box) reach above the box, so leave headroom.
    static func draw(_ scene: BlippScene, in cg: CGContext, origin: CGPoint = .zero, size: CGFloat, time: Double, intro: BlippIntro? = nil) {
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: size / 64, y: size / 64)
        let p = Painter(cg: cg)
        let t = time
        let intro = intro.flatMap { $0.progress < 1 ? $0 : nil }
        var scene = scene
        if let intro { scene.face = introFace(intro, scene.face) }

        // Shadow
        if scene.shape == .puddle {
            p.ellipse(32, 58.5, 27, 2.5, fill: Palette.ink, alpha: 0.12)
        } else {
            p.ellipse(32, 59.5, 19, 2.5, fill: Palette.ink, alpha: 0.12)
        }

        p.group(intro.map(figureTransform) ?? .identity, alpha: intro.map(figureAlpha) ?? 1) {
            if scene.heat == .steam || scene.heat == .fire { drawSteam(p, t) }
            if scene.heat == .fire { drawFlame(p, t) }

            p.group(bodyTransform(scene, t, intro)) {
                drawBody(p, scene)
                let lookShift = intro?.kind == .lookAround ? 3 * CGFloat(sin(2 * .pi * (intro?.progress ?? 0))) : 0
                p.group(CGAffineTransform(translationX: lookShift, y: scene.shape == .puddle ? 9.5 : 0)) {
                    drawFace(p, scene, t)
                }
            }

            drawWork(p, scene, t)
            let toss = intro?.kind == .toss ? -10 * CGFloat(sin(.pi * (intro?.progress ?? 0))) : 0
            p.group(CGAffineTransform(translationX: 0, y: toss)) {
                drawHead(p, scene, t)
            }
            drawNetwork(p, scene, t)
            drawDisk(p, scene, t)
            drawSticker(p, scene, t, intro)
            if scene.heat != .none { drawSweat(p, t) }
            if let intro { drawIntroExtras(p, scene, intro, t) }
        }

        cg.restoreGState()
    }

    private static func bodyTransform(_ scene: BlippScene, _ t: Double, _ intro: BlippIntro?) -> CGAffineTransform {
        var transform: CGAffineTransform
        if scene.shape == .puddle {
            transform = .scale(1 + 0.03 * pulse(t, 2.5), 1, around: 32, 57)
        } else {
            transform = CGAffineTransform(translationX: 0, y: -1.6 * pulse(t, scene.bobPeriod))
        }
        if scene.shake {
            transform = transform.concatenating(CGAffineTransform(translationX: 0.7 * CGFloat(sin(2 * .pi * t / 0.22)), y: 0))
        }
        if let intro, intro.kind == .stretch {
            let k = CGFloat(sin(.pi * intro.progress))
            transform = transform.concatenating(.scale(1 - 0.07 * k, 1 + 0.14 * k, around: 32, 57))
        }
        return transform
    }

    private static func drawBody(_ p: Painter, _ scene: BlippScene) {
        switch scene.shape {
        case .normal:
            p.shape("M32 10C47 10 55 21 55 36C55 50 45 57 32 57C19 57 9 50 9 36C9 21 17 10 32 10Z", fill: scene.color)
            p.stroke("M17 26C18 20 22 15.5 27 14", Palette.white, width: 2.5, alpha: 0.7)
        case .puddle:
            p.shape("M6 57C6 50 13 47 19 47C20 40 26 37 32 37C38 37 44 40 45 47C51 47 58 50 58 57Z", fill: scene.color)
        }
    }

    // MARK: Opening animations

    private static func ease(_ x: Double) -> CGFloat {
        let c = min(1, max(0, x))
        return CGFloat(1 - pow(1 - c, 3))
    }

    private static func figureTransform(_ intro: BlippIntro) -> CGAffineTransform {
        let p = intro.progress
        switch intro.kind {
        case .hop:
            let lift = -11 * CGFloat(sin(.pi * min(1, p / 0.7)))
            // Squash on take-off and landing.
            let squash: CGFloat = p < 0.12 ? 0.12 * CGFloat(sin(.pi * p / 0.12)) : (p > 0.7 && p < 0.9 ? 0.1 * CGFloat(sin(.pi * (p - 0.7) / 0.2)) : 0)
            return CGAffineTransform.scale(1 + squash, 1 - squash, around: 32, 59).concatenating(CGAffineTransform(translationX: 0, y: lift))
        case .peek:
            return CGAffineTransform(translationX: 0, y: 30 * (1 - ease(p / 0.6)))
        case .spin:
            let turn = CGFloat(cos(2 * .pi * min(1, p / 0.8)))
            return .scale(abs(turn) < 0.08 ? 0.08 : turn, 1, around: 32, 34)
        case .nod:
            return .rotation(9 * CGFloat(sin(4 * .pi * p)) * CGFloat(1 - p), around: 32, 58)
        case .shiver:
            return CGAffineTransform(translationX: 1.4 * CGFloat(sin(2 * .pi * p * 22)) * CGFloat(1 - p), y: 0)
        default:
            return .identity
        }
    }

    private static func figureAlpha(_ intro: BlippIntro) -> CGFloat {
        intro.kind == .peek ? min(1, CGFloat(intro.progress / 0.25)) : 1
    }

    /// A different expression for part of the animation, then back to what CPU says.
    private static func introFace(_ intro: BlippIntro, _ face: BlippScene.Face) -> BlippScene.Face {
        let p = intro.progress
        let middle = p > 0.15 && p < 0.85
        switch intro.kind {
        case .hop, .peek, .heart, .slurp: return middle ? .happyClosed : face
        case .wave: return middle ? .wink : face
        case .spin: return p > 0.75 && p < 0.97 ? .wink : face
        case .stretch: return middle ? .yawn : face
        case .wipe: return p > 0.55 && p < 0.95 ? .relieved : face
        case .toss: return middle ? .excited : face
        case .shiver: return middle && face != .dead ? .surprised : face
        case .nod, .lookAround: return face
        }
    }

    private static func drawIntroExtras(_ p: Painter, _ scene: BlippScene, _ intro: BlippIntro, _ t: Double) {
        let k = intro.progress
        switch intro.kind {
        case .wave:
            // Waves with whichever hand is free.
            let left = scene.network == .none
            let x: CGFloat = left ? 7 : 57
            let swing = 22 * CGFloat(sin(2 * .pi * k * 3)) * CGFloat(sin(.pi * k))
            p.group(.rotation(left ? -swing : swing, around: left ? 11 : 53, 34)) {
                p.stroke(left ? "M3 21L1 18M7 19.5V16M11 21L13 18" : "M53 21L51 18M57 19.5V16M61 21L63 18", width: 1.4, alpha: 0.5)
                p.ellipse(x, 26, 3.6, 3.2, fill: scene.color, stroke: Palette.ink, width: 1.6)
            }
        case .heart:
            let rise = ease(k)
            let alpha = k < 0.7 ? 1 : CGFloat(1 - (k - 0.7) / 0.3)
            p.group(CGAffineTransform(translationX: 52, y: 10 - 12 * rise).scaledBy(x: 0.6 + 0.6 * rise, y: 0.6 + 0.6 * rise), alpha: alpha) {
                p.shape("M0 1.6C-1.8 -0.6 -4 0.2 -4 2.2C-4 4.4 -1.6 5.6 0 7C1.6 5.6 4 4.4 4 2.2C4 0.2 1.8 -0.6 0 1.6Z", fill: Palette.ballPink, width: 1)
            }
        case .wipe:
            guard k > 0.1, k < 0.75 else { break }
            let along = CGFloat((k - 0.1) / 0.65)
            p.ellipse(15 + 34 * along, 23 - 3 * CGFloat(sin(.pi * Double(along))), 3.6, 3.2, fill: scene.color, stroke: Palette.ink, width: 1.6)
            p.group(CGAffineTransform(translationX: 8 * along, y: -6 * along), alpha: 1 - along) {
                p.shape("M58 14C58 14 61 17.8 61 19.6A3 3 0 0 1 55 19.6C55 17.8 58 14 58 14Z", fill: Palette.sweat, width: 1.2)
            }
        case .shiver:
            let alpha = CGFloat(sin(.pi * k))
            p.stroke("M1 26L3 28L1 30L3 32M63 26L61 28L63 30L61 32", width: 1.3, alpha: 0.6 * alpha)
        case .slurp:
            let alpha = CGFloat(sin(.pi * k))
            p.stroke("M39 47Q42 45 41 42M41 50Q45 49 45 45", Palette.straw, width: 1.2, alpha: 0.7 * alpha)
        default:
            break
        }
    }

    // MARK: Faces

    private static func eyes(_ p: Painter, y: CGFloat, left: CGFloat = 25, right: CGFloat = 39, glint: CGPoint = CGPoint(x: 1.1, y: -1.1)) {
        p.circle(left, y, 3.2, fill: Palette.ink)
        p.circle(right, y, 3.2, fill: Palette.ink)
        p.circle(left + glint.x, y + glint.y, 1, fill: Palette.white)
        p.circle(right + glint.x, y + glint.y, 1, fill: Palette.white)
    }

    private static func cheeks(_ p: Painter, y: CGFloat, rx: CGFloat = 4, ry: CGFloat = 2.4, alpha: CGFloat = 0.5, left: CGFloat = 18.5, right: CGFloat = 45.5) {
        p.ellipse(left, y, rx, ry, fill: Palette.cheek, alpha: alpha)
        p.ellipse(right, y, rx, ry, fill: Palette.cheek, alpha: alpha)
    }

    private static func squintEyes(_ p: Painter) {
        p.stroke("M22 32.5L27.5 36L22 39.5M42 32.5L36.5 36L42 39.5", width: 2.2)
    }

    private static func drawFace(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        let ink = Palette.ink
        switch scene.face {
        case .smile:
            eyes(p, y: 36)
            cheeks(p, y: 43)
            p.stroke("M28.5 43Q32 46.5 35.5 43")

        case .sleeping:
            p.stroke("M21 36Q25 39 29 36M35 36Q39 39 43 36")
            cheeks(p, y: 41, left: 17.5, right: 46.5)
            p.ellipse(32, 44, 2, 1.5, fill: ink)

        case .sunglasses:
            p.fill("M17.5 32.5H30.5V36.5A4 4 0 0 1 26.5 40.5H21.5A4 4 0 0 1 17.5 36.5Z", ink)
            p.fill("M33.5 32.5H46.5V36.5A4 4 0 0 1 42.5 40.5H37.5A4 4 0 0 1 33.5 36.5Z", ink)
            p.stroke("M30.5 34H33.5")
            p.stroke("M19.5 34.5H22.5M35.5 34.5H38.5", Palette.white, width: 1.2, alpha: 0.8)
            cheeks(p, y: 44)
            p.stroke("M27 44.5Q32 49 37 44.5")

        case .focused:
            p.stroke("M20.5 30.5L28.5 32.5M43.5 30.5L35.5 32.5", width: 2.2)
            eyes(p, y: 36.5)
            p.stroke("M28.5 45H35")
            p.shape("M33 45Q35.5 49 37.5 45", fill: Palette.tongue, width: 1.5)

        case .sweaty:
            squintEyes(p)
            cheeks(p, y: 44, alpha: 0.6)
            p.fill("M27 43.5H37Q37 50 32 50Q27 50 27 43.5Z", ink)
            p.fill("M29.5 48Q32 46 34.5 48Q34 50 32 50Q30 50 29.5 48Z", Palette.tongue)

        case .panic:
            p.circle(25, 35.5, 5, fill: Palette.white, stroke: ink, width: 1.8)
            p.circle(39, 35.5, 5, fill: Palette.white, stroke: ink, width: 1.8)
            p.circle(25, 35.5, 1.6, fill: ink)
            p.circle(39, 35.5, 1.6, fill: ink)
            p.ellipse(32, 48, 4.2, 4.8, fill: ink)
            p.fill("M29.2 50.5Q32 48.5 34.8 50.5Q34 52.8 32 52.8Q30 52.8 29.2 50.5Z", Palette.tongue)

        case .dead:
            p.stroke("M24 34L28 38M28 34L24 38M36 34L40 38M40 34L36 38")
            p.stroke("M28 43Q30 41.5 32 43Q34 44.5 36 43", width: 1.8)

        case .boiling:
            p.stroke("M21 32L28.5 34.5M43 32L35.5 34.5", width: 2.2)
            p.stroke("M21.5 38Q25 36 28.5 38M35.5 38Q39 36 42.5 38", width: 2.2)
            p.stroke("M28 46Q31 44 34 46")

        case .happyClosed:
            p.stroke("M21.5 37Q25 32 28.5 37M35.5 37Q39 32 42.5 37", width: 2.2)
            cheeks(p, y: 43, rx: 4.5, ry: 2.8, alpha: 0.55)
            p.stroke("M28 43.5Q32 48 36 43.5")

        case .wink:
            p.circle(25, 36, 3.2, fill: ink)
            p.circle(25.8, 34.8, 1, fill: Palette.white)
            p.stroke("M35.5 36.5Q39 33 42.5 36.5", width: 2.2)
            cheeks(p, y: 43)
            p.stroke("M27.5 43Q32 47.5 36.5 43")

        case .excited:
            eyes(p, y: 34.5, glint: CGPoint(x: 0.6, y: -1.5))
            cheeks(p, y: 43)
            p.fill("M27.5 42.5H36.5Q36 48.5 32 48.5Q28 48.5 27.5 42.5Z", ink)

        case .yawn:
            p.stroke("M21 36Q25 38 29 36M35 36Q39 38 43 36")
            cheeks(p, y: 41, left: 17.5, right: 46.5)
            p.ellipse(32, 46, 3.6, 4.4, fill: ink)
            p.fill("M29.6 48.6Q32 47 34.4 48.6Q33.6 50.4 32 50.4Q30.4 50.4 29.6 48.6Z", Palette.tongue)

        case .relieved:
            p.stroke("M21.5 36.5Q25 39.5 28.5 36.5M35.5 36.5Q39 39.5 42.5 36.5", width: 2.2)
            cheeks(p, y: 43, rx: 4.5, ry: 2.6, alpha: 0.65)
            p.stroke("M28.5 44Q32 47 35.5 44")

        case .surprised:
            p.circle(25, 34, 3.6, fill: Palette.white, stroke: ink, width: 1.6)
            p.circle(39, 34, 3.6, fill: Palette.white, stroke: ink, width: 1.6)
            p.circle(25, 34.3, 1.7, fill: ink)
            p.circle(39, 34.3, 1.7, fill: ink)
            p.ellipse(32, 45.5, 2.4, 2.8, fill: ink)
        }
    }

    // MARK: CPU: speed lines

    private static func drawWork(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        guard scene.work != .none else { return }
        let base: CGFloat = scene.work == .strong ? 0.55 : 0.25
        let alpha = base + 0.3 * pulse(t, scene.work == .strong ? 0.4 : 0.6)
        // A side only gets lines while its hand is free, so they never cross a prop.
        if scene.network == .none { p.stroke("M0 30H4M-1 37H3", width: 2, alpha: alpha) }
        if scene.disk == .none { p.stroke("M60 30H64M61 37H65", width: 2, alpha: alpha) }
    }

    // MARK: Temperature: sweat and steam

    private static func drawSweat(_ p: Painter, _ t: Double) {
        let first = cycle(t, 1.5)
        p.group(CGAffineTransform(translationX: 0, y: 8 * first), alpha: fadeInOut(first)) {
            p.shape("M53 13C53 13 57 18 57 20.5A4 4 0 0 1 49 20.5C49 18 53 13 53 13Z", fill: Palette.sweat, width: 1.5)
        }
        // The other drop flies off the top of his head, clear of the left hand.
        let second = cycle(t, 1.5, delay: 0.75)
        p.group(CGAffineTransform(translationX: -3 * second, y: 5 * second), alpha: fadeInOut(second)) {
            p.shape("M15 4.5C15 4.5 18 8.3 18 10.1A3 3 0 0 1 12 10.1C12 8.3 15 4.5 15 4.5Z", fill: Palette.sweat, width: 1.4)
        }
    }

    /// Critical heat: his head is on fire. Drawn behind the body, so it rises from his head.
    private static func drawFlame(_ p: Painter, _ t: Double) {
        let k = pulse(t, 0.45)
        p.group(.scale(1 - 0.07 * k, 1 + 0.08 * k, around: 32, 18)) {
            p.shape("M32 -2C35 4 41 5 40 11C43 9 43.5 5.5 42.5 3C48 8 47 16 41 18H23C17 16 16 9 21 4.5C21 7.5 22.5 9.5 24.5 10.5C23 5 28 2 32 -2Z", fill: Palette.flame, width: 1.6)
            p.fill("M32 5C34 9 37 10 36.5 13.5C38 13 38.5 11 38 10C40.5 13 39.5 17 37 18H27C25 17 24.5 14 26.5 12C27 13.5 28 14.5 29 15C28.5 11 30.5 8 32 5Z", Palette.flameCore)
        }
    }

    private static func drawSteam(_ p: Painter, _ t: Double) {
        for (delay, data) in [(0.0, "M4 20Q1 15 4 11Q7 7 4 2"), (0.9, "M62 22Q59 17 62 13Q65 9 62 4")] {
            let c = cycle(t, 1.8, delay: delay)
            p.group(CGAffineTransform(translationX: 0, y: 3 - 6 * c), alpha: CGFloat(sin(.pi * Double(c)))) {
                p.stroke(data, width: 1.8, alpha: 0.5)
            }
        }
    }

    // MARK: Hands

    private static func hand(_ p: Painter, _ scene: BlippScene, _ x: CGFloat, _ y: CGFloat) {
        p.circle(x, y, 2.8, fill: scene.color, stroke: Palette.ink, width: 1.4)
    }

    /// Left hand: network. Props use the panel's graph colors: blue down, violet up.
    private static func drawNetwork(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        let both = scene.network == .both
        if scene.network == .download || both {
            let y: CGFloat = both ? 44 : 40
            let bounce = -1.2 * pulse(t, 1.2)
            p.group(CGAffineTransform(translationX: 0, y: bounce)) {
                p.rect(-5, y, 13, 11, radius: 1.5, fill: Palette.cardboard, width: 1.4)
                let drop = 1.2 * cycle(t, 0.9)
                p.group(CGAffineTransform(translationX: 0, y: drop)) {
                    p.stroke(both ? "M1.5 45.8V51.3M-1 49.1L1.5 51.6L4 49.1" : "M1.5 41.8V47.3M-1 45.1L1.5 47.6L4 45.1", Palette.download, width: 1.8)
                }
                hand(p, scene, 9, y + 6)
            }
        }
        if scene.network == .upload || both {
            let wobble = 4 * CGFloat(sin(2 * .pi * t / 1.6))
            p.group(.rotation(wobble, around: both ? 2 : 3, both ? 30 : 36)) {
                p.shape(both ? "M-6 30L9 25L4 35L2.5 31Z" : "M-6 36L10 30L4.5 42L2.5 37Z", fill: Palette.white, stroke: Palette.upload, width: 1.5)
            }
            p.stroke(both ? "M8 36Q3 38 0 41" : "M9 44Q3 46 -1 50", Palette.upload, width: 1.2, alpha: 0.4 + 0.5 * pulse(t, 0.8), dash: [1.5, 2])
            hand(p, scene, 9.5, both ? 33 : 39)
        }
        if scene.network == .offline {
            p.group(CGAffineTransform(translationX: 0, y: -1.5 * pulse(t, 2.6))) {
                p.shape("M-3 46A3.5 3.5 0 0 1 -1 39.5A4.5 4.5 0 0 1 7.5 39A3.5 3.5 0 0 1 9 46Z", fill: Palette.white, width: 1.4)
                p.stroke("M-1 48L8 37", Palette.red, width: 1.8)
            }
        }
    }

    /// Right hand: disk. Blue lines for reading, a rose pencil for writing.
    private static func drawDisk(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        let both = scene.disk == .both
        if scene.disk == .read || both {
            let x: CGFloat = both ? 53 : 52
            let y: CGFloat = both ? 29 : 38
            p.group(.rotation(3 * CGFloat(sin(2 * .pi * t / 2.2)), around: x + 6, y + 15)) {
                p.rect(x, y, 12, 15, radius: 1.2, fill: Palette.white, width: 1.4)
                // The line being read lights up, one after another.
                let current = Int(cycle(t, 1.8) * 3)
                for (index, (dy, length)) in [(4.0, 7.0), (7.0, 7.0), (10.0, 4.5)].enumerated() {
                    let lineY = y + CGFloat(dy)
                    p.cg.move(to: CGPoint(x: x + 2.5, y: lineY))
                    p.cg.addLine(to: CGPoint(x: x + 2.5 + CGFloat(length), y: lineY))
                    p.cg.setStrokeColor(Painter.color(Palette.read, index == current ? 1 : 0.55))
                    p.cg.setLineWidth(1.3)
                    p.cg.setLineCap(.round)
                    p.cg.strokePath()
                }
            }
            hand(p, scene, both ? 55.5 : 55, both ? 37 : 47)
        }
        if scene.disk == .write || both {
            let wiggle = 7 * CGFloat(sin(2 * .pi * t / 0.35))
            p.group(both ? CGAffineTransform(translationX: -6, y: 3) : .identity) {
                p.group(.rotation(wiggle, around: 49, 58.5)) {
                    p.shape("M50 54L62 42L65.5 45.5L53.5 57.5L49 58.5Z", fill: Palette.write, width: 1.3)
                    p.shape("M49 58.5L50 54L53.5 57.5Z", fill: Palette.pencilTip, width: 1)
                }
                hand(p, scene, 56, 51)
            }
        }
    }

    /// The sticker at his feet: battery. While charging he sips through a straw or eats a cookie.
    private static func drawSticker(_ p: Painter, _ scene: BlippScene, _ t: Double, _ intro: BlippIntro?) {
        switch scene.sticker {
        case .none:
            break

        case .juice:
            let slurping = intro?.kind == .slurp ? CGFloat(sin(.pi * (intro?.progress ?? 0))) : 0
            let squeeze = 0.05 * pulse(t, 1.1) + 0.1 * slurping
            p.stroke("M36 54L36.8 48.8L33.4 44.6", Palette.straw, width: 1.8)
            p.group(.scale(1 - squeeze, 1, around: 33.5, 58)) {
                p.rect(28, 52, 11, 12, radius: 1.6, fill: Palette.juice, width: 1.3)
                p.fill("M34.2 54.2L31.6 58.6H33.6L32.6 62.2L35.6 57.2H33.4Z", Palette.ink)
            }

        case .cookie:
            p.shape("M39.1 55.3A6.2 6.2 0 1 1 35.7 52.7A2.3 2.3 0 0 0 39.1 55.3Z", fill: Palette.cookie, width: 1.3)
            for (x, y, r) in [(31.5, 57.5, 0.9), (35.0, 61.5, 0.9), (36.5, 58.0, 0.8)] {
                p.circle(CGFloat(x), CGFloat(y), CGFloat(r), fill: Palette.ink)
            }
            for (delay, x) in [(0.0, 38.0), (0.6, 40.5)] {
                let c = cycle(t, 1.2, delay: delay)
                p.group(CGAffineTransform(translationX: 0, y: 7 * c), alpha: fadeInOut(c, fadeIn: 0.2, holdUntil: 0.2)) {
                    p.circle(CGFloat(x), 53, 0.9, fill: 0xC98F4A)
                }
            }

        case .limit:
            p.stroke("M36.5 55L37.6 48.4L42.6 46.4", Palette.straw, width: 1.8)
            p.rect(28, 52, 11, 12, radius: 1.6, fill: Palette.juice, width: 1.3)
            p.stroke("M30.5 58L32.8 60.3L36.6 55.5", Palette.green, width: 1.8)

        case .low:
            let blink = cycle(t, 1) < 0.5
            p.rect(25.5, 54.5, 13, 7.5, radius: 1.6, fill: Palette.white, stroke: Palette.red, width: 1.4)
            p.rect(38.7, 56.7, 1.8, 3, radius: 0.5, fill: Palette.red, stroke: nil)
            if blink { p.rect(27.1, 56.1, 3, 4.3, radius: 0.6, fill: Palette.red, stroke: nil) }
        }
    }

    // MARK: Above the head

    private static func juggle(_ p: Painter, _ t: Double, balls: [(CGFloat, CGFloat, UInt32)], period: Double, radius: CGFloat) {
        let angle = CGFloat(360 * cycle(t, period))
        p.group(.rotation(angle, around: 32, 0)) {
            for (x, y, color) in balls {
                p.circle(x, y, radius, fill: color, stroke: Palette.ink, width: 1.5)
            }
        }
    }

    private static func zLetter(_ p: Painter, x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat) {
        // One unit-sized "Z", moved and scaled into place: building the path from the animated
        // coordinates would give SVGPath's cache a new entry every frame.
        p.group(CGAffineTransform(translationX: x, y: y).scaledBy(x: size, y: size)) {
            p.stroke("M0 0H0.75L0 1H0.75", width: 0.2, alpha: alpha)
        }
    }

    // MARK: Gear

    /// A gear centered on (cx, cy): `teeth` trapezoid teeth between `root` and `outer`, with a
    /// round hole. `tip` and `base` are the share of each tooth's slice its top and foot take up.
    private static func gearPath(cx: CGFloat, cy: CGFloat, teeth: Int, outer: CGFloat, root: CGFloat, hole: CGFloat,
                                 tip: CGFloat = 0.42, base: CGFloat = 0.62) -> CGPath {
        let path = CGMutablePath()
        let pitch = 2 * CGFloat.pi / CGFloat(teeth)
        let center = CGPoint(x: cx, y: cy)
        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
        }
        for i in 0..<teeth {
            let mid = CGFloat(i) * pitch - .pi / 2
            let baseHalf = pitch * base / 2
            let tipHalf = pitch * tip / 2
            if i == 0 { path.move(to: point(root, mid - baseHalf)) }
            path.addLine(to: point(outer, mid - tipHalf))
            path.addArc(center: center, radius: outer, startAngle: mid - tipHalf, endAngle: mid + tipHalf, clockwise: false)
            path.addLine(to: point(root, mid + baseHalf))
            path.addArc(center: center, radius: root, startAngle: mid + baseHalf, endAngle: mid + pitch - baseHalf, clockwise: false)
        }
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: cx - hole, y: cy - hole, width: hole * 2, height: hole * 2))
        return path
    }

    /// Eight teeth and a hole: still clearly a gear at the panel's 50 points.
    private static let gear = gearPath(cx: 50, cy: 8, teeth: 8, outer: 7.6, root: 5.8, hole: 2.3)

    private static func drawHead(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        switch scene.head {
        case .none:
            break

        case .zzz:
            for (delay, x, y, size) in [(0.0, 47.0, 6.0, 7.0), (1.4, 54.0, 0.0, 5.0)] {
                let c = cycle(t, 2.8, delay: delay)
                let alpha: CGFloat = c < 0.3 ? c / 0.3 : 1 - (c - 0.3) / 0.7
                zLetter(p, x: CGFloat(x) + 4 * c, y: CGFloat(y) + 4 - 10 * c, size: CGFloat(size), alpha: alpha)
            }

        case .gear:
            p.group(.rotation(CGFloat(360 * cycle(t, 2.4)), around: 50, 8)) {
                p.shape(gear, fill: Palette.steel, width: 1.4)
            }

        case .juggle3:
            juggle(p, t, balls: [
                (32, -9, Palette.ballPink), (39.8, 4.5, Palette.ballBlue), (24.2, 4.5, Palette.ballYellow),
            ], period: 1.8, radius: 3.8)

        case .juggle5:
            juggle(p, t, balls: [
                (32, -11, Palette.ballPink), (40.5, -5, Palette.ballBlue), (40.5, 5, Palette.ballPurple),
                (23.5, 5, Palette.ballYellow), (23.5, -5, Palette.mint),
            ], period: 1.0, radius: 3.4)
            // One keeps slipping away.
            let c = cycle(t, 1.6)
            p.group(CGAffineTransform(translationX: 6 * c, y: 16 * c * c), alpha: fadeInOut(c, fadeIn: 0.1, holdUntil: 0.7)) {
                p.circle(46, 2, 3.1, fill: Palette.ballOrange, stroke: Palette.ink, width: 1.4)
            }

        case .swapBox:
            // A closed moving box: memory packed off to the SSD.
            p.group(CGAffineTransform(translationX: 0, y: -1.5 * pulse(t, 1.4))) {
                p.shape("M23 -7L27 -11H42L38 -7Z", fill: Palette.cardboardLight, width: 1.3)
                p.shape("M38 -7L42 -11V0L38 4Z", fill: Palette.cardboardDark, width: 1.3)
                p.rect(23, -7, 15, 11, radius: 0.8, fill: Palette.cardboard, width: 1.4)
                p.fill("M29.3 -7L33.3 -11H36L32 -7Z", Palette.tape)
                p.rect(29.3, -7, 2.7, 11, radius: 0, fill: Palette.tape, stroke: nil)
                p.rect(33.2, -3.6, 3.6, 2.7, radius: 0.5, fill: Palette.white, width: 0.8)
                p.stroke("M26 1.6V-3.4M24.4 -1.8L26 -3.5L27.6 -1.8", width: 0.9)
            }
        }
    }
}

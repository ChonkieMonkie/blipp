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

enum BlippRenderer {
    /// Draws Blipp with the 64-unit design box placed at `origin` and scaled to `size` points.
    /// Some parts (flames, juggling balls, clouds) reach above the box, so leave headroom.
    static func draw(_ scene: BlippScene, in cg: CGContext, origin: CGPoint = .zero, size: CGFloat, time: Double) {
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: size / 64, y: size / 64)
        let p = Painter(cg: cg)
        let t = time

        // Shadow
        switch scene.shape {
        case .puddle: p.ellipse(32, 58.5, 27, 2.5, fill: Palette.ink, alpha: 0.12)
        case .wide: p.ellipse(32, 59.5, 24, 2.5, fill: Palette.ink, alpha: 0.12)
        default: p.ellipse(32, 59.5, 19, 2.5, fill: Palette.ink, alpha: 0.12)
        }

        if scene.overhead == .flame {
            drawFlame(p, t)
        }

        p.group(bodyTransform(scene, t)) {
            drawBody(p, scene)
            p.group(CGAffineTransform(translationX: 0, y: faceOffset(scene.shape))) {
                drawFace(p, scene, t)
            }
        }

        // Things held near the mouth move with the face when Blipp is squished (asleep).
        let handsOffset: CGFloat = scene.shape == .squished ? faceOffset(scene.shape) : 0
        p.group(CGAffineTransform(translationX: 0, y: handsOffset)) {
            drawHands(p, scene, t)
        }
        drawOverhead(p, scene, t)

        if scene.sweat {
            let first = cycle(t, 1.5)
            p.group(CGAffineTransform(translationX: 0, y: 9 * first), alpha: fadeInOut(first)) {
                p.shape("M51 15C51 15 55 20 55 22.5A4 4 0 0 1 47 22.5C47 20 51 15 51 15Z", fill: Palette.sweat, width: 1.5)
            }
            let second = cycle(t, 1.5, delay: 0.75)
            p.group(CGAffineTransform(translationX: 0, y: 9 * second), alpha: fadeInOut(second)) {
                p.shape("M12 20C12 20 15 23.8 15 25.6A3 3 0 0 1 9 25.6C9 23.8 12 20 12 20Z", fill: Palette.sweat, width: 1.4)
            }
        }

        if scene.tear {
            let c = cycle(t, 2)
            p.group(CGAffineTransform(translationX: 0, y: 9 * c), alpha: fadeInOut(c)) {
                p.shape("M22.5 40C22.5 40 25 43 25 44.5A2.5 2.5 0 0 1 20 44.5C20 43 22.5 40 22.5 40Z", fill: Palette.sweat, width: 1.2)
            }
        }

        cg.restoreGState()
    }

    private static func bodyTransform(_ scene: BlippScene, _ t: Double) -> CGAffineTransform {
        var transform: CGAffineTransform
        switch scene.shape {
        case .squished:
            let k = pulse(t, 3.6)
            transform = .scale(1 + 0.03 * k, 1 - 0.03 * k, around: 32, 58)
        case .puddle:
            transform = .scale(1 + 0.03 * pulse(t, 2.5), 1, around: 32, 57)
        case .wide:
            let k = pulse(t, 1.6)
            transform = .scale(1 + 0.04 * k, 1 - 0.03 * k, around: 32, 57)
        default:
            transform = CGAffineTransform(translationX: 0, y: -1.6 * pulse(t, scene.bobPeriod))
        }
        if scene.shake {
            transform = transform.concatenating(CGAffineTransform(translationX: 0.7 * CGFloat(sin(2 * .pi * t / 0.22)), y: 0))
        }
        if scene.dizzy {
            transform = transform.concatenating(.rotation(3 * CGFloat(sin(2 * .pi * t / 0.8)), around: 32, 57))
        }
        return transform
    }

    private static func faceOffset(_ shape: BlippScene.Shape) -> CGFloat {
        switch shape {
        case .squished: return 5
        case .puddle: return 9.5
        default: return 0
        }
    }

    private static func drawBody(_ p: Painter, _ scene: BlippScene) {
        switch scene.shape {
        case .normal:
            p.shape("M32 10C47 10 55 21 55 36C55 50 45 57 32 57C19 57 9 50 9 36C9 21 17 10 32 10Z", fill: scene.color)
            p.stroke("M17 26C18 20 22 15.5 27 14", Palette.white, width: 2.5, alpha: 0.7)
        case .squished:
            p.shape("M32 18C48 18 57 28 57 40C57 52 46 58 32 58C18 58 7 52 7 40C7 28 16 18 32 18Z", fill: scene.color)
            p.stroke("M16 32C18 27 22 23.5 27 22", Palette.white, width: 2.5, alpha: 0.7)
        case .round:
            p.shape("M32 11C48 11 57 22 57 37C57 50 46 57 32 57C18 57 7 50 7 37C7 22 16 11 32 11Z", fill: scene.color)
            p.stroke("M16 27C17 21 21 16.5 26 15", Palette.white, width: 2.5, alpha: 0.7)
        case .wide:
            p.shape("M32 12C50 12 61 23 61 37C61 51 48 57 32 57C16 57 3 51 3 37C3 23 14 12 32 12Z", fill: scene.color)
            p.stroke("M14 26C16 20 21 16 27 15", Palette.white, width: 2.5, alpha: 0.7)
        case .puddle:
            p.shape("M6 57C6 50 13 47 19 47C20 40 26 37 32 37C38 37 44 40 45 47C51 47 58 50 58 57Z", fill: scene.color)
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

        case .happyClosed:
            p.stroke("M21.5 37Q25 32 28.5 37M35.5 37Q39 32 42.5 37", width: 2.2)
            p.ellipse(18.5, 43, 4.5, 2.8, fill: Palette.cheek, alpha: 0.55)
            p.circle(34, 45.5, 1.8, fill: ink)

        case .chewing:
            p.stroke("M21 35Q25 38.5 29 35M35 35Q39 38.5 43 35", width: 2.2)
            p.ellipse(18, 42, 5, 3.4, fill: Palette.cheek, alpha: 0.55)
            p.group(.scale(1, 1 - 0.6 * pulse(t, 0.5), around: 31, 44.5)) {
                p.ellipse(31, 44.5, 3.6, 2.2, fill: ink)
            }

        case .content:
            p.stroke("M20.5 35.5Q24.5 39 28.5 35.5M35.5 35.5Q39.5 39 43.5 35.5", width: 2.2)
            cheeks(p, y: 42, rx: 4.5, ry: 2.6, alpha: 0.55, left: 17.5, right: 46.5)
            p.fill("M26.5 42.5H37.5Q37 49.5 32 49.5Q27 49.5 26.5 42.5Z", ink)
            p.fill("M29 47.5Q32 45.5 35 47.5Q34 49.5 32 49.5Q30 49.5 29 47.5Z", Palette.tongue)

        case .pleased:
            p.stroke("M21 35.5Q25 39 29 35.5M35 35.5Q39 39 43 35.5", width: 2.2)
            cheeks(p, y: 42.5)
            p.stroke("M28 43.5Q32 47 36 43.5")

        case .tired:
            p.fill("M21 37A4 4 0 0 0 29 37Z", ink)
            p.fill("M35 37A4 4 0 0 0 43 37Z", ink)
            p.stroke("M20 37H30M34 37H44")
            let c = cycle(t, 3.5)
            let open: CGFloat
            if c < 0.6 {
                open = 0.5
            } else if c < 0.75 {
                open = 0.5 + 0.65 * (c - 0.6) / 0.15
            } else {
                open = 1.15 - 0.65 * (c - 0.75) / 0.25
            }
            p.group(.scale(1, open, around: 32, 47)) {
                p.ellipse(32, 47, 3.2, 3.8, fill: ink)
            }

        case .dead:
            p.stroke("M24 34L28 38M28 34L24 38M36 34L40 38M40 34L36 38")
            p.stroke("M28 43Q30 41.5 32 43Q34 44.5 36 43", width: 1.8)

        case .dizzy:
            p.stroke("M25 36.5A1.5 1.5 0 1 1 26.5 35A3 3 0 1 1 23.5 32A4.2 4.2 0 0 1 29.2 36", width: 1.8)
            p.stroke("M39 36.5A1.5 1.5 0 1 1 40.5 35A3 3 0 1 1 37.5 32A4.2 4.2 0 0 1 43.2 36", width: 1.8)
            p.stroke("M27 46Q29.5 43.5 32 46Q34.5 48.5 37 46")

        case .lookingUp:
            eyes(p, y: 34, glint: CGPoint(x: 0.5, y: -1.6))
            p.ellipse(32, 45, 2.2, 2.6, fill: ink)

        case .determined:
            p.stroke("M20.5 30.5L28.5 32.5M43.5 30.5L35.5 32.5", width: 2.2)
            eyes(p, y: 36.5)
            p.stroke("M28 46Q32 43.5 36 46")

        case .relieved:
            p.stroke("M21.5 36.5Q25 39.5 28.5 36.5M35.5 36.5Q39 39.5 42.5 36.5", width: 2.2)
            cheeks(p, y: 43, rx: 4.5, ry: 2.6, alpha: 0.65)
            p.stroke("M28.5 44Q32 47 35.5 44")

        case .licking:
            squintEyes(p)
            p.ellipse(45.5, 43.5, 4, 2.4, fill: Palette.cheek, alpha: 0.6)
            p.stroke("M30 44Q34 47 38 44")
            p.stroke("M30.5 44.5Q27 47.5 24 45.5", Palette.tongue, width: 2.6)

        case .boiling:
            p.stroke("M21 32L28.5 34.5M43 32L35.5 34.5", width: 2.2)
            p.stroke("M21.5 38Q25 36 28.5 38M35.5 38Q39 36 42.5 38", width: 2.2)
            p.stroke("M28 46Q31 44 34 46")

        case .excited:
            eyes(p, y: 34.5, glint: CGPoint(x: 0.6, y: -1.5))
            cheeks(p, y: 43)
            p.fill("M27.5 42.5H36.5Q36 48.5 32 48.5Q28 48.5 27.5 42.5Z", ink)

        case .wink:
            p.circle(25, 36, 3.2, fill: ink)
            p.circle(25.8, 34.8, 1, fill: Palette.white)
            p.stroke("M35.5 36.5Q39 33 42.5 36.5", width: 2.2)
            cheeks(p, y: 43)
            p.stroke("M27.5 43Q32 47.5 36.5 43")

        case .sad:
            p.stroke("M21 31.5L28 29.5M43 31.5L36 29.5")
            eyes(p, y: 36.5)
            p.stroke("M28 47Q32 43.5 36 47")

        case .surprised:
            p.circle(14, 42, 7, fill: 0xFF9EB5, alpha: 0.65)
            p.circle(50, 42, 7, fill: 0xFF9EB5, alpha: 0.65)
            p.circle(25, 33, 3.6, fill: Palette.white, stroke: ink, width: 1.6)
            p.circle(39, 33, 3.6, fill: Palette.white, stroke: ink, width: 1.6)
            p.circle(25, 33.3, 1.7, fill: ink)
            p.circle(39, 33.3, 1.7, fill: ink)
            p.stroke("M28.5 45Q32 43.5 35.5 45")
            p.shape("M33 44.5L38 41.5L40 45.5L35 48Z", fill: Palette.white, width: 1.3)
        }
    }

    // MARK: Hands

    private static func hand(_ p: Painter, _ scene: BlippScene, _ x: CGFloat, _ y: CGFloat) {
        p.ellipse(x, y, 3.4, 3, fill: scene.color, stroke: Palette.ink, width: 1.6)
    }

    private static func drawHands(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        switch scene.hands {
        case .none:
            break

        case .juice:
            p.group(CGAffineTransform(translationX: 0, y: -1.2 * pulse(t, 1.1))) {
                p.stroke("M53 38V31L35.5 45", Palette.straw, width: 2.2)
                p.rect(43, 38, 14, 17, radius: 2.5, fill: Palette.juice)
                p.stroke("M43 41.5H57", width: 1.5)
                p.fill("M51.5 43.5L47.5 49H50.5L49 53.5L54 47.5H51L52.5 43.5Z", Palette.ink)
                hand(p, scene, 44, 49)
            }

        case .cookie:
            // The bite is a real hole in the cookie, so whatever is behind it (an eye, the
            // background) shows through instead of being painted over.
            let bites = [CGRect(x: 34.9, y: 37.4, width: 7.2, height: 7.2), CGRect(x: 38.9, y: 36.6, width: 5.2, height: 5.2)]
            let cookie = CGRect(x: 36, y: 38, width: 18, height: 18)
            p.cg.saveGState()
            p.cg.addRect(CGRect(x: -20, y: -20, width: 104, height: 104))
            bites.forEach { p.cg.addEllipse(in: $0) }
            p.cg.clip(using: .evenOdd)
            p.circle(45, 47, 9, fill: Palette.cookie, stroke: Palette.ink)
            p.fill("M46.5 41.5L42.5 47.5H45.5L44 52L49 46H46L47.5 41.5Z", 0xFFF2B3)
            p.stroke("M46.5 41.5L42.5 47.5H45.5L44 52L49 46H46L47.5 41.5Z", width: 1.1)
            p.circle(41, 53, 1, fill: Palette.ink, alpha: 0.5)
            p.circle(49, 51, 1, fill: Palette.ink, alpha: 0.5)
            p.cg.restoreGState()
            // Outline the bite's edge, but only on the cookie side of it.
            p.cg.saveGState()
            p.cg.addEllipse(in: cookie)
            p.cg.clip()
            p.cg.addRect(CGRect(x: -20, y: -20, width: 104, height: 104))
            bites.forEach { p.cg.addEllipse(in: $0) }
            p.cg.clip(using: .evenOdd)
            for bite in bites {
                p.ring(bite.midX, bite.midY, bite.width / 2, width: 2.4)
            }
            p.cg.restoreGState()
            hand(p, scene, 38, 50)
            for (delay, x, y) in [(0.0, 34.0, 50.0), (0.6, 37.0, 52.0)] {
                let c = cycle(t, 1.2, delay: delay)
                p.group(CGAffineTransform(translationX: 0, y: 8 * c), alpha: fadeInOut(c, fadeIn: 0.2, holdUntil: 0.2)) {
                    p.circle(CGFloat(x), CGFloat(y), 1, fill: 0xC98F4A)
                }
            }

        case .juiceAside:
            p.stroke("M54 45V39.5L57 37.5", Palette.straw, width: 2)
            p.rect(47, 45, 12, 13, radius: 2.2, fill: Palette.juice, width: 1.8)
            p.stroke("M47 48H59", width: 1.3)
            p.fill("M54 49.5L50.8 53.8H53.2L52 57L56 52.4H53.6L54.8 49.5Z", Palette.ink)
            let wave = 10 * CGFloat(sin(2 * .pi * t / 0.9))
            p.group(.rotation(wave, around: 12, 36)) {
                p.stroke("M4 25L2 22M8 23.5V20M12 25L14 22", width: 1.4, alpha: 0.5)
                p.ellipse(8, 30, 3.6, 3.2, fill: scene.color, stroke: Palette.ink, width: 1.6)
            }

        case .fan:
            let angle = 14 * CGFloat(sin(2 * .pi * t / 0.45))
            p.group(.rotation(angle, around: 50, 46)) {
                p.shape("M50 46L41 30A13 13 0 0 1 59 30Z", fill: 0xFF9EB5, width: 1.8)
                p.stroke("M50 46L46 30.5M50 46L50 29M50 46L54 30.5", width: 1.1, alpha: 0.55)
            }
            hand(p, scene, 50, 47)

        case .iceCream:
            p.shape("M11 41L17 57L23 41Z", fill: Palette.cookie, width: 1.8)
            p.stroke("M13.5 45L20.5 45M15 49.5L19.5 49.5", width: 1, alpha: 0.5)
            p.shape("M10 41C10 36 13 33 17 33C21 33 24 36 24 41C22.5 42.5 21 41 19.5 42.5C18 44 16 42 14.5 43C13 44 11.5 42 10 41Z", fill: 0xFFB3C7, width: 1.8)
            for (delay, data) in [(0.0, "M12.5 43V46"), (0.75, "M21 43.5V46")] {
                let c = cycle(t, 1.5, delay: delay)
                p.group(CGAffineTransform(translationX: 0, y: 9 * c), alpha: fadeInOut(c)) {
                    p.stroke(data, 0xFFB3C7, width: 2.4)
                }
            }

        case .catchBox:
            let c = cycle(t, 1.6)
            let y: CGFloat = c < 0.7 ? -8 + 11 * (c / 0.7) : 3
            let alpha: CGFloat = c < 0.25 ? c / 0.25 : (c < 0.7 ? 1 : max(0, 1 - (c - 0.7) / 0.3))
            p.group(CGAffineTransform(translationX: 0, y: y), alpha: alpha) {
                p.rect(24.5, -8, 15, 12, radius: 1.8, fill: Palette.cardboard, width: 1.8)
                p.stroke("M32 -5V1.5M28.8 -1.5L32 1.5L35.2 -1.5", width: 1.6)
            }
            hand(p, scene, 17, 15)
            hand(p, scene, 47, 15)

        case .plane:
            p.stroke("M50 22Q52 16 55 13", width: 1.4, alpha: 0.5, dash: [2, 2])
            hand(p, scene, 51, 25)
            let c = cycle(t, 1.8)
            p.group(CGAffineTransform(translationX: -6 + 12 * c, y: 8 - 16 * c), alpha: fadeInOut(c, fadeIn: 0.2, holdUntil: 0.2)) {
                p.shape("M48 10L63 2L56 16L54 11Z", fill: Palette.white, width: 1.6)
                p.stroke("M54 11L63 2", width: 1.1)
            }

        case .papers:
            p.group(.rotation(-8, around: 49.5, 46.5)) {
                p.rect(41, 40, 17, 13, radius: 1.5, fill: Palette.white, width: 1.6)
            }
            p.group(.rotation(6, around: 50.5, 44.5)) {
                p.rect(42, 38, 17, 13, radius: 1.5, fill: Palette.white, width: 1.6)
                p.stroke("M45 42H55M45 45H53M45 48H55", width: 1, alpha: 0.5)
            }
            hand(p, scene, 43, 48)
            for (delay, x, y, w, h) in [(0.0, 48.0, 22.0, 9.0, 7.0), (0.7, 51.0, 28.0, 8.0, 6.0)] {
                let c = cycle(t, 1.4, delay: delay)
                let move = CGAffineTransform(translationX: 10 * c, y: -12 * c)
                p.group(move, alpha: fadeInOut(c, fadeIn: 0.2, holdUntil: 0.2)) {
                    p.group(.rotation(40 * c, around: CGFloat(x + w / 2), CGFloat(y + h / 2))) {
                        p.rect(CGFloat(x), CGFloat(y), CGFloat(w), CGFloat(h), radius: 1, fill: Palette.white, width: 1.3)
                    }
                }
            }

        case .packBox:
            for (delay, x, color) in [(0.0, 52.0, Palette.ballPink), (0.65, 57.0, Palette.ballYellow)] {
                let c = cycle(t, 1.3, delay: delay)
                p.group(CGAffineTransform(translationX: 0, y: -10 + 18 * c), alpha: fadeInOut(c, fadeIn: 0.2, holdUntil: 0.8)) {
                    p.circle(CGFloat(x), 36, 3.4, fill: color, stroke: Palette.ink, width: 1.5)
                }
            }
            p.stroke("M44 46L40 41.5M64 46L68 41.5")
            p.shape("M44 46H64V60H44Z", fill: Palette.cardboard)
            p.rect(49, 51, 10, 4, radius: 1, fill: 0xF4E3C9, stroke: nil)
            hand(p, scene, 45, 49)

        case .thermometer:
            p.stroke("M33 46L52 36.5", width: 5)
            p.stroke("M33 46L52 36.5", Palette.white, width: 2.6)
            p.stroke("M41 42L52 36.5", Palette.red, width: 2.6)
        }
    }

    // MARK: Above the head

    private static func drawFlame(_ p: Painter, _ t: Double) {
        let k = pulse(t, 0.45)
        p.group(.scale(1 - 0.07 * k, 1 + 0.08 * k, around: 32, 18)) {
            p.shape("M32 -2C35 4 41 5 40 11C43 9 43.5 5.5 42.5 3C48 8 47 16 41 18H23C17 16 16 9 21 4.5C21 7.5 22.5 9.5 24.5 10.5C23 5 28 2 32 -2Z", fill: 0xFFB020, width: 1.6)
            p.fill("M32 5C34 9 37 10 36.5 13.5C38 13 38.5 11 38 10C40.5 13 39.5 17 37 18H27C25 17 24.5 14 26.5 12C27 13.5 28 14.5 29 15C28.5 11 30.5 8 32 5Z", 0xFFE27A)
        }
    }

    private static func juggle(_ p: Painter, _ scene: BlippScene, _ t: Double, balls: [(CGFloat, CGFloat, UInt32)], period: Double, radius: CGFloat) {
        let angle = CGFloat(360 * cycle(t, period))
        p.group(.rotation(angle, around: 32, 0)) {
            for (x, y, color) in balls {
                p.circle(x, y, radius, fill: color, stroke: Palette.ink, width: 1.6)
            }
        }
        hand(p, scene, 9, 24)
        hand(p, scene, 55, 24)
    }

    private static func zLetter(_ p: Painter, x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat) {
        // One unit-sized "Z", moved and scaled into place: building the path from the animated
        // coordinates would give SVGPath's cache a new entry every frame.
        p.group(CGAffineTransform(translationX: x, y: y).scaledBy(x: size, y: size)) {
            p.stroke("M0 0H0.75L0 1H0.75", width: 0.2, alpha: alpha)
        }
    }

    private static func battery(_ p: Painter, x: CGFloat, y: CGFloat, outline: UInt32, fillWidth: CGFloat, fillColor: UInt32) {
        p.rect(x, y, 15, 8, radius: 1.8, fill: Palette.white, stroke: outline, width: 1.6)
        p.rect(x + 15.5, y + 2.2, 2.2, 3.6, radius: 0.6, fill: outline, stroke: nil)
        if fillWidth > 0 {
            p.rect(x + 2, y + 2, fillWidth, 4, radius: 0.6, fill: fillColor, stroke: nil)
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

    private static func drawOverhead(_ p: Painter, _ scene: BlippScene, _ t: Double) {
        switch scene.overhead {
        case .none, .flame:
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
            let flash = pulse(t, 0.6)
            p.stroke("M1 30H5M0 37H4M59 30H63M60 37H64", width: 2, alpha: 0.2 + 0.5 * flash)

        case .juggle3:
            juggle(p, scene, t, balls: [
                (32, -9, Palette.ballPink), (39.8, 4.5, Palette.ballBlue), (24.2, 4.5, Palette.ballYellow),
            ], period: 1.8, radius: 4)

        case .juggle5:
            juggle(p, scene, t, balls: [
                (32, -9, Palette.ballPink), (40.5, -3, Palette.ballBlue), (40.5, 7, Palette.ballPurple),
                (23.5, 7, Palette.ballYellow), (23.5, -3, Palette.mint),
            ], period: 1.0, radius: 3.6)
            let roll = 2 * pulse(t, 1.2)
            p.circle(5 + roll, 56, 3.4, fill: Palette.ballOrange, stroke: Palette.ink, width: 1.5)
            p.circle(60 - roll, 56.5, 3, fill: Palette.ballBlue, stroke: Palette.ink, width: 1.5)

        case .cloudOffline:
            p.group(CGAffineTransform(translationX: 0, y: -2.5 * pulse(t, 2.6))) {
                p.shape("M22 4A6 6 0 0 1 27 -4A7 7 0 0 1 40 -3A5 5 0 0 1 42 7H24A4 4 0 0 1 22 4Z", fill: Palette.white, width: 1.6)
                p.stroke("M26 7L39 -5", Palette.red, width: 2)
            }

        case .lowBattery:
            if cycle(t, 1) < 0.5 {
                battery(p, x: 24, y: 1, outline: Palette.ink, fillWidth: 3, fillColor: Palette.red)
            }

        case .emptyBattery:
            if cycle(t, 1) < 0.5 {
                battery(p, x: 24, y: 24, outline: Palette.red, fillWidth: 0, fillColor: Palette.red)
                p.stroke("M31.5 25.5V29.5", Palette.red, width: 1.6)
            }

        case .batteryCheck:
            p.group(CGAffineTransform(translationX: 0, y: -2.5 * pulse(t, 2.6))) {
                battery(p, x: 23, y: 0, outline: Palette.ink, fillWidth: 8.5, fillColor: Palette.green)
                p.stroke("M34.6 4L35.8 5.2L37.6 3", Palette.green, width: 1.2)
            }

        case .sparkles:
            let stars: [(String, Double)] = [
                ("M54 8L55.5 12L59.5 13.5L55.5 15L54 19L52.5 15L48.5 13.5L52.5 12Z", 0),
                ("M9 12L10 14.5L12.5 15.5L10 16.5L9 19L8 16.5L5.5 15.5L8 14.5Z", 0.5),
                ("M60 30L60.8 32L62.8 32.8L60.8 33.6L60 35.6L59.2 33.6L57.2 32.8L59.2 32Z", 1.0),
            ]
            for (data, delay) in stars {
                let k = pulse(t, 1.6, phase: delay / 1.6)
                let bounds = SVGPath.path(data).boundingBox
                p.group(.scale(0.6 + 0.4 * k, 0.6 + 0.4 * k, around: bounds.midX, bounds.midY), alpha: 0.25 + 0.75 * k) {
                    p.shape(data, fill: Palette.juice, width: 1.1)
                }
            }

        case .steam:
            for (delay, data) in [
                (0.0, "M19 4A3 3 0 0 1 24 2A3 3 0 0 1 29 3A2.5 2.5 0 0 1 28 8H20A2.5 2.5 0 0 1 19 4Z"),
                (0.9, "M36 2A3 3 0 0 1 41 0A3 3 0 0 1 46 1A2.5 2.5 0 0 1 45 6H37A2.5 2.5 0 0 1 36 2Z"),
            ] {
                let c = cycle(t, 1.8, delay: delay)
                let bounds = SVGPath.path(data).boundingBox
                let scale = 0.7 + 0.4 * c
                let transform = CGAffineTransform(translationX: 0, y: 4 - 12 * c)
                p.group(transform, alpha: c < 0.3 ? c / 0.3 : 1 - (c - 0.3) / 0.7) {
                    p.group(.scale(scale, scale, around: bounds.midX, bounds.midY)) {
                        p.shape(data, fill: Palette.white, width: 1.3)
                    }
                }
            }
        }
    }
}

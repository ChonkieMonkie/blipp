import CoreGraphics
import Foundation

/// A small SVG path-data parser (M, L, H, V, C, Q, A, Z in both cases) so Blipp's
/// shapes can be written exactly as they were in the design.
enum SVGPath {
    private static var cache: [String: CGPath] = [:]
    private static let lock = NSLock()

    static func path(_ data: String) -> CGPath {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[data] { return cached }
        let parsed = parse(data)
        cache[data] = parsed
        return parsed
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ data: String) -> [Token] {
        let bytes = Array(data.utf8)
        var tokens: [Token] = []
        var index = 0

        func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
        func isLetter(_ byte: UInt8) -> Bool { (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) }

        while index < bytes.count {
            let byte = bytes[index]
            if isLetter(byte) {
                tokens.append(.command(Character(UnicodeScalar(byte))))
                index += 1
            } else if isDigit(byte) || byte == 45 || byte == 43 || byte == 46 {  // digit - + .
                var end = index
                if byte == 45 || byte == 43 { end += 1 }
                var seenDot = false
                while end < bytes.count {
                    let next = bytes[end]
                    if isDigit(next) {
                        end += 1
                    } else if next == 46 && !seenDot {
                        seenDot = true
                        end += 1
                    } else {
                        break
                    }
                }
                let text = String(decoding: bytes[index..<end], as: UTF8.self)
                tokens.append(.number(CGFloat(Double(text) ?? 0)))
                index = max(end, index + 1)
            } else {
                index += 1
            }
        }
        return tokens
    }

    private static func parse(_ data: String) -> CGPath {
        let tokens = tokenize(data)
        let path = CGMutablePath()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        func hasNumber() -> Bool {
            guard index < tokens.count, case .number = tokens[index] else { return false }
            return true
        }
        func number() -> CGFloat {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return 0 }
            index += 1
            return value
        }
        func point(relative: Bool) -> CGPoint {
            let x = number()
            let y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if case .command(let next) = tokens[index] {
                command = next
                index += 1
            } else if command == "Z" || command == "z" {
                index += 1  // stray number after a close: skip it
                continue
            }

            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                let target = point(relative: relative)
                path.move(to: target)
                current = target
                subpathStart = target
                command = relative ? "l" : "L"
            case "L":
                let target = point(relative: relative)
                path.addLine(to: target)
                current = target
            case "H":
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C":
                let control1 = point(relative: relative)
                let control2 = point(relative: relative)
                let target = point(relative: relative)
                path.addCurve(to: target, control1: control1, control2: control2)
                current = target
            case "Q":
                let control = point(relative: relative)
                let target = point(relative: relative)
                path.addQuadCurve(to: target, control: control)
                current = target
            case "A":
                let rx = number()
                let ry = number()
                let rotation = number()
                let largeArc = number() != 0
                let sweep = number() != 0
                let target = point(relative: relative)
                addArc(to: path, from: current, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep, end: target)
                current = target
            case "Z":
                path.closeSubpath()
                current = subpathStart
            default:
                // Unknown command: skip its numbers so parsing can carry on.
                while hasNumber() { index += 1 }
            }
        }
        return path
    }

    /// Converts an SVG elliptical arc (endpoint form) into cubic Béziers.
    private static func addArc(
        to path: CGMutablePath, from start: CGPoint, rx: CGFloat, ry: CGFloat,
        rotation: CGFloat, largeArc: Bool, sweep: Bool, end: CGPoint
    ) {
        guard start != end else { return }
        var rx = abs(rx)
        var ry = abs(ry)
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = max(0, rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1)
        let denominator = rx2 * y1 * y1 + ry2 * x1 * x1
        var coefficient = denominator == 0 ? 0 : sqrt(numerator / denominator)
        if largeArc == sweep { coefficient = -coefficient }

        let cx1 = coefficient * rx * y1 / ry
        let cy1 = coefficient * -ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var value = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }

        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 {
            delta -= 2 * .pi
        } else if sweep && delta < 0 {
            delta += 2 * .pi
        }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let handle = 4.0 / 3.0 * tan(step / 4)

        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi, y: cy + rx * x * sinPhi + ry * y * cosPhi)
        }

        var theta = theta1
        for _ in 0..<segments {
            let next = theta + step
            let control1 = map(cos(theta) - handle * sin(theta), sin(theta) + handle * cos(theta))
            let control2 = map(cos(next) + handle * sin(next), sin(next) - handle * cos(next))
            path.addCurve(to: map(cos(next), sin(next)), control1: control1, control2: control2)
            theta = next
        }
    }
}

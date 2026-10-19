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

import SwiftUI

/// A small area graph whose line color fades with the value it shows.
struct Sparkline: View {
    let points: [GraphPoint]
    let range: ClosedRange<Double>
    let scale: HeatScale
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else {
                if let only = points.first {
                    let y = yPosition(only.value, height: size.height)
                    var line = Path()
                    line.move(to: CGPoint(x: size.width - 2, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(scale.color(at: only.value)), lineWidth: lineWidth)
                }
                return
            }

            var line = Path()
            for (index, point) in points.enumerated() {
                let location = CGPoint(x: point.x * size.width, y: yPosition(point.value, height: size.height))
                if index == 0 { line.move(to: location) } else { line.addLine(to: location) }
            }
            var area = line
            area.addLine(to: CGPoint(x: (points.last?.x ?? 1) * size.width, y: size.height))
            area.addLine(to: CGPoint(x: (points.first?.x ?? 0) * size.width, y: size.height))
            area.closeSubpath()

            let gradient = scale.gradient(min: range.lowerBound, max: range.upperBound)
            let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
            var faded = context
            faded.opacity = 0.18
            faded.fill(area, with: shading)
            context.stroke(line, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private func yPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
        let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
        let inset = lineWidth
        return inset + (1 - fraction) * (height - inset * 2)
    }
}

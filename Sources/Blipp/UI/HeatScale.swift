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

/// Maps values to colors with smooth fades between stops. Used for graphs, bars and cores.
struct HeatScale {
    struct RGB {
        var r: Double, g: Double, b: Double

        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    }

    let stops: [(value: Double, color: RGB)]

    init(_ stops: [(Double, UInt32)]) {
        self.stops = stops.map { ($0.0, RGB($0.1)) }
    }

    func rgb(at value: Double) -> RGB {
        guard let first = stops.first, let last = stops.last else { return RGB(0x888888) }
        if value <= first.value { return first.color }
        if value >= last.value { return last.color }
        for (lower, upper) in zip(stops, stops.dropFirst()) where value <= upper.value {
            let t = (value - lower.value) / (upper.value - lower.value)
            return RGB(
                r: lower.color.r + (upper.color.r - lower.color.r) * t,
                g: lower.color.g + (upper.color.g - lower.color.g) * t,
                b: lower.color.b + (upper.color.b - lower.color.b) * t
            )
        }
        return last.color
    }

    func color(at value: Double) -> Color { rgb(at: value).color }

    /// A top-to-bottom gradient for a graph whose y axis runs from `max` (top) to `min` (bottom).
    func gradient(min: Double, max: Double, steps: Int = 12) -> Gradient {
        let stops = (0...steps).map { index -> Gradient.Stop in
            let location = Double(index) / Double(steps)
            let value = max - (max - min) * location
            return Gradient.Stop(color: color(at: value), location: location)
        }
        return Gradient(stops: stops)
    }

    static let green: UInt32 = 0x22A06B
    static let yellow: UInt32 = 0xEAB308
    static let orange: UInt32 = 0xF97316
    static let red: UInt32 = 0xE5484D
    static let blueLight: UInt32 = 0x7FB2F5
    static let blueMid: UInt32 = 0x3D7BF0
    static let blueDark: UInt32 = 0x3451C7

    static let cpu = HeatScale([(0, green), (50, yellow), (75, orange), (95, red)])
    static let temperature = HeatScale([(45, green), (62, yellow), (78, orange), (92, red)])
    static let memoryFraction = HeatScale([(0.5, green), (0.7, yellow), (0.85, orange), (0.97, red)])
    static let network = HeatScale([(0, blueLight), (3_000_000, blueMid), (20_000_000, blueDark)])
    static let disk = HeatScale([(0, blueLight), (50_000_000, blueMid), (300_000_000, blueDark)])
}

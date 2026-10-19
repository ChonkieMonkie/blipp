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

import Foundation

enum Format {
    static func bytes(_ value: Double) -> String {
        let gigabytes = value / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        return String(format: "%.0f MB", value / 1_048_576)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        scaled(bytesPerSecond, units: ["B/s", "KB/s", "MB/s", "GB/s"])
    }

    /// Network speed in the unit the user picked: "1.2 MB/s", or eight times that as "9.6 Mb/s".
    static func rate(_ bytesPerSecond: Double, in unit: NetworkUnit) -> String {
        switch unit {
        case .bytes: return rate(bytesPerSecond)
        case .bits: return scaled(bytesPerSecond * 8, units: ["b/s", "kb/s", "Mb/s", "Gb/s"])
        }
    }

    /// Picks the unit (×1000 per step) and the decimals, the same way for bytes and bits.
    private static func scaled(_ value: Double, units: [String]) -> String {
        switch value {
        case ..<1_000: return "\(Int(value.rounded())) \(units[0])"
        case ..<1_000_000: return String(format: "%.0f %@", value / 1_000, units[1])
        case ..<100_000_000: return String(format: "%.1f %@", value / 1_000_000, units[2])
        // Whole megas from 100 up, so "176 MB/s" fits a tile without being squeezed.
        case ..<1_000_000_000: return String(format: "%.0f %@", value / 1_000_000, units[2])
        default: return String(format: "%.2f %@", value / 1_000_000_000, units[3])
        }
    }

    static func diskSpace(_ bytes: Double) -> String {
        let gigabytes = bytes / 1_000_000_000
        if gigabytes >= 1000 { return String(format: "%.1f TB", gigabytes / 1000) }
        return String(format: "%.0f GB", gigabytes)
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Like `percent`, but a process that did run never reads as a flat "0%".
    static func processPercent(_ value: Double) -> String {
        value > 0 && value < 0.5 ? "<1%" : percent(value)
    }
}

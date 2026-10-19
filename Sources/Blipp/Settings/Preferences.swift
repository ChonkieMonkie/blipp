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

import Combine
import Foundation

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case blippOnly, cpuPercent, miniBars, batteryPercent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blippOnly: return "Blipp only"
        case .cpuPercent: return "Blipp + CPU %"
        case .miniBars: return "Blipp + mini bars"
        case .batteryPercent: return "Blipp + battery %"
        }
    }
}

enum IconStyle: String, CaseIterable, Identifiable {
    case color, monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return "Color"
        case .monochrome: return "Monochrome"
        }
    }
}

enum ClickAction: String, CaseIterable, Identifiable {
    case showPanel, openActivityMonitor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showPanel: return "Show the panel"
        case .openActivityMonitor: return "Open Activity Monitor"
        }
    }
}

/// How network speeds are written: bytes like Activity Monitor, or bits like internet plans.
enum NetworkUnit: String, CaseIterable, Identifiable {
    case bytes, bits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bytes: return "MB/s"
        case .bits: return "Mb/s"
        }
    }
}

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let graphIntervals: [Double] = [0.5, 1, 2, 5]
    static let graphSpans: [Double] = [30, 60, 300, 900, 3600]
    static let moodIntervals: [Double] = [1, 2, 5]

    private let defaults: UserDefaults

    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: Keys.menuBarDisplay) }
    }
    @Published var iconStyle: IconStyle {
        didSet { defaults.set(iconStyle.rawValue, forKey: Keys.iconStyle) }
    }
    @Published var animateMenuBar: Bool {
        didSet { defaults.set(animateMenuBar, forKey: Keys.animateMenuBar) }
    }
    @Published var randomizeVariants: Bool {
        didSet { defaults.set(randomizeVariants, forKey: Keys.randomizeVariants) }
    }
    @Published var graphInterval: Double {
        didSet { defaults.set(graphInterval, forKey: Keys.graphInterval) }
    }
    @Published var graphSpan: Double {
        didSet { defaults.set(graphSpan, forKey: Keys.graphSpan) }
    }
    @Published var moodInterval: Double {
        didSet { defaults.set(moodInterval, forKey: Keys.moodInterval) }
    }
    @Published var clickAction: ClickAction {
        didSet { defaults.set(clickAction.rawValue, forKey: Keys.clickAction) }
    }
    @Published var networkUnit: NetworkUnit {
        didSet { defaults.set(networkUnit.rawValue, forKey: Keys.networkUnit) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard {
            Self.migrateFromOldBundleID(into: defaults)
        }
        menuBarDisplay = MenuBarDisplay(rawValue: defaults.string(forKey: Keys.menuBarDisplay) ?? "") ?? .blippOnly
        iconStyle = IconStyle(rawValue: defaults.string(forKey: Keys.iconStyle) ?? "") ?? .color
        animateMenuBar = defaults.object(forKey: Keys.animateMenuBar) as? Bool ?? true
        randomizeVariants = defaults.object(forKey: Keys.randomizeVariants) as? Bool ?? true
        graphInterval = Self.pick(defaults.double(forKey: Keys.graphInterval), from: Self.graphIntervals, fallback: 1)
        graphSpan = Self.pick(defaults.double(forKey: Keys.graphSpan), from: Self.graphSpans, fallback: 60)
        moodInterval = Self.pick(defaults.double(forKey: Keys.moodInterval), from: Self.moodIntervals, fallback: 2)
        clickAction = ClickAction(rawValue: defaults.string(forKey: Keys.clickAction) ?? "") ?? .showPanel
        networkUnit = NetworkUnit(rawValue: defaults.string(forKey: Keys.networkUnit) ?? "") ?? .bytes
    }

    /// Blipp's first builds used the bundle ID `app.blipp.Blipp`; carry those settings over once.
    private static func migrateFromOldBundleID(into defaults: UserDefaults) {
        let marker = "migratedFromOldBundleID"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)
        guard let old = defaults.persistentDomain(forName: "app.blipp.Blipp") else { return }
        let keys = [
            Keys.menuBarDisplay, Keys.iconStyle, Keys.animateMenuBar, Keys.randomizeVariants,
            Keys.graphInterval, Keys.graphSpan, Keys.moodInterval, Keys.clickAction,
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
    }

    private static func pick(_ value: Double, from options: [Double], fallback: Double) -> Double {
        options.contains(value) ? value : fallback
    }

    static func spanTitle(_ seconds: Double, short: Bool = true) -> String {
        switch seconds {
        case ..<60: return short ? "\(Int(seconds)) s" : "\(Int(seconds)) seconds"
        case ..<3600:
            let minutes = Int(seconds / 60)
            return short ? "\(minutes) min" : (minutes == 1 ? "minute" : "\(minutes) minutes")
        default:
            let hours = Int(seconds / 3600)
            return short ? "\(hours) h" : (hours == 1 ? "hour" : "\(hours) hours")
        }
    }

    static func intervalTitle(_ seconds: Double) -> String {
        if seconds < 1 { return "0.5 seconds" }
        return seconds == 1 ? "1 second" : "\(Int(seconds)) seconds"
    }

    private enum Keys {
        static let menuBarDisplay = "menuBarDisplay"
        static let iconStyle = "iconStyle"
        static let animateMenuBar = "animateMenuBar"
        static let randomizeVariants = "randomizeVariants"
        static let graphInterval = "graphInterval"
        static let graphSpan = "graphSpan"
        static let moodInterval = "moodInterval"
        static let clickAction = "clickAction"
        static let networkUnit = "networkUnit"
    }
}

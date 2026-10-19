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

struct Mood: Equatable {
    var scene: BlippScene
    var title: String
    var subtitle: String
    /// True when the subtitle is the plain CPU line ("CPU at 8%" or "Safari is using 40% CPU"),
    /// which can be refreshed with new numbers whatever the headline says.
    var subtitleIsCPULine = false

    static let initial = Mood(scene: BlippScene(), title: "Hi, I'm Blipp!", subtitle: "Taking a first look at your Mac…")
}

/// Turns raw numbers into Blipp's look and a line of text.
///
/// Every metric owns one part of Blipp: color = heat, face = CPU, hands = battery,
/// network and disk, above the head = memory. Emergencies take over the whole figure.
final class MoodEngine {
    enum CPULevel: Int, Comparable {
        case sleeping, chilling, working, sweating, burning

        init(percent: Double) {
            switch percent {
            case ..<10: self = .sleeping
            case ..<35: self = .chilling
            case ..<65: self = .working
            case ..<90: self = .sweating
            default: self = .burning
            }
        }

        static func < (lhs: CPULevel, rhs: CPULevel) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum BatteryMood { case none, charging, full, atLimit, low, critical }
    enum MemoryMood { case plenty, juggling, dropping, swapping }

    var randomize = true

    private var chargeVariant = 0
    private var chillVariant = 0
    private var wasCharging = false
    private var wasChilling = false

    func mood(for s: Snapshot, smoothedCPU: Double) -> Mood {
        let level = CPULevel(percent: smoothedCPU)
        let battery = batteryMood(s.battery)
        let memory = memoryMood(s.memory)
        let downloading = s.networkDown > 1_000_000
        let uploading = s.networkUp > 500_000
        let diskBusy = s.diskIO > 50_000_000
        let diskFull = s.diskTotal > 0 && s.diskFreeFraction < 0.10

        // Pick fresh variants each time a state starts, so Blipp doesn't get repetitive.
        if battery == .charging && !wasCharging {
            chargeVariant = randomize ? Int.random(in: 0...1) : 0
        }
        wasCharging = battery == .charging
        if level == .chilling && !wasChilling {
            chillVariant = randomize ? Int.random(in: 0...1) : 0
        }
        wasChilling = level == .chilling

        let top = s.topProcesses.first
        let defaultSubtitle: String = {
            if let top, top.cpu >= 20 {
                return "\(top.name) is using \(Int(top.cpu.rounded()))% CPU"
            }
            return "CPU at \(Int(s.cpuTotal.rounded()))%"
        }()

        // MARK: Emergencies
        if battery == .critical {
            var scene = BlippScene(shape: .puddle, color: Palette.melted, face: .dead, overhead: .emptyBattery)
            scene.bobPeriod = 3
            return Mood(scene: scene, title: "Melting… I need power!", subtitle: "Battery at \(s.battery?.percent ?? 0)%. Plug in soon.")
        }
        if s.thermal == .critical {
            let scene = BlippScene(color: Palette.boiling, face: .boiling, hands: .thermometer, overhead: .steam, shake: true)
            return Mood(scene: scene, title: "Boiling! Slowing down to cool off", subtitle: "Thermal state is critical. Give your Mac a break.")
        }
        if memory == .swapping {
            var scene = BlippScene(face: .determined, hands: .packBox)
            scene.bobPeriod = 0.9
            return Mood(scene: scene, title: "Packing memory onto the SSD", subtitle: "Swap in use: \(Format.bytes(s.memory.swapUsed))")
        }

        // MARK: Layers
        var scene = BlippScene()

        // Color = heat (CPU or temperature, whichever is hotter).
        let cpuHeat: [Double] = [0, 1, 2, 3, 4]
        var heat = cpuHeat[level.rawValue]
        switch s.thermal {
        case .fair: heat = max(heat, 2.5)
        case .serious: heat = max(heat, 3.5)
        default: break
        }
        scene.color = color(forHeat: heat)

        // Face = CPU.
        switch level {
        case .sleeping:
            scene.face = .sleeping
            scene.shape = .squished
            scene.overhead = .zzz
            scene.bobPeriod = 3.6
        case .chilling:
            scene.face = chillVariant == 0 ? .sunglasses : .smile
            scene.bobPeriod = 2.4
        case .working:
            scene.face = .focused
            scene.overhead = .gear
            scene.bobPeriod = 1.4
        case .sweating:
            scene.face = .sweaty
            scene.sweat = true
            scene.bobPeriod = 0.8
        case .burning:
            scene.face = .panic
            scene.sweat = true
            scene.shake = true
            scene.overhead = .flame
        }
        let relaxed = level <= .chilling
        var faceLocked = false
        func overrideFace(_ face: BlippScene.Face, when allowed: Bool) {
            guard allowed, !faceLocked else { return }
            scene.face = face
            faceLocked = true
        }

        // Above the head = memory.
        if level != .burning {
            switch memory {
            case .dropping:
                scene.overhead = .juggle5
                scene.dizzy = true
                overrideFace(.dizzy, when: true)
            case .juggling:
                scene.overhead = .juggle3
            default: break
            }
        }

        // Battery.
        switch battery {
        case .low:
            overrideFace(.tired, when: level != .burning)
            if heat < 3 { scene.color = Palette.tired }
            if scene.overhead == .none || scene.overhead == .gear { scene.overhead = .lowBattery }
            scene.bobPeriod = 4
        case .charging:
            scene.hands = chargeVariant == 0 ? .juice : .cookie
            overrideFace(chargeVariant == 0 ? .happyClosed : .chewing, when: relaxed)
        case .full:
            if relaxed && scene.shape == .normal { scene.shape = .round }
            overrideFace(.content, when: relaxed)
            if scene.overhead == .none { scene.overhead = .sparkles }
            scene.bobPeriod = 4
        case .atLimit:
            scene.hands = .juiceAside
            overrideFace(.pleased, when: relaxed)
            if scene.overhead == .none { scene.overhead = .batteryCheck }
        default: break
        }

        // Temperature.
        switch s.thermal {
        case .serious:
            if scene.hands == .none { scene.hands = .iceCream }
            overrideFace(.licking, when: level <= .working)
            scene.sweat = true
        case .fair:
            if scene.hands == .none { scene.hands = .fan }
            overrideFace(.relieved, when: relaxed)
        default: break
        }

        if memory == .juggling {
            overrideFace(.lookingUp, when: level <= .working)
        }

        // Network.
        if !s.online {
            if scene.overhead == .none { scene.overhead = .cloudOffline }
            if heat < 2 && battery != .low { scene.color = Palette.offline }
            overrideFace(.sad, when: relaxed)
            if relaxed { scene.tear = true }
        } else if downloading, scene.hands == .none, scene.overhead == .none || scene.overhead == .zzz || scene.overhead == .gear {
            scene.hands = .catchBox
            scene.overhead = .none
            overrideFace(.excited, when: relaxed)
        } else if uploading, scene.hands == .none {
            scene.hands = .plane
            overrideFace(.wink, when: relaxed)
        }

        // Disk.
        if diskFull {
            if scene.shape == .normal { scene.shape = .wide }
            overrideFace(.surprised, when: relaxed)
        }
        if diskBusy, scene.hands == .none {
            scene.hands = .papers
        }

        // MARK: Text, most important first
        let charging = s.battery.map { battery -> String in
            var parts: [String] = []
            if let watts = battery.watts, watts > 0.5 { parts.append("Charging at \(Int(watts.rounded())) W") } else { parts.append("Charging") }
            if let minutes = battery.minutesToFull { parts.append("full in \(Format.duration(minutes: minutes))") }
            return parts.joined(separator: " · ")
        } ?? "Charging"

        let text: (String, String)
        if level == .burning {
            text = ("I'm on fire!", defaultSubtitle)
        } else if level == .sweating {
            text = ("Breaking a sweat!", defaultSubtitle)
        } else if battery == .low {
            text = ("Getting sleepy…", "Battery at \(s.battery?.percent ?? 0)%. Plug me in?")
        } else if memory == .dropping {
            text = ("Too much! Dropping balls", "Memory pressure is high")
        } else if battery == .charging {
            text = (chargeVariant == 0 ? "Mmm, juice!" : "Nom nom, charging", charging)
        } else if battery == .full {
            text = ("Stuffed! You can unplug me", "Battery is fully charged")
        } else if battery == .atLimit {
            text = ("No thanks, I'm full", "Charge limit reached at \(s.battery?.percent ?? 0)%")
        } else if s.thermal == .serious {
            text = ("It's hot in here", "Your Mac may slow down to cool off")
        } else if s.thermal == .fair {
            text = ("Getting warm", s.temperature.map { "Chip at \(Int($0.rounded())) °C" } ?? "Thermal state is fair")
        } else if memory == .juggling {
            text = ("Juggling lots of apps", "Memory pressure is medium")
        } else if !s.online {
            text = ("No internet", "Blipp can't find a network")
        } else if level == .working {
            text = ("Working on it", defaultSubtitle)
        } else if scene.hands == .catchBox {
            text = ("Catching packages", "Downloading at \(Format.rate(s.networkDown))")
        } else if scene.hands == .plane {
            text = ("Sending paper planes", "Uploading at \(Format.rate(s.networkUp))")
        } else if diskFull {
            text = ("My cheeks are stuffed!", "Only \(Int((s.diskFreeFraction * 100).rounded()))% disk space left")
        } else if scene.hands == .papers {
            text = ("Shuffling files", "Disk at \(Format.rate(s.diskIO))")
        } else if level == .sleeping {
            text = ("Zzz… all quiet", defaultSubtitle)
        } else {
            text = ("Just chilling", defaultSubtitle)
        }

        return Mood(scene: scene, title: text.0, subtitle: text.1, subtitleIsCPULine: text.1 == defaultSubtitle)
    }

    private func batteryMood(_ battery: BatteryInfo?) -> BatteryMood {
        guard let battery else { return .none }
        if battery.onAC {
            if battery.isCharging { return .charging }
            // Plugged in but not charging below 100 % means a charge limit (or optimized charging) is holding it.
            return battery.percent >= 99 ? .full : .atLimit
        }
        if battery.percent < 5 { return .critical }
        if battery.percent < 20 { return .low }
        return .none
    }

    private func memoryMood(_ memory: MemoryInfo) -> MemoryMood {
        switch memory.pressure {
        case .critical: return memory.swapUsed > 2 * 1_073_741_824 ? .swapping : .dropping
        case .warning: return .juggling
        case .normal: return .plenty
        }
    }

    private func color(forHeat heat: Double) -> UInt32 {
        switch heat {
        case ..<0.5: return Palette.sleepy
        case ..<1.5: return Palette.mint
        case ..<2.25: return Palette.lime
        case ..<2.75: return Palette.warm
        case ..<3.25: return Palette.yellow
        case ..<3.75: return Palette.orange
        default: return Palette.hot
        }
    }
}

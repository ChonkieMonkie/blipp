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
    /// What the headline is about. The subtitle's live numbers may refresh every sample, but only
    /// while the situation (and so the headline) stays the same.
    var situation: MoodEngine.Situation = .greeting
    /// What he says in the menu bar. Chosen together with the rest of the mood, so the bubble
    /// changes at the same moment as Blipp himself.
    var bubble: MenuBubble?

    static let initial = Mood(scene: BlippScene(), title: "Hi, I'm Blipp!", subtitle: "Taking a first look at your Mac…")
}

/// What Blipp says in the menu bar's speech bubble: one thing at a time, the most important first.
struct MenuBubble: Equatable {
    enum Kind: Hashable {
        case empty, heat, low, offline, swap, memory, charging, download, upload, disk
    }

    var kind: Kind
    var value: String
    /// Emergencies get a red bubble and show even when the bubble is turned off.
    var emergency = false
}

/// Turns raw numbers into Blipp's look and a line of text.
///
/// One signal, one place: face = CPU, color and sweat = temperature, above the head = memory,
/// left hand = network, right hand = disk, sticker = battery. Two emergencies (an empty battery
/// and critical heat) change the whole figure.
final class MoodEngine {
    enum CPULevel: Int, Comparable {
        case sleeping, chilling, busy, straining, maxed

        init(percent: Double) {
            switch percent {
            case ..<10: self = .sleeping
            case ..<35: self = .chilling
            case ..<65: self = .busy
            case ..<90: self = .straining
            default: self = .maxed
            }
        }

        static func < (lhs: CPULevel, rhs: CPULevel) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Temperature: Int, Comparable {
        case chilly, cool, warm, hot, veryHot, critical

        init(celsius: Double?, thermal: ProcessInfo.ThermalState) {
            var level: Temperature
            switch celsius ?? 50 {
            case ..<40: level = .chilly
            case ..<60: level = .cool
            case ..<75: level = .warm
            case ..<90: level = .hot
            default: level = .veryHot
            }
            switch thermal {
            case .fair: level = max(level, .warm)
            case .serious: level = max(level, .veryHot)
            case .critical: level = .critical
            default: break
            }
            self = level
        }

        static func < (lhs: Temperature, rhs: Temperature) -> Bool { lhs.rawValue < rhs.rawValue }

        var color: UInt32 {
            switch self {
            case .chilly: return Palette.chilly
            case .cool: return Palette.mint
            case .warm: return Palette.warm
            case .hot: return Palette.orange
            case .veryHot: return Palette.hot
            case .critical: return Palette.boiling
            }
        }
    }

    enum MemoryLevel { case plenty, busy, high, swapping }
    enum BatteryLevel { case none, charging, full, atLimit, low, empty }

    /// Everything Blipp can talk about, most important first.
    enum Situation: Int, Comparable {
        case batteryEmpty, criticalHeat, batteryLow, offline, swapping, memoryHigh, cpuMaxed, veryHot
        case diskFull, cpuStraining, hot, memoryBusy, downloading, uploading, writing, reading
        case charging, full, atLimit, cpuBusy, warm, chilling, sleeping, greeting

        static func < (lhs: Situation, rhs: Situation) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var randomize = true
    var networkUnit = NetworkUnit.bytes
    /// Bubbles the user turned off, usually because macOS already shows the same thing.
    var hiddenBubbles: Set<MenuBubble.Kind> = []

    private var chargeVariant = 0
    private var chillVariant = 0
    private var wasCharging = false
    private var wasChilling = false
    private var situation: Situation?
    private var titleIndex = 0
    private var isDownloading = false
    private var isUploading = false
    private var isReading = false
    private var isWriting = false

    /// Traffic starts counting above its threshold and stops only below half of it, so a
    /// transfer hovering around the line doesn't make Blipp and his bubble flicker.
    private static func busy(_ value: Double, threshold: Double, was: Bool) -> Bool {
        value > (was ? threshold / 2 : threshold)
    }

    /// A new headline and new prop variants next time, as when the panel opens.
    func reshuffle() {
        situation = nil
        if randomize {
            chargeVariant = Int.random(in: 0...1)
            chillVariant = Int.random(in: 0...1)
        }
    }

    // MARK: Levels

    static func memoryLevel(_ memory: MemoryInfo) -> MemoryLevel {
        switch memory.pressure {
        case .critical: return memory.swapUsed > 2 * 1_073_741_824 ? .swapping : .high
        case .warning: return .busy
        case .normal: return .plenty
        }
    }

    static func batteryLevel(_ battery: BatteryInfo?) -> BatteryLevel {
        guard let battery else { return .none }
        if battery.onAC {
            if battery.isCharging { return .charging }
            // Plugged in but not charging below 100 % means a charge limit (or optimized charging) is holding it.
            return battery.percent >= 99 ? .full : .atLimit
        }
        if battery.percent < 5 { return .empty }
        if battery.percent < 20 { return .low }
        return .none
    }

    static let downloadThreshold: Double = 1_000_000
    static let uploadThreshold: Double = 500_000
    static let diskThreshold: Double = 20_000_000

    // MARK: Scene and text

    func mood(for s: Snapshot, smoothedCPU: Double) -> Mood {
        let cpu = CPULevel(percent: smoothedCPU)
        let temperature = Temperature(celsius: s.temperature, thermal: s.thermal)
        let memory = Self.memoryLevel(s.memory)
        let battery = Self.batteryLevel(s.battery)
        isDownloading = Self.busy(s.networkDown, threshold: Self.downloadThreshold, was: isDownloading)
        isUploading = Self.busy(s.networkUp, threshold: Self.uploadThreshold, was: isUploading)
        isReading = Self.busy(s.diskRead, threshold: Self.diskThreshold, was: isReading)
        isWriting = Self.busy(s.diskWrite, threshold: Self.diskThreshold, was: isWriting)
        let downloading = isDownloading, uploading = isUploading, reading = isReading, writing = isWriting

        // Fresh variants each time a state starts, so Blipp doesn't get repetitive.
        if battery == .charging && !wasCharging && randomize { chargeVariant = Int.random(in: 0...1) }
        wasCharging = battery == .charging
        if cpu == .chilling && !wasChilling && randomize { chillVariant = Int.random(in: 0...1) }
        wasChilling = cpu == .chilling

        let scene = makeScene(cpu: cpu, temperature: temperature, memory: memory, battery: battery,
                              online: s.online, downloading: downloading, uploading: uploading,
                              reading: reading, writing: writing)

        let facts = Facts(snapshot: s, cpu: cpu, temperature: temperature, memory: memory, battery: battery,
                          downloading: downloading, uploading: uploading, reading: reading, writing: writing,
                          unit: networkUnit)
        let current = facts.situations.first ?? .chilling
        if current != situation {
            situation = current
            let count = Self.titles(for: current, chargeVariant: chargeVariant).count
            titleIndex = randomize ? Int.random(in: 0..<max(1, count)) : 0
        }
        let titles = Self.titles(for: current, chargeVariant: chargeVariant)
        let title = titles[titleIndex % titles.count]
        return Mood(scene: scene, title: title, subtitle: facts.subtitle(for: current), situation: current,
                    bubble: Self.bubble(for: s, unit: networkUnit, downloading: downloading, uploading: uploading,
                                        diskBusy: reading || writing, hiding: hiddenBubbles))
    }

    private func makeScene(cpu: CPULevel, temperature: Temperature, memory: MemoryLevel, battery: BatteryLevel,
                           online: Bool, downloading: Bool, uploading: Bool, reading: Bool, writing: Bool) -> BlippScene {
        var scene = BlippScene()

        // Emergencies take over the whole figure.
        if battery == .empty {
            scene.shape = .puddle
            scene.color = Palette.melted
            scene.face = .dead
            scene.sticker = .low
            scene.bobPeriod = 3
            return scene
        }
        if temperature == .critical {
            scene.color = Palette.boiling
            scene.face = .boiling
            scene.heat = .fire
            scene.shake = true
            return scene
        }

        // Face and energy: CPU.
        switch cpu {
        case .sleeping:
            scene.face = .sleeping
            scene.bobPeriod = 3.6
        case .chilling:
            scene.face = chillVariant == 0 ? .smile : .sunglasses
            scene.bobPeriod = 2.4
        case .busy:
            scene.face = .focused
            scene.work = .light
            scene.bobPeriod = 1.4
        case .straining:
            scene.face = .sweaty
            scene.work = .strong
            scene.bobPeriod = 0.8
        case .maxed:
            scene.face = .panic
            scene.work = .strong
            scene.shake = true
            scene.bobPeriod = 0.6
        }

        // Color and sweat: temperature.
        scene.color = temperature.color
        switch temperature {
        case .hot: scene.heat = .sweat
        case .veryHot: scene.heat = .steam
        default: break
        }

        // Above the head: memory, or CPU's Zzz and gear when memory leaves the spot free.
        switch memory {
        case .busy: scene.head = .juggle3
        case .high: scene.head = .juggle5
        case .swapping: scene.head = .swapBox
        case .plenty:
            if cpu == .sleeping { scene.head = .zzz }
            if cpu == .busy { scene.head = .gear }
        }

        // Left hand: network.
        if !online {
            scene.network = .offline
        } else if downloading && uploading {
            scene.network = .both
        } else if downloading {
            scene.network = .download
        } else if uploading {
            scene.network = .upload
        }

        // Right hand: disk.
        if reading && writing {
            scene.disk = .both
        } else if reading {
            scene.disk = .read
        } else if writing {
            scene.disk = .write
        }

        // Sticker: battery.
        switch battery {
        case .charging: scene.sticker = chargeVariant == 0 ? .juice : .cookie
        case .full, .atLimit: scene.sticker = .limit
        case .low: scene.sticker = .low
        default: break
        }
        return scene
    }

    // MARK: Menu bar bubble

    /// The one thing worth saying in the menu bar right now, if any. A hidden kind steps aside
    /// for the next most important one. It's picked with the rest of the mood, so the bubble
    /// changes at the same moment as Blipp himself.
    static func bubble(for s: Snapshot, unit: NetworkUnit, downloading: Bool, uploading: Bool, diskBusy: Bool,
                       hiding hidden: Set<MenuBubble.Kind> = []) -> MenuBubble? {
        let battery = batteryLevel(s.battery)
        let percent = s.battery.map { "\($0.percent)%" } ?? ""
        var candidates: [MenuBubble] = []
        if battery == .empty { candidates.append(MenuBubble(kind: .empty, value: percent, emergency: true)) }
        if s.thermal == .critical {
            candidates.append(MenuBubble(kind: .heat, value: s.temperature.map { "\(Int($0.rounded())) °C" } ?? "Hot", emergency: true))
        }
        if battery == .low { candidates.append(MenuBubble(kind: .low, value: percent)) }
        if !s.online { candidates.append(MenuBubble(kind: .offline, value: "Offline")) }
        switch memoryLevel(s.memory) {
        case .swapping: candidates.append(MenuBubble(kind: .swap, value: Format.bytes(s.memory.swapUsed)))
        case .high: candidates.append(MenuBubble(kind: .memory, value: Format.percent(s.memory.usedFraction * 100)))
        default: break
        }
        if battery == .charging { candidates.append(MenuBubble(kind: .charging, value: percent)) }
        if downloading { candidates.append(MenuBubble(kind: .download, value: Format.rate(s.networkDown, in: unit))) }
        if uploading { candidates.append(MenuBubble(kind: .upload, value: Format.rate(s.networkUp, in: unit))) }
        if diskBusy { candidates.append(MenuBubble(kind: .disk, value: Format.rate(s.diskIO))) }
        return candidates.first { !hidden.contains($0.kind) }
    }

    // MARK: Headlines

    static func titles(for situation: Situation, chargeVariant: Int) -> [String] {
        switch situation {
        case .batteryEmpty: return ["Melting… I need power!", "Running on fumes!", "Feed me electrons!", "Going, going…"]
        case .criticalHeat: return ["Boiling! Slowing down to cool off", "Too hot to handle!", "I'm a hot potato!", "Somebody call the fan!"]
        case .batteryLow: return ["Getting sleepy…", "Running low, plug me in?", "My battery is grumbling", "Snack time soon?", "Low on juice"]
        case .offline: return ["Where did the internet go?", "Hello? Anyone out there?", "No signal, no fun", "Lost in the void", "The tubes are empty"]
        case .swapping: return ["Packing memory onto the SSD", "Moving boxes to the basement", "Memory's overflowing!", "Out of shelf space"]
        case .memoryHigh: return ["Too much! Dropping balls", "Juggling way too much", "My hands are full!", "Whoops, butterfingers"]
        case .cpuMaxed: return ["I'm on fire!", "Full throttle!", "Giving it everything!", "Engines at maximum!", "Hold on tight!"]
        case .veryHot: return ["It's hot in here", "Somebody open a window!", "Toasty, very toasty", "I could fry an egg"]
        case .diskFull: return ["My cheeks are stuffed!", "No room left!", "Time for a cleanup?", "Bursting at the seams"]
        case .cpuStraining: return ["Breaking a sweat!", "Working hard here!", "Pushing through!", "Heavy lifting!", "Phew, this is a big one"]
        case .hot: return ["Feeling the heat", "Things are heating up", "Phew, it's warm", "Sweating a little"]
        case .memoryBusy: return ["Juggling lots of apps", "Keeping the balls in the air", "Multitasking like a pro", "So many tabs!"]
        case .downloading: return ["Catching packages", "Incoming!", "Special delivery!", "Downloading goodies", "Grabbing the bits"]
        case .uploading: return ["Sending paper planes", "Off it goes!", "Air mail!", "Uploading with style", "Wheee, up and away"]
        case .writing: return ["Scribbling away", "Taking notes", "Writing it all down", "Filing paperwork"]
        case .reading: return ["Reading up", "Flipping through files", "Doing my homework", "Bookworm mode"]
        case .charging:
            return chargeVariant == 0
                ? ["Mmm, juice!", "Sipping some power", "Refueling", "Slurp slurp"]
                : ["Nom nom, charging", "Cookie break!", "Munching on watts", "Crunchy electrons"]
        case .full: return ["Stuffed! You can unplug me", "All charged up!", "Full tank!", "Ready for anything"]
        case .atLimit: return ["No thanks, I'm full", "Saving room for later", "Just the right amount", "Taking it easy on the battery"]
        case .cpuBusy: return ["Working on it", "In the zone", "Busy bee", "Crunching numbers", "On it!"]
        case .warm: return ["Nice and toasty", "Warm and cozy", "Sunbathing a little"]
        case .chilling: return ["Just chilling", "All good here", "Taking it easy", "Smooth sailing", "Living the good life", "Cool as a cucumber"]
        case .sleeping: return ["Zzz… all quiet", "Napping", "Dreaming of electric sheep", "Shh, resting", "Quiet as a mouse", "Five more minutes…"]
        case .greeting: return ["Hi, I'm Blipp!"]
        }
    }
}

/// The numbers behind each situation, so a headline always comes with the value that matters,
/// plus the next most important thing from a different part of the Mac.
private struct Facts {
    let snapshot: Snapshot
    let cpu: MoodEngine.CPULevel
    let temperature: MoodEngine.Temperature
    let memory: MoodEngine.MemoryLevel
    let battery: MoodEngine.BatteryLevel
    let downloading: Bool
    let uploading: Bool
    let reading: Bool
    let writing: Bool
    let unit: NetworkUnit

    private enum Topic { case battery, heat, memory, cpu, network, disk }

    /// Everything that applies right now, most important first.
    var situations: [MoodEngine.Situation] {
        var list: [MoodEngine.Situation] = []
        if battery == .empty { list.append(.batteryEmpty) }
        if temperature == .critical { list.append(.criticalHeat) }
        if battery == .low { list.append(.batteryLow) }
        if !snapshot.online { list.append(.offline) }
        if memory == .swapping { list.append(.swapping) }
        if memory == .high { list.append(.memoryHigh) }
        if cpu == .maxed { list.append(.cpuMaxed) }
        if temperature == .veryHot { list.append(.veryHot) }
        if snapshot.diskTotal > 0 && snapshot.diskFreeFraction < 0.10 { list.append(.diskFull) }
        if cpu == .straining { list.append(.cpuStraining) }
        if temperature == .hot { list.append(.hot) }
        if memory == .busy { list.append(.memoryBusy) }
        if downloading { list.append(.downloading) }
        if uploading { list.append(.uploading) }
        if writing { list.append(.writing) }
        if reading { list.append(.reading) }
        if battery == .charging { list.append(.charging) }
        if battery == .full { list.append(.full) }
        if battery == .atLimit { list.append(.atLimit) }
        if cpu == .busy { list.append(.cpuBusy) }
        if temperature == .warm { list.append(.warm) }
        list.append(cpu == .sleeping ? .sleeping : .chilling)
        return list
    }

    func subtitle(for situation: MoodEngine.Situation) -> String {
        let main = text(for: situation)
        // Add the most important thing from another topic, when it's worth mentioning and fits.
        let topic = Self.topic(of: situation)
        let extra = situations.first { other in
            other != situation && Self.topic(of: other) != topic && Self.isWorthAdding(other)
        }
        guard let extra else { return main }
        let combined = main + " · " + text(for: extra, short: true)
        return combined.count <= 46 ? combined : main
    }

    private static func topic(of situation: MoodEngine.Situation) -> Topic {
        switch situation {
        case .batteryEmpty, .batteryLow, .charging, .full, .atLimit: return .battery
        case .criticalHeat, .veryHot, .hot, .warm: return .heat
        case .swapping, .memoryHigh, .memoryBusy: return .memory
        case .cpuMaxed, .cpuStraining, .cpuBusy, .chilling, .sleeping, .greeting: return .cpu
        case .offline, .downloading, .uploading: return .network
        case .diskFull, .writing, .reading: return .disk
        }
    }

    /// Calm states never ride along in someone else's subtitle.
    private static func isWorthAdding(_ situation: MoodEngine.Situation) -> Bool {
        switch situation {
        case .chilling, .sleeping, .greeting, .warm, .full, .atLimit, .cpuBusy: return false
        default: return true
        }
    }

    private func text(for situation: MoodEngine.Situation, short: Bool = false) -> String {
        let s = snapshot
        let percent = s.battery?.percent ?? 0
        let chip = s.temperature.map { "\(Int($0.rounded())) °C" }
        switch situation {
        case .batteryEmpty:
            return short ? "battery \(percent)%" : "Battery at \(percent)%. Plug in now!"
        case .criticalHeat:
            return short ? "chip \(chip ?? "critical")" : "Chip at \(chip ?? "a critical heat"), macOS is slowing down"
        case .batteryLow:
            if short { return "battery \(percent)%" }
            if let minutes = s.battery?.minutesToEmpty { return "Battery at \(percent)% · \(Format.duration(minutes: minutes)) left" }
            return "Battery at \(percent)%. Plug me in?"
        case .offline:
            return short ? "offline" : "No network connection"
        case .swapping:
            return short ? "\(Format.bytes(s.memory.swapUsed)) swap" : "\(Format.bytes(s.memory.swapUsed)) moved to the SSD"
        case .memoryHigh:
            return short ? "memory \(Format.percent(s.memory.usedFraction * 100))" : "Memory pressure is high · \(Format.percent(s.memory.usedFraction * 100)) used"
        case .memoryBusy:
            return short ? "memory busy" : "Memory pressure is medium · \(Format.percent(s.memory.usedFraction * 100)) used"
        case .cpuMaxed, .cpuStraining, .cpuBusy, .chilling, .sleeping, .greeting:
            if short { return "CPU \(Int(s.cpuTotal.rounded()))%" }
            if let top = s.topProcesses.first, top.cpu >= 20, situation != .sleeping {
                return "\(top.name) is using \(Int(top.cpu.rounded()))% CPU"
            }
            return "CPU at \(Int(s.cpuTotal.rounded()))%"
        case .veryHot, .hot, .warm:
            if let chip { return short ? "chip \(chip)" : "Chip at \(chip)" }
            return short ? "running hot" : "Thermal state is \(s.thermal.title.lowercased())"
        case .diskFull:
            let left = Int((s.diskFreeFraction * 100).rounded())
            return short ? "disk \(left)% free" : "Only \(left)% disk space left"
        case .downloading:
            return short ? "↓ \(Format.rate(s.networkDown, in: unit))" : "Downloading at \(Format.rate(s.networkDown, in: unit))"
        case .uploading:
            return short ? "↑ \(Format.rate(s.networkUp, in: unit))" : "Uploading at \(Format.rate(s.networkUp, in: unit))"
        case .writing:
            return short ? "writing \(Format.rate(s.diskWrite))" : "Writing \(Format.rate(s.diskWrite)) to disk"
        case .reading:
            return short ? "reading \(Format.rate(s.diskRead))" : "Reading \(Format.rate(s.diskRead)) from disk"
        case .charging:
            if short { return "charging" }
            var parts: [String] = []
            if let watts = s.battery?.watts, watts > 0.5 { parts.append("Charging at \(Int(watts.rounded())) W") } else { parts.append("Charging, \(percent)%") }
            if let minutes = s.battery?.minutesToFull { parts.append("full in \(Format.duration(minutes: minutes))") }
            return parts.joined(separator: " · ")
        case .full:
            return "Battery is fully charged"
        case .atLimit:
            return "Charge limit reached at \(percent)%"
        }
    }
}

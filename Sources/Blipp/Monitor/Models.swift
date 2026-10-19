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

struct MemoryInfo: Equatable {
    enum Pressure: Int {
        case normal = 1, warning = 2, critical = 4

        var title: String {
            switch self {
            case .normal: return "low"
            case .warning: return "medium"
            case .critical: return "high"
            }
        }
    }

    var total: Double = 0       // bytes
    var app: Double = 0
    var wired: Double = 0
    var compressed: Double = 0
    var cached: Double = 0
    var swapUsed: Double = 0
    var pressure: Pressure = .normal

    var used: Double { app + wired + compressed }
    var free: Double { max(0, total - used - cached) }
    var usedFraction: Double { total > 0 ? used / total : 0 }
}

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
    var isCharged: Bool
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    /// Power flowing into (positive) or out of (negative) the battery.
    var watts: Double?
    var adapterWatts: Int?
}

struct ProcessUsage: Equatable, Identifiable {
    var pid: Int32
    var name: String
    var cpu: Double   // percent of one core, like Activity Monitor

    var id: Int32 { pid }
}

struct CoreLayout: Equatable {
    var performance: Int
    var efficiency: Int

    static let current: CoreLayout = {
        func int(_ name: String) -> Int {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
        }
        return CoreLayout(performance: int("hw.perflevel0.logicalcpu"), efficiency: int("hw.perflevel1.logicalcpu"))
    }()
}

struct Snapshot: Equatable {
    var cpuTotal: Double = 0          // 0–100, whole machine
    var cpuCores: [Double] = []       // 0–100 per core
    var memory = MemoryInfo()
    var battery: BatteryInfo?
    var temperature: Double?          // °C
    var thermal: ProcessInfo.ThermalState = .nominal
    var networkDown: Double = 0       // bytes per second
    var networkUp: Double = 0
    var online = true
    var diskRead: Double = 0          // bytes per second
    var diskWrite: Double = 0
    var diskFree: Double = 0          // bytes
    var diskTotal: Double = 0
    var topProcesses: [ProcessUsage] = []

    var diskIO: Double { diskRead + diskWrite }
    var diskFreeFraction: Double { diskTotal > 0 ? diskFree / diskTotal : 1 }
}

struct GraphPoint: Equatable {
    var x: Double   // 0 = start of span, 1 = now
    var value: Double
}

struct Graphs: Equatable {
    var temperature: [GraphPoint] = []
    var networkDown: [GraphPoint] = []
    var diskIO: [GraphPoint] = []
    var memoryUsed: [GraphPoint] = []
}

extension ProcessInfo.ThermalState {
    var title: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

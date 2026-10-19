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
import IOKit

/// Disk throughput from the block storage drivers, free space from the boot volume.
final class DiskSampler {
    private var previous: (read: UInt64, written: UInt64, time: TimeInterval)?
    private var lastSpaceCheck: TimeInterval = -.infinity
    private var space: (free: Double, total: Double) = (0, 0)
    private var drivers: [io_object_t] = []
    private var lastDriverScan: TimeInterval = -.infinity

    deinit {
        drivers.forEach { IOObjectRelease($0) }
    }

    /// `spaceInterval`: free space barely moves and asking for it can make the file system do work,
    /// so the caller checks it rarely unless the panel is open.
    func sample(now: TimeInterval, spaceInterval: TimeInterval) -> (read: Double, write: Double, free: Double, total: Double) {
        if now - lastSpaceCheck >= spaceInterval {
            lastSpaceCheck = now
            space = readSpace()
        }

        // Finding the drivers is a registry search; reading them is cheap. Search once a minute
        // so external drives that come and go are still picked up.
        if now - lastDriverScan > 60 || drivers.isEmpty && now - lastDriverScan > 5 {
            lastDriverScan = now
            let before = drivers.count
            findDrivers()
            if drivers.count != before { previous = nil }  // avoid a fake spike when a drive appears
        }
        let totals = readCounters()
        defer { previous = (totals.read, totals.written, now) }
        guard let previous, now > previous.time else { return (0, 0, space.free, space.total) }

        let elapsed = now - previous.time
        let read = totals.read >= previous.read ? Double(totals.read - previous.read) / elapsed : 0
        let write = totals.written >= previous.written ? Double(totals.written - previous.written) / elapsed : 0
        return (read, write, space.free, space.total)
    }

    func refreshSpaceSoon() {
        lastSpaceCheck = -.infinity
    }

    private func findDrivers() {
        drivers.forEach { IOObjectRelease($0) }
        drivers.removeAll()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            drivers.append(entry)
        }
    }

    private func readCounters() -> (read: UInt64, written: UInt64) {
        var read: UInt64 = 0
        var written: UInt64 = 0
        for driver in drivers {
            guard let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { continue }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, written)
    }

    private func readSpace() -> (free: Double, total: Double) {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Double(values?.volumeTotalCapacity ?? 0)
        return (free, total)
    }
}

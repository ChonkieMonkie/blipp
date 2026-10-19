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

import CSensors
import Foundation

/// Developer tool: `Blipp --benchmark` times every sampler so optimizations can be measured.
enum Benchmark {
    static func run(iterations: Int = 40) {
        print("Die sensors found: \(blipp_die_sensor_count())")
        if CommandLine.arguments.contains("--sensors") { blipp_debug_dump_sensors() }

        func time(_ name: String, warmup: Int = 2, _ body: () -> Void) {
            for _ in 0..<warmup { body() }
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations { body() }
            let perCall = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1_000_000
            print(String(format: "%-28@ %8.3f ms", name as NSString, perCall))
        }

        let cpu = CPUSampler()
        let memory = MemorySampler()
        let battery = BatterySampler()
        let disk = DiskSampler()
        let processes = ProcessSampler()
        let queue = DispatchQueue(label: "benchmark")
        let network = NetworkSampler(queue: queue)
        var now = ProcessInfo.processInfo.systemUptime

        time("CPU") { _ = cpu.sample() }
        time("Memory") { _ = memory.sample() }
        time("Battery") { _ = battery.sample() }
        time("Temperature (2 reads)") { _ = blipp_cpu_temperature(2) }
        time("Temperature (6 reads)") { _ = blipp_cpu_temperature(6) }
        time("Network") { now += 1; _ = network.sample(now: now) }
        time("Disk (counters)") { now += 1; _ = disk.sample(now: now, spaceInterval: .infinity) }
        time("Disk (with free space)") { now += 1; _ = disk.sample(now: now, spaceInterval: 0) }
        time("Processes") { now += 1; _ = processes.sample(now: now) }

        var series = Series()
        for second in 0..<3600 { series.append(Double(second % 100), at: Double(second)) }
        time("Graph points (1 h series)") { _ = series.points(span: 3600, now: 3600) }

        let engine = MoodEngine()
        let snapshot = Snapshot()
        time("Mood") { _ = engine.mood(for: snapshot, smoothedCPU: 40) }

        let scene = BlippScene(face: .sweaty, sweat: true)
        let context = IconExporter.makeContext(width: 36, height: 36)
        time("Menu bar icon draw") { MenuBarRenderer.draw(scene, in: context, size: 18, template: false, time: 1) }
        let panelContext = IconExporter.makeContext(width: 130, height: 130)
        time("Panel Blipp draw") { BlippRenderer.draw(scene, in: panelContext, origin: .zero, size: 100, time: 1) }
    }
}

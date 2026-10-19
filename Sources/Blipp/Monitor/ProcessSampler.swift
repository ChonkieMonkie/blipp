import AppKit
import Darwin

/// Finds the processes using the most CPU, the same way Activity Monitor counts it
/// (100 % = one full core).
final class ProcessSampler {
    private var previous: [Int32: UInt64] = [:]
    private var previousTime: TimeInterval?
    private var names: [Int32: String] = [:]
    private let ticksToNanos: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    func sample(now: TimeInterval, limit: Int = 3) -> [ProcessUsage] {
        let pids = listPids()
        var current: [Int32: UInt64] = [:]
        current.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            if result == 0 {
                current[pid] = usage.ri_user_time &+ usage.ri_system_time
            }
        }

        defer {
            previous = current
            previousTime = now
            names = names.filter { current[$0.key] != nil }
        }
        guard let previousTime, now > previousTime else { return [] }
        let elapsedNanos = (now - previousTime) * 1_000_000_000

        var usages: [ProcessUsage] = []
        for (pid, ticks) in current {
            guard let before = previous[pid], ticks >= before else { continue }
            let cpu = Double(ticks - before) * ticksToNanos / elapsedNanos * 100
            if cpu >= 0.5 {
                usages.append(ProcessUsage(pid: pid, name: "", cpu: cpu))
            }
        }

        usages.sort { $0.cpu > $1.cpu }
        return usages.prefix(limit).map { usage in
            var named = usage
            named.name = name(for: usage.pid)
            return named
        }
    }

    private func listPids() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private func name(for pid: Int32) -> String {
        if let cached = names[pid] { return cached }
        var resolved = NSRunningApplication(processIdentifier: pid)?.localizedName
        if resolved == nil {
            var buffer = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
                resolved = String(cString: buffer)
            }
        }
        let name = resolved ?? "PID \(pid)"
        names[pid] = name
        return name
    }
}

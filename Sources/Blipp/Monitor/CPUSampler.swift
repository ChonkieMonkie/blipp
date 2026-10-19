import Darwin
import Foundation

/// Reads per-core load from the Mach host and turns tick counters into percentages.
final class CPUSampler {
    private struct Ticks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private var previous: [Ticks] = []

    func sample() -> (total: Double, cores: [Double]) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return (0, []) }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var current: [Ticks] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * core
            current.append(Ticks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }

        defer { previous = current }
        guard previous.count == current.count else { return (0, Array(repeating: 0, count: current.count)) }

        var cores: [Double] = []
        var busyTotal: Double = 0
        var allTotal: Double = 0
        for (now, before) in zip(current, previous) {
            let busy = Double((now.user &- before.user) &+ (now.system &- before.system) &+ (now.nice &- before.nice))
            let idle = Double(now.idle &- before.idle)
            let all = busy + idle
            cores.append(all > 0 ? busy / all * 100 : 0)
            busyTotal += busy
            allTotal += all
        }
        return (allTotal > 0 ? busyTotal / allTotal * 100 : 0, cores)
    }
}

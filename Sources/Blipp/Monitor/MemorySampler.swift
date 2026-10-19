import Darwin
import Foundation

/// Mirrors the memory breakdown shown in Activity Monitor.
final class MemorySampler {
    func sample() -> MemoryInfo {
        var info = MemoryInfo()
        info.total = Double(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let purgeable = Double(stats.purgeable_count)
            info.app = max(0, Double(stats.internal_page_count) - purgeable) * page
            info.wired = Double(stats.wire_count) * page
            info.compressed = Double(stats.compressor_page_count) * page
            info.cached = (Double(stats.external_page_count) + purgeable) * page
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            info.swapUsed = Double(swap.xsu_used)
        }

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            info.pressure = MemoryInfo.Pressure(rawValue: Int(level)) ?? .normal
        }
        return info
    }
}

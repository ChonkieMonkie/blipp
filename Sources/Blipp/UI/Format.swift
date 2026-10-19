import Foundation

enum Format {
    static func bytes(_ value: Double) -> String {
        let gigabytes = value / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        return String(format: "%.0f MB", value / 1_048_576)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1_000: return "\(Int(bytesPerSecond.rounded())) B/s"
        case ..<1_000_000: return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        case ..<1_000_000_000: return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        default: return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000)
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

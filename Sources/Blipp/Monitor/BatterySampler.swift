import Foundation
import IOKit
import IOKit.ps

final class BatterySampler {
    /// Looked up once; the smart battery driver lives as long as the machine is up.
    private lazy var smartBattery: io_service_t = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

    deinit {
        if smartBattery != 0 { IOObjectRelease(smartBattery) }
    }

    func sample() -> BatteryInfo? {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current

            var info = BatteryInfo(
                percent: min(100, max(0, percent)),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                minutesToFull: positive(description[kIOPSTimeToFullChargeKey]),
                minutesToEmpty: positive(description[kIOPSTimeToEmptyKey])
            )
            readRegistry(into: &info)
            return info
        }
        return nil
    }

    private func positive(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes > 0 else { return nil }
        return minutes
    }

    /// Voltage and amperage come from the smart battery driver and give us the charging power.
    private func readRegistry(into info: inout BatteryInfo) {
        let service = smartBattery
        guard service != 0 else { return }

        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        if let voltage = (property("Voltage") as? NSNumber)?.doubleValue,
           let amperageNumber = (property("InstantAmperage") ?? property("Amperage")) as? NSNumber {
            let amperage = Double(Int64(bitPattern: amperageNumber.uint64Value))
            let watts = voltage * amperage / 1_000_000
            if abs(watts) < 500 {
                info.watts = watts
            }
        }

        if let adapter = property("AdapterDetails") as? [String: Any], let watts = adapter["Watts"] as? Int, watts > 0 {
            info.adapterWatts = watts
        }
    }
}

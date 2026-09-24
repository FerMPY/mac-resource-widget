import Foundation
import Darwin
import IOKit

struct EnergyUsage: Equatable {
    var joules: Double = 0
    var uptime: TimeInterval = 0
    var batteryPercent: Double? = nil   // share of a full battery charge
    var available: Bool = false
}

/// Measures how much energy this process itself has consumed since launch,
/// using the kernel's per-task energy counter (Apple Silicon).
enum EnergyTracker {
    /// Evaluated once, early in app launch (see AppDelegate).
    static let launchDate = Date()

    /// Cumulative energy used by this process, in joules.
    static func currentJoules() -> Double? {
        var info = task_power_info_v2()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Double(info.task_energy) / 1_000_000_000   // nanojoules → joules
    }

    /// Full-charge capacity of the internal battery, in milliwatt-hours.
    static func batteryCapacityMWh() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleSmartBattery"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        // mAh × mV / 1000 = mWh
        if let mAh = dict["AppleRawMaxCapacity"] as? Int,
           let mV = dict["Voltage"] as? Int, mAh > 0, mV > 0 {
            return Double(mAh) * Double(mV) / 1000.0
        }
        return nil
    }

    static func sample() -> EnergyUsage {
        var usage = EnergyUsage()
        usage.uptime = Date().timeIntervalSince(launchDate)
        guard let joules = currentJoules() else { return usage }
        usage.available = true
        usage.joules = joules
        let mWh = joules / 3.6   // 1 mWh = 3.6 J
        if let capacity = batteryCapacityMWh(), capacity > 0 {
            usage.batteryPercent = mWh / capacity * 100
        }
        return usage
    }
}

/// Live energy readout for the About section. Polls only while the
/// Preferences window is open.
final class EnergyViewModel: ObservableObject {
    static let shared = EnergyViewModel()
    @Published var usage = EnergyUsage()

    private var timer: Timer?
    private init() {}

    func start() {
        stop()
        usage = EnergyTracker.sample()
        let t = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            let u = EnergyTracker.sample()
            DispatchQueue.main.async { self?.usage = u }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

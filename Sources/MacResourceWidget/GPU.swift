import Foundation
import IOKit

/// Reads GPU utilization from the IOAccelerator IORegistry node's
/// PerformanceStatistics dictionary. Works on both Apple Silicon
/// (AGXAccelerator) and Intel (IOAccelerator) since AGX inherits.
final class GPUSampler {
    func sample() -> Double {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var best: Double = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perf = dict["PerformanceStatistics"] as? [String: Any]
            else { continue }

            // Apple Silicon uses "Device Utilization %"; some Intel drivers
            // expose "GPU Core Utilization" (in 0..1) or "GPU Activity(%)".
            if let v = perf["Device Utilization %"] as? Double {
                best = max(best, v)
            } else if let v = perf["Device Utilization %"] as? Int {
                best = max(best, Double(v))
            } else if let v = perf["GPU Activity(%)"] as? Double {
                best = max(best, v)
            } else if let v = perf["GPU Activity(%)"] as? Int {
                best = max(best, Double(v))
            } else if let v = perf["GPU Core Utilization"] as? Double {
                best = max(best, v * 100)
            }
        }
        return min(best, 100)
    }
}

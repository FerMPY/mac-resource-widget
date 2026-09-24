import Foundation
import Darwin
import IOKit
import IOKit.ps

enum MemoryPressure: String, Equatable {
    case normal, warning, critical
}

struct Snapshot: Equatable {
    var cpuPercent: Double = 0
    var perCoreCPU: [Double] = []
    var ramPercent: Double = 0
    var ramUsedGB: Double = 0
    var ramTotalGB: Double = 0
    var ramAppGB: Double = 0
    var ramWiredGB: Double = 0
    var ramCompressedGB: Double = 0
    var ramCachedGB: Double = 0
    var swapUsedGB: Double = 0
    var swapTotalGB: Double = 0
    var memoryPressure: MemoryPressure = .normal
    var gpuPercent: Double = 0
    var diskUsedPercent: Double = 0
    var diskFreeGB: Double = 0
    var diskTotalGB: Double = 0
    var netDownKBps: Double = 0
    var netUpKBps: Double = 0
    var batteryPercent: Double? = nil
    var batteryCharging: Bool = false
}

final class StatsCollector {
    private var prevCPUTicks: [[UInt32]] = []   // per core: user, system, idle, nice
    private var prevNetCounters: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var prevNetTime: TimeInterval = 0
    private let gpu = GPUSampler()

    func sample() -> Snapshot {
        var s = Snapshot()
        let cpu = sampleCPU()
        // Quantize to display precision so an idle system produces
        // byte-identical snapshots and Equatable catches no-op updates.
        s.cpuPercent = cpu.overall.rounded()
        s.perCoreCPU = cpu.perCore.map { $0.rounded() }
        let ram = sampleRAM()
        s.ramPercent = ram.percent.rounded()
        s.ramUsedGB = round1(ram.usedGB)
        s.ramTotalGB = ram.totalGB.rounded()
        s.ramAppGB = round1(ram.appGB)
        s.ramWiredGB = round1(ram.wiredGB)
        s.ramCompressedGB = round1(ram.compressedGB)
        s.ramCachedGB = round1(ram.cachedGB)
        let swap = sampleSwap()
        s.swapUsedGB = round1(swap.usedGB)
        s.swapTotalGB = round1(swap.totalGB)
        s.memoryPressure = samplePressure(usedGB: ram.usedGB,
                                          totalGB: ram.totalGB,
                                          swapUsedGB: swap.usedGB)
        s.gpuPercent = gpu.sample().rounded()
        let disk = sampleDisk()
        s.diskUsedPercent = disk.usedPercent.rounded()
        s.diskFreeGB = disk.freeGB.rounded()
        s.diskTotalGB = disk.totalGB.rounded()
        let net = sampleNetwork()
        s.netDownKBps = net.down.rounded()
        s.netUpKBps = net.up.rounded()
        let bat = sampleBattery()
        s.batteryPercent = bat?.percent.rounded()
        s.batteryCharging = bat?.charging ?? false
        return s
    }

    private func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    // MARK: - CPU

    private func sampleCPU() -> (overall: Double, perCore: [Double]) {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t? = nil
        var numCPUInfo: mach_msg_type_number_t = 0
        let err = host_processor_info(mach_host_self(),
                                      PROCESSOR_CPU_LOAD_INFO,
                                      &numCPUs,
                                      &cpuInfo,
                                      &numCPUInfo)
        guard err == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return (0, [])
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: cpuInfo),
                          vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var perCore: [Double] = []
        var newTicks: [[UInt32]] = []
        var busyAll = 0.0, totalAll = 0.0

        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            let ticks = [CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE].map {
                UInt32(bitPattern: cpuInfo[base + Int($0)])
            }
            newTicks.append(ticks)
            guard i < prevCPUTicks.count else {
                perCore.append(0)
                continue
            }
            // Wrapping subtraction: the kernel's tick counters are 32-bit
            // and wrap around after long uptimes.
            let d = zip(ticks, prevCPUTicks[i]).map { Double($0 &- $1) }
            let total = d.reduce(0, +)
            let busy = total - d[2]   // everything but idle
            perCore.append(total > 0 ? (busy / total) * 100 : 0)
            busyAll += busy
            totalAll += total
        }

        prevCPUTicks = newTicks
        return (totalAll > 0 ? (busyAll / totalAll) * 100 : 0, perCore)
    }

    // MARK: - RAM

    private struct RAMInfo {
        var percent = 0.0
        var usedGB = 0.0
        var totalGB = 0.0
        var appGB = 0.0
        var wiredGB = 0.0
        var compressedGB = 0.0
        var cachedGB = 0.0
    }

    private func sampleRAM() -> RAMInfo {
        var info = RAMInfo()

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return info }

        let gb = 1_073_741_824.0
        let ps = Double(pageSize)
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        info.totalGB = totalBytes / gb

        let wired = Double(stats.wire_count) * ps
        let compressed = Double(stats.compressor_page_count) * ps
        let purgeable = Double(stats.purgeable_count) * ps
        let external = Double(stats.external_page_count) * ps      // file-backed pages
        let internalPages = Double(stats.internal_page_count) * ps // anonymous (app) pages

        // App memory: anonymous, non-purgeable resident pages — matches the
        // "App Memory" figure Activity Monitor shows.
        let app = max(0, internalPages - purgeable)
        // Cached files: reclaimable memory used for file/purgeable caching.
        let cached = external + purgeable
        // Memory Used = App + Wired + Compressed (Activity Monitor's definition).
        let used = app + wired + compressed

        info.appGB = app / gb
        info.wiredGB = wired / gb
        info.compressedGB = compressed / gb
        info.cachedGB = cached / gb
        info.usedGB = used / gb
        info.percent = totalBytes > 0 ? (used / totalBytes) * 100 : 0
        return info
    }

    // MARK: - Swap

    private func sampleSwap() -> (usedGB: Double, totalGB: Double) {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        let gb = 1_073_741_824.0
        return (Double(swap.xsu_used) / gb, Double(swap.xsu_total) / gb)
    }

    // MARK: - Memory pressure

    private func samplePressure(usedGB: Double, totalGB: Double, swapUsedGB: Double) -> MemoryPressure {
        // Prefer the kernel's own pressure level when it's readable.
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            switch level {
            case 4: return .critical
            case 2: return .warning
            case 1: return .normal
            default: break
            }
        }
        // Fallback heuristic from used ratio + swap activity.
        let ratio = totalGB > 0 ? usedGB / totalGB : 0
        if ratio > 0.90 || swapUsedGB > 4 { return .critical }
        if ratio > 0.75 || swapUsedGB > 1 { return .warning }
        return .normal
    }

    // MARK: - Disk

    private func sampleDisk() -> (usedPercent: Double, freeGB: Double, totalGB: Double) {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return (0, 0, 0) }
        let blockSize = Double(stat.f_bsize)
        let total = Double(stat.f_blocks) * blockSize
        let free = Double(stat.f_bavail) * blockSize
        let used = total - free
        let totalGB = total / 1_073_741_824
        let freeGB = free / 1_073_741_824
        let percent = total > 0 ? (used / total) * 100 : 0
        return (percent, freeGB, totalGB)
    }

    // MARK: - Network

    private func sampleNetwork() -> (down: Double, up: Double) {
        // if_data's byte counters are 32-bit and wrap every 4 GB, so deltas
        // are taken per interface with wrapping subtraction before summing.
        var dRx: UInt64 = 0
        var dTx: UInt64 = 0
        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let iface = cur.pointee
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: iface.ifa_name)
                // Skip loopback and virtual interfaces
                if !name.hasPrefix("lo") && !name.hasPrefix("gif") && !name.hasPrefix("stf") &&
                   !name.hasPrefix("utun") && !name.hasPrefix("awdl") && !name.hasPrefix("llw") &&
                   !name.hasPrefix("anpi") && !name.hasPrefix("ap") && !name.hasPrefix("bridge") {
                    if let data = iface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        let cur = (rx: data.pointee.ifi_ibytes, tx: data.pointee.ifi_obytes)
                        counters[name] = cur
                        if let prev = prevNetCounters[name] {
                            dRx += UInt64(cur.rx &- prev.rx)
                            dTx += UInt64(cur.tx &- prev.tx)
                        }
                    }
                }
            }
            ptr = iface.ifa_next
        }

        let now = Date().timeIntervalSince1970
        defer {
            prevNetCounters = counters
            prevNetTime = now
        }
        guard prevNetTime > 0 else { return (0, 0) }
        let dt = now - prevNetTime
        guard dt > 0 else { return (0, 0) }
        return (Double(dRx) / dt / 1024.0, Double(dTx) / dt / 1024.0)
    }

    // MARK: - Battery

    private func sampleBattery() -> (percent: Double, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                // Actually charging — not merely plugged in (a full battery
                // on AC reports false).
                let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
                return (Double(current) / Double(max) * 100, charging)
            }
        }
        return nil
    }
}

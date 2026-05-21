import SwiftUI
import AppKit
import IOKit.ps

// MARK: - System actions

enum SystemActions {
    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - View model

final class StatsViewModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var cpuHistory: [Double] = []
    @Published var ramHistory: [Double] = []
    @Published var gpuHistory: [Double] = []

    private let collector = StatsCollector()
    private let maxHistory = 60
    private var timer: Timer?

    private var isVisible: Bool = true
    private var isScreenAwake: Bool = true
    private var onBattery: Bool = false

    private var powerSource: CFRunLoopSource?
    private let settings = Settings.shared
    private var settingsObserver: NSObjectProtocol?

    init() {
        _ = collector.sample()
        let first = collector.sample()
        snapshot = first

        updateBatteryState()
        installPowerObserver()
        installScreenObserver()
        installSettingsObserver()

        applyPollingState()
    }

    deinit {
        if let src = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate()
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        applyPollingState()
    }

    // MARK: Polling

    private var effectiveInterval: TimeInterval {
        let base = settings.refreshRate.rawValue
        return (settings.throttleOnBattery && onBattery) ? max(base, 2.0) : base
    }

    private var shouldPoll: Bool { isVisible && isScreenAwake }

    private func applyPollingState() {
        timer?.invalidate()
        timer = nil
        guard shouldPoll else { return }
        let t = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let s = self.collector.sample()
            DispatchQueue.main.async {
                if self.settings.showHistory {
                    self.pushHistory(s)
                    self.snapshot = s
                } else if s != self.snapshot {
                    self.snapshot = s
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func pushHistory(_ s: Snapshot) {
        appendTrim(&cpuHistory, s.cpuPercent)
        appendTrim(&ramHistory, s.ramPercent)
        appendTrim(&gpuHistory, s.gpuPercent)
    }

    private func appendTrim(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > maxHistory {
            arr.removeFirst(arr.count - maxHistory)
        }
    }

    // MARK: Power observer

    private func installPowerObserver() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let me = Unmanaged<StatsViewModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.updateBatteryState() }
        }
        if let src = IOPSNotificationCreateRunLoopSource(cb, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
    }

    private func updateBatteryState() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        var battery = false
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                battery = (state == kIOPSBatteryPowerValue)
                break
            }
        }
        if battery != onBattery {
            onBattery = battery
            applyPollingState()
        }
    }

    // MARK: Screen observer

    private func installScreenObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(screenDidSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenDidWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func screenDidSleep() {
        isScreenAwake = false
        applyPollingState()
    }

    @objc private func screenDidWake() {
        isScreenAwake = true
        applyPollingState()
    }

    // MARK: Settings observer

    private func installSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsRefreshChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyPollingState()
        }
    }
}

extension Notification.Name {
    static let settingsRefreshChanged = Notification.Name("settings.refreshChanged")
    static let settingsWindowLevelChanged = Notification.Name("settings.windowLevelChanged")
}

// MARK: - Root view (routes between layouts)

struct WidgetView: View {
    @ObservedObject var model: StatsViewModel
    @ObservedObject var settings = Settings.shared
    @State private var dragStartMouse: NSPoint?
    @State private var dragStartOrigin: NSPoint?
    @State private var didDrag = false

    private static var widgetWindow: NSWindow? {
        NSApp.windows.first { $0 is WidgetWindow }
    }

    var body: some View {
        Group {
            if settings.compactMode {
                CompactWidget(model: model, settings: settings)
            } else {
                FullWidget(model: model, settings: settings)
            }
        }
        .contentShape(Rectangle())
        // Drag moves the window. minimumDistance 0 so even a plain click is
        // consumed by the gesture — otherwise an unhandled click on this
        // desktop-adjacent window could fall through to the desktop. Movement
        // uses absolute screen mouse position so moving the window mid-drag
        // doesn't feed back into the delta.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard let window = Self.widgetWindow else { return }
                    let mouse = NSEvent.mouseLocation
                    if dragStartMouse == nil {
                        dragStartMouse = mouse
                        dragStartOrigin = window.frame.origin
                        didDrag = false
                    }
                    guard let sm = dragStartMouse, let so = dragStartOrigin else { return }
                    let dx = mouse.x - sm.x
                    let dy = mouse.y - sm.y
                    if abs(dx) > 5 || abs(dy) > 5 { didDrag = true }
                    if didDrag {
                        window.setFrameOrigin(NSPoint(x: so.x + dx, y: so.y + dy))
                    }
                }
                .onEnded { _ in
                    dragStartMouse = nil
                    dragStartOrigin = nil
                    didDrag = false
                }
        )
    }
}

// MARK: - Full layout

struct FullWidget: View {
    @ObservedObject var model: StatsViewModel
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.showCPU {
                StatRow(label: "CPU",
                        value: model.snapshot.cpuPercent,
                        detail: nil,
                        color: settings.color(for: .cpu),
                        history: settings.showHistory ? model.cpuHistory : nil)
                if settings.showPerCore && !model.snapshot.perCoreCPU.isEmpty {
                    PerCoreStrip(cores: model.snapshot.perCoreCPU,
                                 color: settings.color(for: .cpu))
                }
            }

            if settings.showRAM {
                MemorySection(snapshot: model.snapshot,
                              history: settings.showHistory ? model.ramHistory : nil,
                              detailed: settings.detailedMemory,
                              baseColor: settings.color(for: .ram))
            }

            if settings.showGPU {
                StatRow(label: "GPU",
                        value: model.snapshot.gpuPercent,
                        detail: nil,
                        color: settings.color(for: .gpu),
                        history: settings.showHistory ? model.gpuHistory : nil)
            }

            if settings.showDisk {
                StatRow(label: "Disk",
                        value: model.snapshot.diskUsedPercent,
                        detail: String(format: "%.0f GB free", model.snapshot.diskFreeGB),
                        color: settings.color(for: .disk),
                        history: nil)
            }

            if settings.showNetwork {
                NetworkRow(down: model.snapshot.netDownKBps,
                           up: model.snapshot.netUpKBps)
            }

            if settings.showBattery, let battery = model.snapshot.batteryPercent {
                BatteryRow(percent: battery, charging: model.snapshot.batteryCharging)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 240)
        .background(WidgetBackground(opacity: settings.backgroundOpacity, cornerRadius: 22))
        .opacity(0.5 + 0.5 * settings.backgroundOpacity)
        .fixedSize()
    }
}

// MARK: - Compact layout

struct CompactWidget: View {
    @ObservedObject var model: StatsViewModel
    @ObservedObject var settings: Settings

    var body: some View {
        HStack(spacing: 0) {
            chips
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(WidgetBackground(opacity: settings.backgroundOpacity, cornerRadius: 16))
        .opacity(0.5 + 0.5 * settings.backgroundOpacity)
        .fixedSize()
    }

    @ViewBuilder
    private var chips: some View {
        let items = enabledChips
        ForEach(Array(items.enumerated()), id: \.offset) { idx, chip in
            if idx > 0 {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1, height: 28)
                    .padding(.horizontal, 2)
            }
            CompactChip(label: chip.label, value: chip.value, color: chip.color)
        }
    }

    private struct ChipData { let label: String; let value: Double; let color: Color }

    private var enabledChips: [ChipData] {
        var out: [ChipData] = []
        if settings.showCPU {
            out.append(ChipData(label: "CPU", value: model.snapshot.cpuPercent,
                                color: settings.color(for: .cpu)))
        }
        if settings.showRAM {
            out.append(ChipData(label: "RAM", value: model.snapshot.ramPercent,
                                color: settings.color(for: .ram)))
        }
        if settings.showGPU {
            out.append(ChipData(label: "GPU", value: model.snapshot.gpuPercent,
                                color: settings.color(for: .gpu)))
        }
        if settings.showDisk {
            out.append(ChipData(label: "DISK", value: model.snapshot.diskUsedPercent,
                                color: settings.color(for: .disk)))
        }
        if settings.showBattery, let b = model.snapshot.batteryPercent {
            out.append(ChipData(label: "BATT", value: b,
                                color: model.snapshot.batteryCharging ? .green : .white.opacity(0.85)))
        }
        return out
    }
}

struct CompactChip: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Int(value))%")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(color.opacity(0.9))
                    .frame(width: max(3, 30 * CGFloat(min(max(value / 100, 0), 1))))
            }
            .frame(width: 30, height: 3)
        }
        .frame(minWidth: 44)
        .padding(.horizontal, 4)
    }
}

// MARK: - Shared background

struct WidgetBackground: View {
    let opacity: Double
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Color.black.opacity(0.18 * opacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - Row components

struct StatRow: View {
    let label: String
    let value: Double
    let detail: String?
    let color: Color
    let history: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            ProgressBar(value: value / 100, color: color)
            if let history, history.count >= 2 {
                Sparkline(values: history, color: color)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(color.opacity(0.9))
                    .frame(width: max(3, geo.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Memory section

/// Shades used for the memory composition (bar segments + legend swatches).
enum MemoryShade {
    static let app = 1.0
    static let wired = 0.68
    static let compressed = 0.42
    static let cached = 0.26
}

struct MemorySection: View {
    let snapshot: Snapshot
    let history: [Double]?
    let detailed: Bool
    let baseColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(snapshot.ramPercent))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            ProgressBar(value: snapshot.ramPercent / 100, color: baseColor)
            if let history, history.count >= 2 {
                Sparkline(values: history, color: baseColor)
            }
            if detailed {
                StackedMemoryBar(snapshot: snapshot, baseColor: baseColor)
                    .padding(.top, 2)
                MemoryLegend(snapshot: snapshot, baseColor: baseColor)
            } else {
                Text(String(format: "%.1f of %.0f GB", snapshot.ramUsedGB, snapshot.ramTotalGB))
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Stacked composition bar: App / Wired / Compressed / Cached against total RAM.
struct StackedMemoryBar: View {
    let snapshot: Snapshot
    let baseColor: Color

    var body: some View {
        GeometryReader { geo in
            let total = max(snapshot.ramTotalGB, 0.001)
            let w = geo.size.width
            HStack(spacing: 1) {
                seg(snapshot.ramAppGB, total, w, MemoryShade.app)
                seg(snapshot.ramWiredGB, total, w, MemoryShade.wired)
                seg(snapshot.ramCompressedGB, total, w, MemoryShade.compressed)
                seg(snapshot.ramCachedGB, total, w, MemoryShade.cached)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .background(Capsule().fill(.white.opacity(0.08)))
        .clipShape(Capsule())
    }

    private func seg(_ gb: Double, _ total: Double, _ w: CGFloat, _ shade: Double) -> some View {
        Rectangle()
            .fill(baseColor.opacity(shade))
            .frame(width: max(0, CGFloat(gb / total) * w))
    }
}

struct MemoryLegend: View {
    let snapshot: Snapshot
    let baseColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                item("App", snapshot.ramAppGB, MemoryShade.app)
                item("Wired", snapshot.ramWiredGB, MemoryShade.wired)
            }
            HStack(spacing: 10) {
                item("Comp", snapshot.ramCompressedGB, MemoryShade.compressed)
                item("Cache", snapshot.ramCachedGB, MemoryShade.cached)
            }
            HStack(spacing: 6) {
                Text("Swap")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f GB", snapshot.swapUsedGB))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Circle()
                    .fill(pressureColor)
                    .frame(width: 6, height: 6)
                Text(pressureLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func item(_ label: String, _ gb: Double, _ shade: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(baseColor.opacity(shade))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(String(format: "%.1f GB", gb))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var pressureColor: Color {
        switch snapshot.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var pressureLabel: String {
        switch snapshot.memoryPressure {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }
}

struct Sparkline: View {
    let values: [Double]   // 0...100
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = points(w: w, h: h)
            ZStack {
                // Area fill
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    for pt in pts { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: last.x, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                // Line
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 22)
    }

    // Soft auto-scale: ceiling tracks the peak but never below 25% so an
    // idle metric still shows texture without wildly exaggerating noise.
    private func points(w: CGFloat, h: CGFloat) -> [CGPoint] {
        let n = values.count
        guard n >= 2 else { return [] }
        let scaleMax = max((values.max() ?? 0) * 1.2, 25)
        return values.enumerated().map { i, v in
            let x = CGFloat(i) / CGFloat(n - 1) * w
            let clamped = min(max(v, 0), scaleMax)
            let y = h - CGFloat(clamped / scaleMax) * h
            return CGPoint(x: x, y: y)
        }
    }
}

struct PerCoreStrip: View {
    let cores: [Double]
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color.opacity(0.6))
                    .frame(height: max(2, CGFloat(c / 100) * 16))
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
            }
        }
        .frame(height: 16, alignment: .bottom)
    }
}

struct NetworkRow: View {
    let down: Double
    let up: Double

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(format(down))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(format(up))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
    }

    private func format(_ kbps: Double) -> String {
        if kbps >= 1024 {
            return String(format: "%.1f MB/s", kbps / 1024)
        }
        return String(format: "%.0f KB/s", kbps)
    }
}

struct BatteryRow: View {
    let percent: Double
    let charging: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: charging ? "battery.100.bolt" : batteryIcon(percent))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(charging ? .green : (percent < 20 ? .red : .secondary))
            Text("\(Int(percent))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func batteryIcon(_ p: Double) -> String {
        switch p {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

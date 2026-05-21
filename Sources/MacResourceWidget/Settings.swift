import Foundation
import SwiftUI

enum ColorTheme: String, CaseIterable, Identifiable {
    case multicolor, monochrome, accent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .multicolor: return "Multicolor"
        case .monochrome: return "Monochrome"
        case .accent: return "System Accent"
        }
    }
}

enum RefreshRate: Double, CaseIterable, Identifiable {
    case fast = 1.0
    case normal = 2.0
    case slow = 5.0
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .fast: return "1 second"
        case .normal: return "2 seconds"
        case .slow: return "5 seconds"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    // Persisted via property observers below.
    @Published var refreshRate: RefreshRate {
        didSet { d.set(refreshRate.rawValue, forKey: K.refresh) }
    }
    @Published var throttleOnBattery: Bool {
        didSet { d.set(throttleOnBattery, forKey: K.throttle) }
    }
    @Published var showCPU: Bool { didSet { d.set(showCPU, forKey: K.showCPU) } }
    @Published var showPerCore: Bool { didSet { d.set(showPerCore, forKey: K.showPerCore) } }
    @Published var showRAM: Bool { didSet { d.set(showRAM, forKey: K.showRAM) } }
    @Published var showGPU: Bool { didSet { d.set(showGPU, forKey: K.showGPU) } }
    @Published var showDisk: Bool { didSet { d.set(showDisk, forKey: K.showDisk) } }
    @Published var showNetwork: Bool { didSet { d.set(showNetwork, forKey: K.showNetwork) } }
    @Published var showBattery: Bool { didSet { d.set(showBattery, forKey: K.showBattery) } }
    @Published var colorTheme: ColorTheme {
        didSet { d.set(colorTheme.rawValue, forKey: K.theme) }
    }
    @Published var backgroundOpacity: Double {
        didSet { d.set(backgroundOpacity, forKey: K.opacity) }
    }
    @Published var showHistory: Bool {
        didSet { d.set(showHistory, forKey: K.showHistory) }
    }
    @Published var compactMode: Bool {
        didSet { d.set(compactMode, forKey: K.compact) }
    }
    @Published var detailedMemory: Bool {
        didSet { d.set(detailedMemory, forKey: K.detailedMem) }
    }
    @Published var alwaysOnTop: Bool {
        didSet {
            d.set(alwaysOnTop, forKey: K.alwaysOnTop)
            NotificationCenter.default.post(name: .settingsWindowLevelChanged, object: nil)
        }
    }

    private let d = UserDefaults.standard
    private enum K {
        static let refresh = "settings.refreshRate"
        static let throttle = "settings.throttleOnBattery"
        static let showCPU = "settings.showCPU"
        static let showPerCore = "settings.showPerCore"
        static let showRAM = "settings.showRAM"
        static let showGPU = "settings.showGPU"
        static let showDisk = "settings.showDisk"
        static let showNetwork = "settings.showNetwork"
        static let showBattery = "settings.showBattery"
        static let theme = "settings.colorTheme"
        static let opacity = "settings.backgroundOpacity"
        static let showHistory = "settings.showHistory"
        static let compact = "settings.compactMode"
        static let detailedMem = "settings.detailedMemory"
        static let alwaysOnTop = "widget.alwaysOnTop"
    }

    private init() {
        let d = UserDefaults.standard
        // Register defaults so first launch picks them up.
        d.register(defaults: [
            K.refresh: RefreshRate.fast.rawValue,
            K.throttle: true,
            K.showCPU: true,
            K.showPerCore: true,
            K.showRAM: true,
            K.showGPU: true,
            K.showDisk: true,
            K.showNetwork: true,
            K.showBattery: true,
            K.theme: ColorTheme.multicolor.rawValue,
            K.opacity: 1.0,
            K.showHistory: true,
            K.compact: false,
            K.detailedMem: true,
            K.alwaysOnTop: false,
        ])
        self.refreshRate = RefreshRate(rawValue: d.double(forKey: K.refresh)) ?? .fast
        self.throttleOnBattery = d.bool(forKey: K.throttle)
        self.showCPU = d.bool(forKey: K.showCPU)
        self.showPerCore = d.bool(forKey: K.showPerCore)
        self.showRAM = d.bool(forKey: K.showRAM)
        self.showGPU = d.bool(forKey: K.showGPU)
        self.showDisk = d.bool(forKey: K.showDisk)
        self.showNetwork = d.bool(forKey: K.showNetwork)
        self.showBattery = d.bool(forKey: K.showBattery)
        self.colorTheme = ColorTheme(rawValue: d.string(forKey: K.theme) ?? "") ?? .multicolor
        self.backgroundOpacity = d.double(forKey: K.opacity)
        self.showHistory = d.bool(forKey: K.showHistory)
        self.compactMode = d.bool(forKey: K.compact)
        self.detailedMemory = d.bool(forKey: K.detailedMem)
        self.alwaysOnTop = d.bool(forKey: K.alwaysOnTop)
    }

    /// Color for a given metric, based on the active theme.
    func color(for metric: Metric) -> Color {
        switch colorTheme {
        case .monochrome:
            return .white.opacity(0.85)
        case .accent:
            return Color.accentColor
        case .multicolor:
            switch metric {
            case .cpu: return .cyan
            case .ram: return .purple
            case .gpu: return .pink
            case .disk: return .orange
            }
        }
    }

    enum Metric { case cpu, ram, gpu, disk }
}

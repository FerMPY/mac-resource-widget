import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Form {
            Section("Metrics") {
                Toggle("CPU", isOn: $settings.showCPU)
                Toggle("Per-core CPU bars", isOn: $settings.showPerCore)
                    .disabled(!settings.showCPU)
                Toggle("Memory", isOn: $settings.showRAM)
                Toggle("Detailed memory breakdown", isOn: $settings.detailedMemory)
                    .disabled(!settings.showRAM)
                Toggle("GPU", isOn: $settings.showGPU)
                Toggle("Disk", isOn: $settings.showDisk)
                Toggle("Network", isOn: $settings.showNetwork)
                Toggle("Battery", isOn: $settings.showBattery)
            }

            Section("Refresh") {
                Picker("Update every", selection: $settings.refreshRate) {
                    ForEach(RefreshRate.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .onChange(of: settings.refreshRate) { _, _ in
                    NotificationCenter.default.post(name: .settingsRefreshChanged, object: nil)
                }
                Toggle("Slow down to ≥2s on battery", isOn: $settings.throttleOnBattery)
                    .onChange(of: settings.throttleOnBattery) { _, _ in
                        NotificationCenter.default.post(name: .settingsRefreshChanged, object: nil)
                    }
            }

            Section("Layout") {
                Toggle("Compact mode", isOn: $settings.compactMode)
                Toggle("Always on top", isOn: $settings.alwaysOnTop)
                Toggle("History graphs", isOn: $settings.showHistory)
                    .disabled(settings.compactMode)
            }

            Section("Appearance") {
                Picker("Color theme", selection: $settings.colorTheme) {
                    ForEach(ColorTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                HStack {
                    Text("Background opacity")
                    Slider(value: $settings.backgroundOpacity, in: 0.3...1.0)
                    Text("\(Int(settings.backgroundOpacity * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 610)
    }
}

/// Holds onto the preferences NSWindow so it isn't reused/recreated.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private convenience init() {
        let host = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: host)
        window.title = "Mac Resource Widget — Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 380, height: 610))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        // Briefly bring the app forward so the window can receive focus,
        // then drop back to accessory so we still have no dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

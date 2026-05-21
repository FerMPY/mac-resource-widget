import Cocoa
import SwiftUI

@main
struct Bootstrap {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: WidgetWindow!
    private let model = StatsViewModel()
    private let posKey = "widget.topLeft"

    // Anchor point: the widget's top-left corner in screen coords. The window
    // resizes itself to fit content, so we re-anchor on every resize to keep
    // the top edge stable instead of the (Cocoa-default) bottom edge.
    private var desiredTopLeft: NSPoint = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = WidgetHostingController(rootView: WidgetView(model: model))
        host.sizingOptions = [.preferredContentSize]

        window = WidgetWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 320),
                              styleMask: [.borderless, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.contentViewController = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // .stationary makes the window behave like desktop furniture for
        // window management — excluded from Mission Control / Stage Manager /
        // Exposé — while still being a real, clickable normal-level window.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        desiredTopLeft = restoreTopLeft() ?? defaultTopLeft()

        NotificationCenter.default.addObserver(self, selector: #selector(windowMoved),
                                               name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResized),
                                               name: NSWindow.didResizeNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLevelChanged),
                                               name: .settingsWindowLevelChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: window)

        window.orderFront(nil)
        applyLevel()
        repositionToDesired()

        model.setVisible(window.occlusionState.contains(.visible))
    }

    @objc private func occlusionChanged() {
        model.setVisible(window.occlusionState.contains(.visible))
    }

    // MARK: - Positioning

    private func defaultTopLeft() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 40, y: 800) }
        let v = screen.visibleFrame
        return NSPoint(x: v.maxX - 260, y: v.maxY - 20)
    }

    private func restoreTopLeft() -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: posKey) else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        guard p.count == 2 else { return nil }
        return NSPoint(x: p[0], y: p[1])
    }

    private func saveTopLeft() {
        UserDefaults.standard.set("\(desiredTopLeft.x),\(desiredTopLeft.y)", forKey: posKey)
    }

    @objc private func windowMoved() {
        let f = window.frame
        desiredTopLeft = NSPoint(x: f.minX, y: f.maxY)
        saveTopLeft()
    }

    @objc private func windowResized() {
        repositionToDesired()
    }

    private func repositionToDesired() {
        let f = window.frame
        var origin = NSPoint(x: desiredTopLeft.x, y: desiredTopLeft.y - f.height)
        if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), max(vf.minX, vf.maxX - f.width))
            origin.y = min(max(origin.y, vf.minY), max(vf.minY, vf.maxY - f.height))
        }
        if f.origin != origin {
            window.setFrameOrigin(origin)
        }
    }

    // MARK: - Window level

    @objc private func windowLevelChanged() {
        applyLevel()
    }

    @objc private func windowResignedKey() {
        // When the user clicks away, sink the widget back behind other
        // windows so it reads as living on the desktop without being stuck
        // on top. Skipped in always-on-top mode.
        if !Settings.shared.alwaysOnTop {
            window.orderBack(nil)
        }
    }

    fileprivate func applyLevel() {
        if Settings.shared.alwaysOnTop {
            window.level = .floating
        } else {
            // A normal-level window ordered behind the others. The desktop-
            // icon level looks more "on the desktop" but the OS treats that
            // whole layer as the desktop itself — clicks (especially after
            // click-to-reveal-desktop) get swallowed before reaching the
            // widget. A normal window that sinks to the back stays genuinely
            // clickable while still sitting behind your app windows.
            window.level = .normal
            window.orderBack(nil)
        }
    }

    // MARK: - Menu actions

    @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        Settings.shared.alwaysOnTop.toggle()
        sender.state = Settings.shared.alwaysOnTop ? .on : .off
    }

    @objc func toggleCompact(_ sender: NSMenuItem) {
        Settings.shared.compactMode.toggle()
        sender.state = Settings.shared.compactMode ? .on : .off
    }

    @objc func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc func openActivityMonitor() {
        SystemActions.openActivityMonitor()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

/// NSHostingView that responds to the first click even when the app is not
/// active — required for a desktop-level widget, otherwise the first click
/// only activates the window and never reaches the SwiftUI gestures.
final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Hosting controller that installs the first-mouse-aware hosting view while
/// keeping `sizingOptions`-based window auto-resizing.
final class WidgetHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = WidgetHostingView(rootView: rootView)
    }
}

/// Borderless window that accepts mouse events and shows a context menu.
final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let menu = NSMenu()

        let prefsItem = NSMenuItem(title: "Edit Widget…",
                                   action: #selector(AppDelegate.openPreferences),
                                   keyEquivalent: ",")
        prefsItem.target = delegate
        menu.addItem(prefsItem)

        let amItem = NSMenuItem(title: "Open Activity Monitor",
                                action: #selector(AppDelegate.openActivityMonitor),
                                keyEquivalent: "")
        amItem.target = delegate
        menu.addItem(amItem)

        menu.addItem(.separator())

        let compactItem = NSMenuItem(title: "Compact Mode",
                                     action: #selector(AppDelegate.toggleCompact(_:)),
                                     keyEquivalent: "")
        compactItem.target = delegate
        compactItem.state = Settings.shared.compactMode ? .on : .off
        menu.addItem(compactItem)

        let topItem = NSMenuItem(title: "Always on Top",
                                 action: #selector(AppDelegate.toggleAlwaysOnTop(_:)),
                                 keyEquivalent: "")
        topItem.target = delegate
        topItem.state = Settings.shared.alwaysOnTop ? .on : .off
        menu.addItem(topItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Mac Resource Widget",
                                  action: #selector(AppDelegate.quit),
                                  keyEquivalent: "q")
        quitItem.target = delegate
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self.contentView!)
    }
}

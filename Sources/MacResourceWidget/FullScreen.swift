import Cocoa
import CoreGraphics

/// Detects another app showing a full-screen window on a given screen — a
/// native full-screen Space, or a browser's full-screen video. Used to hide
/// the always-on-top widget so it doesn't float over full-screen content.
enum FullScreenDetector {
    static func isOtherAppFullScreen(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // CGWindow bounds use a top-left origin relative to the primary screen.
        let f = screen.frame
        let screenRect = CGRect(x: f.minX, y: primary.frame.maxY - f.maxY,
                                width: f.width, height: f.height)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            // Ordinary (even zoomed) windows stop below the menu bar; only
            // full-screen windows cover the entire display.
            if bounds.insetBy(dx: -1, dy: -1).contains(screenRect) {
                return true
            }
        }
        return false
    }
}

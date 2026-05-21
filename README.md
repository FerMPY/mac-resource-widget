# Mac Resource Widget

A real-time system monitor that lives on your macOS desktop.

<p align="center">
  <img src="docs/screenshot.png" width="240" alt="Mac Resource Widget">
</p>

## Why

macOS already has Notification Center widgets — but **WidgetKit widgets cannot
update in real time**. The system throttles their refreshes to minutes apart to
save battery, so a CPU meter built with WidgetKit would show stale numbers.

Mac Resource Widget is a lightweight native window that polls **every 1–5
seconds** for genuinely live data, and sits on your desktop behind your app
windows like a piece of desktop furniture. No Dock icon, no menu-bar clutter.

## Features

- **Live metrics** — CPU (with per-core bars), Memory, GPU, Disk, Network, Battery
- **Sparkline history** — 60-sample rolling graphs for CPU / Memory / GPU
- **Detailed memory** — App / Wired / Compressed / Cached breakdown, plus swap
  usage and memory-pressure indicator
- **Compact mode** — collapse to a single-line pill
- **Battery-aware** — pauses polling when the widget is covered or the display
  sleeps; throttles refresh on battery
- **Stays out of the way** — excluded from Mission Control, Stage Manager and
  ⌘-Tab; sits behind your app windows (or pin it always-on-top)
- **Customizable** — toggle any metric, pick refresh rate, color theme and
  background opacity
- **No dependencies** — pure Swift + AppKit + SwiftUI

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon recommended — GPU utilization is read from the Apple Silicon
  `IOAccelerator` registry; Intel GPUs may report under a different key
- To build: the Swift toolchain (Xcode or the Command Line Tools)

## Install

### From a release DMG

Open the `.dmg` and drag **MacResourceWidget.app** onto the Applications
shortcut.

> The app is ad-hoc signed (no paid Apple Developer ID), so on first launch
> Gatekeeper will block it. Right-click the app → **Open**, or allow it under
> **System Settings → Privacy & Security**. You only need to do this once.

### Build it yourself

```sh
git clone <repo-url>
cd mac-resource-widget
./build.sh           # produces MacResourceWidget.app
open MacResourceWidget.app
```

To produce a distributable installer:

```sh
./package.sh         # produces MacResourceWidget.dmg
```

To launch automatically at login, add the app under
**System Settings → General → Login Items**.

## Usage

- **Drag** anywhere on the widget to reposition it (position is remembered).
- **Right-click** for the menu:
  - **Edit Widget…** — toggle metrics, refresh rate, theme, opacity, layout
  - **Open Activity Monitor**
  - **Compact Mode** — single-line layout
  - **Always on Top** — float above all windows instead of sitting behind them
  - **Quit**

## How it works

Pure Swift, no third-party dependencies:

| Metric | Source |
|--------|--------|
| CPU / per-core | Mach `host_processor_info` |
| Memory | Mach `host_statistics64` (`vm_statistics64`) |
| Swap | `sysctl vm.swapusage` |
| GPU | `IOAccelerator` IORegistry (`PerformanceStatistics`) |
| Disk | `statfs` |
| Network | `getifaddrs` interface byte counters |
| Battery | `IOPowerSources` |

The widget is a borderless, normal-level `NSWindow` with the `.stationary`
collection behavior — that combination keeps it clickable while making window
management (Mission Control, Stage Manager, Exposé) treat it like the desktop.

## Known limitations

- **Not a WidgetKit / Notification Center widget** — a deliberate tradeoff;
  WidgetKit cannot refresh in real time.
- **Activity Monitor** opens from the right-click menu but the matching tab
  cannot be pre-selected (no API for that), and its cold launch takes a moment.
- **GPU on Intel Macs** may need a different IORegistry key than the Apple
  Silicon path.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for planned features and ideas.

## License

[MIT](LICENSE)

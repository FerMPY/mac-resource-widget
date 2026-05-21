# Mac Resource Widget — Roadmap

Feature backlog for the desktop system-monitor widget. Items are grouped by
how useful they'd be day-to-day vs. how much work they take.

## Shipped

- **Live stats** — CPU, per-core CPU, RAM, GPU, Disk, Network, Battery
- **Desktop-level window** — sits on the desktop, covered by app windows
- **Battery-aware polling** — pauses when occluded or screen asleep, throttles on battery
- **Native styling** — `.regularMaterial` background, 22pt corners
- **Preferences** — toggle metrics, refresh rate, color theme, opacity
- **Sparkline history graphs** — 60-sample rolling line charts for CPU/RAM/GPU
- **Open Activity Monitor** — from the right-click menu
- **Compact mode** — single-line horizontal pill layout
- **App icon** — generated programmatically (`Scripts/make_icon.swift`)

## Backlog

### High value — would actually use daily

#### Threshold alerts
Local notification when a metric stays above a threshold for N seconds
(e.g. CPU > 90% for 30s). Needs `UNUserNotificationCenter` + a small
sustained-state tracker in `StatsViewModel`. Add threshold + duration
controls to Preferences.
*Effort: ~120 lines. Gotcha: notification permission prompt on first alert.*

#### Color thresholds
Bars shift color by severity — green < 60%, amber 60–85%, red > 85%.
Purely a `ProgressBar` change; thresholds could be fixed or configurable.
*Effort: ~40 lines.*

### Worth doing if the widget gets heavy use

#### Top processes
Show the top 3 processes by CPU (and/or memory). Parse
`ps -arcwwwxo "pid pcpu pmem comm"`, take the top rows. Adds a section to
the full layout.
*Effort: ~100 lines. Gotcha: `ps` shell-out runs every refresh — cache it
or sample it at a slower cadence than the bars.*

#### Temperature
CPU / GPU temperature via SMC keys. Trivial on Intel; on Apple Silicon the
SMC layout differs and the useful keys are model-specific. Realistically
needs a small SMC-reading helper (see the `SMCKit` / `smc` open-source
implementations, or `powermetrics` which requires root).
*Effort: ~200+ lines, or a vendored dependency. Gotcha: Apple Silicon
sensor keys are not documented and vary by chip.*

#### Fan speeds
Same SMC story as temperature — read `F0Ac` / `F1Ac` style keys. Many
Apple Silicon laptops have one fan; the Air has none.
*Effort: folds into the temperature/SMC work.*

#### Multiple widgets
Let the user spawn more than one widget, each with its own metric set and
position (e.g. a CPU-only mini-widget in one corner, a full one elsewhere).
Requires per-widget settings instances and an array of windows.
*Effort: ~250 lines — meaningful refactor of `Settings` and `AppDelegate`.*

#### Multi-monitor awareness
Remember position per display; reposition gracefully when a monitor is
unplugged. Listen for `NSApplication.didChangeScreenParametersNotification`.
*Effort: ~80 lines.*

### Nice-to-have / polish

#### Wallpaper-adaptive theme
Sample the desktop wallpaper's dominant colors and tint the widget to match.
Read the wallpaper via `NSWorkspace.desktopImageURL(for:)`, downscale,
extract average/dominant color.
*Effort: ~120 lines.*

#### Energy-impact self-readout
Show the widget's own energy footprint — a fun meta-stat. Hard to get an
exact "Energy Impact" number (that's a private Activity Monitor metric);
approximate with this process's CPU time.
*Effort: ~60 lines, approximate only.*

#### Process killer
Right-click a top-process row → Quit / Force Quit. Depends on the
"Top processes" feature landing first. Use `kill(pid, SIGTERM/SIGKILL)`.
*Effort: ~50 lines on top of Top processes. Gotcha: killing other users'
or system processes will fail without privileges — handle gracefully.*

#### Network details
Wi-Fi SSID + signal strength, current public IP, link speed. SSID/RSSI via
CoreWLAN (`CWWiFiClient`); public IP needs a network request (so: respect
the offline case, cache it).
*Effort: ~120 lines. Gotcha: CoreWLAN SSID access may require Location
permission on recent macOS.*

#### Battery health
Design capacity vs. current max capacity, cycle count. Available from
`IOServiceMatching("AppleSmartBattery")` registry properties
(`DesignCapacity`, `AppleRawMaxCapacity`, `CycleCount`).
*Effort: ~70 lines.*

#### Export to time-series
Persist samples to SQLite or CSV so trends can be graphed in a real tool.
A rolling ring buffer flushed to disk periodically.
*Effort: ~150 lines.*

#### Distribution — Homebrew + GitHub
Publish the source on GitHub and ship a Homebrew cask so it installs with
`brew install --cask`. Needs a proper (non-ad-hoc) signature and ideally
notarization for the cask to install without Gatekeeper warnings — that
requires an Apple Developer account ($99/yr).
*Effort: mostly process, not code. Gotcha: notarization needs a paid
Developer account.*

## Known limitations

- **Not a WidgetKit widget.** It does not appear in the macOS "Edit Widgets"
  picker. That was a deliberate tradeoff — WidgetKit widgets cannot update
  in real time (the system throttles refreshes to minutes). This widget
  polls every 1–5s for genuinely live data.
- **Activity Monitor.** The right-click menu opens Activity Monitor but
  cannot pre-select a specific tab — Activity Monitor exposes no API or URL
  scheme for that. Cold launch also takes a second or two (Apple's app).
- **GPU on Intel Macs.** GPU % is read from the `IOAccelerator` registry
  node. Tuned for Apple Silicon; Intel integrated/discrete GPUs may expose
  the utilization figure under a different key.

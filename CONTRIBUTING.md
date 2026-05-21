# Contributing

Thanks for your interest in improving Mac Resource Widget. This is a small,
dependency-free project — contributions of all sizes are welcome.

## Getting set up

You need the Swift toolchain (Xcode or the Command Line Tools):

```sh
git clone <repo-url>
cd mac-resource-widget
./build.sh            # compiles and assembles MacResourceWidget.app
open MacResourceWidget.app
```

`./package.sh` additionally produces a distributable `MacResourceWidget.dmg`.

## Project layout

```
Sources/MacResourceWidget/
  App.swift          App entry, window setup, window level, context menu
  WidgetView.swift   SwiftUI views, the polling view-model, drag handling
  Stats.swift        System metric collectors (CPU, RAM, swap, disk, …)
  GPU.swift          GPU utilization via the IOAccelerator registry
  Settings.swift     Persisted preferences (UserDefaults-backed)
  Preferences.swift  The "Edit Widget" preferences window
Scripts/make_icon.swift   Generates the app icon
Resources/Info.plist      App bundle metadata
build.sh / package.sh     Build and packaging
docs/ROADMAP.md           Planned features
```

## Guidelines

- **No third-party dependencies.** The project is intentionally pure
  Swift + AppKit + SwiftUI. Please keep it that way.
- **Match the existing style** — standard Swift conventions, small focused
  types, comments only where the *why* isn't obvious.
- **Test on a real Mac.** There are no automated UI tests; build the app and
  verify your change behaves correctly, including edge cases (occlusion
  pausing, battery throttling, compact mode, etc.).
- Keep changes focused — one logical change per pull request.

## Submitting a pull request

1. Fork the repo and create a branch off `main`.
2. Make your change and confirm `./build.sh` succeeds with no warnings.
3. Open a PR describing **what** changed and **why**.

## Reporting bugs and requesting features

Use the issue templates. For bugs, please include your macOS version and Mac
model (Apple Silicon vs Intel) — several metrics, GPU especially, behave
differently across hardware.

Larger ideas are tracked in [`docs/ROADMAP.md`](docs/ROADMAP.md).

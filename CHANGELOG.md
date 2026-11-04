# Changelog

All notable changes to QuickOpen are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- English and Simplified Chinese interface. English by default unless the system language is Chinese; switch in Settings → General.

### Changed
- Overview (hold mode): removed "tap to keep open". Releasing the modifiers opens the selected app, or closes the panel if nothing is selected. Use toggle mode or the menu bar item to keep the panel open.

### Fixed
- Overview (hold mode): after releasing the modifiers the panel could freeze until the mouse moved, especially after pressing `Space` many times. Like `⌘Tab`, QuickOpen now briefly becomes the active app while the overview is shown, so the release arrives as a real key event and activation is handed directly to the chosen app (or back to the previous app if nothing was selected). The panel also closes instantly instead of fading out. `Space` presses still queued at release time are counted.
- App icons in the overview and launch hint could appear blank the first time they were shown.

## [1.3.0] - 2026-11-04

### Added
- New app icon: a stack of glass cards on an amber background.
- Liquid Glass UI on macOS 26 (`NSGlassEffectView`), with a frosted fallback on macOS 13–15.
- Template menu bar icon that matches the app icon.
- Automated releases: pushing a `v*` tag builds a universal `.dmg` / `.zip` and publishes a GitHub Release.

### Changed
- Restrained color palette: the accent color is used only for the recording field, the overview selection, recording hints and the logo; everything else is neutral or follows the system accent.

## [1.1.2] - 2026-10-30

### Fixed
- Keycaps are centered when the container is wider than the keys (e.g. single-key shortcuts in the launch hint).

## [1.1.1] - 2026-10-30

### Added
- Single-key shortcuts (e.g. `F5`). Keys that would block typing show a warning.

## [1.1.0] - 2026-10-30

### Added
- Shortcut overview panel (`⌃⌥Space`), with hold and toggle modes.
- Launch hint that briefly shows the app icon and its shortcut.
- Redesigned settings window with Shortcuts and General tabs, keycaps, drag-in apps and conflict checks.
- Launch at login, hide-on-repeat, drag to reorder.

### Fixed
- Recording no longer leaves all shortcuts disabled when the settings window loses focus.
- Running apps without windows now open a new window.
- A corrupted configuration file is backed up instead of being overwritten.
- Shortcuts that fail to register are reported.

## [1.0.0] - 2026-09-03

- Initial release.

[Unreleased]: https://github.com/simmzl/QuickOpen/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/simmzl/QuickOpen/releases/tag/v1.3.0

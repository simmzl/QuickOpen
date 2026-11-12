# Changelog

All notable changes to QuickOpen are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.4.2] - 2026-11-12

### Changed
- **Pointer cursor on everything clickable:** the Settings toolbar tabs, buttons, checkboxes, radio buttons, pop-up menus, sliders, switches and the keys in the keyboard view now show the pointing-hand cursor. Disabled controls keep the arrow.
- Settings → General → Appearance uses the same pill switch as List / Keyboard instead of the blue segmented control.
- Icons and labels in pill switches and the **Add App** button sit closer together and are optically centered, so Chinese and English text line up with the icon.
- README: refreshed settings screenshots.

## [1.4.1] - 2026-11-12

### Changed
- **Redesigned shortcut list.** Apps sit in a grouped list like System Settings, grouped by modifier combination and sorted by key (switch to *Custom Order* to drag rows). Shortcuts are shown as keycaps — click one to record a new shortcut. The bundle ID is replaced by a running / not running status (hover a row to see it), and Remove, Preview and Show in Finder move into a "⋯" menu that appears on hover.
- **Menu bar menu:** each app shows its shortcut as a keycap on the right, so you see — and remember — which key opens which app. Apps follow the same order as the settings list.
- New pill-style switches for List / Keyboard and By Key / Custom Order, a prominent **Add App** button, and roomier spacing in the Shortcuts tab.
- README: refreshed screenshots, plus a menu bar screenshot.

### Fixed
- Opening Settings or switching tabs no longer puts a focus ring on the first button or link.

## [1.4.0] - 2026-11-11

### Added
- **Keyboard view** for the Shortcuts tab: a sculpted Mac keyboard with each app's icon sitting right on the key that opens it.
  - Hover an app to lift its key and press down its modifiers; everything else dims. The hint reads in the order you press it: shortcut → Open → app.
  - A Dock below groups apps by modifier combination (single key, `⌥`, `⇧⌘`…). Hover a group to see only those keys, plus the keys macOS already uses and the ones still free; click to pin it, `Esc` to return.
  - Hold `⌃` `⌥` `⇧` `⌘` on the real keyboard to switch groups live. Click a free key to bind an app (or add a new one); drop apps onto the keyboard to add them.
  - Switch between the classic list (default) and the keyboard in the top-right corner; your choice is remembered.
- Appearance setting in Settings → General: follow the system, or always Light / Dark.
- About tab with version, author and links to the GitHub repository, releases and issues.

### Changed
- The Settings window is larger by default, resizable, and remembers its size and position. The window title is always "QuickOpen".
- README: a new keyboard hero image that follows GitHub's light/dark theme, and refreshed screenshots.

### Fixed
- Settings → General: content can scroll when the window is short, and the note under "Launch QuickOpen at login" is no longer clipped.
- `scripts/build-app.sh`: universal builds work with newer SwiftPM, which reuses one output directory for every architecture.

## [1.3.2] - 2026-11-04

### Changed
- Simpler app icon: two glass cards instead of three. The menu bar icon matches.
- README: added a demo video, and screenshots now use F1–F4 for Claude, ChatGPT, Chrome and Figma.

### Fixed
- Launch hint: short app names (e.g. "Figma") are no longer truncated.

## [1.3.1] - 2026-11-04

### Added
- Settings → General shows whether Input Monitoring is allowed for the overview's Hold mode, with a button to grant it.
- English and Simplified Chinese interface. English by default unless the system language is Chinese; switch in Settings → General.

### Changed
- Overview (hold mode): removed "tap to keep open". Releasing the modifiers opens the selected app, or closes the panel if nothing is selected. Use toggle mode or the menu bar item to keep the panel open.

### Fixed
- Overview (hold mode): after releasing the modifiers the panel could freeze until the mouse moved, especially after pressing `Space` many times. Hold mode now asks once for **Input Monitoring** and uses a listen-only event tap (modifier keys only, active only while the overview is visible) to detect the release reliably. Like `⌘Tab`, QuickOpen briefly becomes the active app while the overview is shown and hands activation to the chosen app (or back to the previous app if nothing was selected). The panel closes instantly instead of fading out.
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

[Unreleased]: https://github.com/simmzl/QuickOpen/compare/v1.4.2...HEAD
[1.4.2]: https://github.com/simmzl/QuickOpen/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/simmzl/QuickOpen/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/simmzl/QuickOpen/compare/v1.3.2...v1.4.0
[1.3.2]: https://github.com/simmzl/QuickOpen/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/simmzl/QuickOpen/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/simmzl/QuickOpen/releases/tag/v1.3.0

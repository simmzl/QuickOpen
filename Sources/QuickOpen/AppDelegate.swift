import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ShortcutStore()
    private let hotKeyManager = GlobalHotKeyManager()
    private let launcher = AppLauncher()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createStatusItem()
        _ = reloadHotKeysAndMenu()

        if store.shortcuts.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    @discardableResult
    private func reloadHotKeysAndMenu() -> [UUID: OSStatus] {
        hotKeyManager.unregisterAll()
        var failures: [UUID: OSStatus] = [:]

        for shortcut in store.shortcuts {
            guard let hotKey = shortcut.hotKey else { continue }
            let status = hotKeyManager.register(id: shortcut.id, hotKey: hotKey) { [weak self] in
                guard let self, let current = self.store.shortcut(id: shortcut.id) else { return }
                _ = self.launcher.activate(current)
            }
            if status != noErr { failures[shortcut.id] = status }
        }

        rebuildMenu()
        return failures
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "command.circle", accessibilityDescription: "QuickOpen")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "QuickOpen"
        }
        statusItem = item
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "快捷键设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !store.shortcuts.isEmpty {
            menu.addItem(.separator())
            for shortcut in store.shortcuts {
                let suffix = shortcut.hotKey.map { "    \($0.displayString)" } ?? "    未设置"
                let item = NSMenuItem(
                    title: shortcut.appName + suffix,
                    action: #selector(activateApplication(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = shortcut.id.uuidString
                let icon = NSWorkspace.shared.icon(forFile: shortcut.appPath)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 QuickOpen", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                store: store,
                hotKeyManager: hotKeyManager,
                onShortcutsChanged: { [weak self] in self?.reloadHotKeysAndMenu() ?? [:] }
            )
        }
        settingsWindowController?.present()
    }

    @objc private func activateApplication(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let shortcut = store.shortcut(id: id) else { return }
        _ = launcher.activate(shortcut)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

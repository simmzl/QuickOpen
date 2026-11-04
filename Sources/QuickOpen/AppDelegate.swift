import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ShortcutStore()
    private let preferences = Preferences()
    private let hotKeyManager = GlobalHotKeyManager()
    private let launcher = AppLauncher()
    private let hud = LaunchHUDController()
    private let overview = OverviewPanelController()
    private var statusItem: NSStatusItem?
    private lazy var settingsContext = SettingsContext(
        store: store,
        preferences: preferences,
        hotKeyManager: hotKeyManager,
        reloadHotKeys: { [weak self] in self?.reloadHotKeysAndMenu() ?? [:] },
        previewHUD: { [weak self] shortcut in self?.showHUD(for: shortcut, outcome: .activated, force: true) },
        isRunning: { [weak self] shortcut in self?.launcher.runningApplication(for: shortcut) != nil }
    )
    private var settingsWindowController: SettingsWindowController?
    /// 最近一次注册失败的快捷键（id → 错误码）。速查面板使用 `SettingsContext.overviewHotKeyID`。
    private var registrationFailures: [UUID: OSStatus] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launcher.hidesWhenFrontmost = preferences.hidesWhenFrontmost
        overview.onLaunch = { [weak self] shortcut in self?.launch(shortcut) }
        overview.isRunning = { [weak self] shortcut in self?.launcher.runningApplication(for: shortcut) != nil }
        overview.currentEventTime = { [weak self] in
            self?.hotKeyManager.currentEventTime ?? ProcessInfo.processInfo.systemUptime
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: .quickOpenPreferencesChanged, object: preferences
        )

        createStatusItem()
        reloadHotKeysAndMenu()

        if let backupURL = store.corruptedBackupURL {
            DispatchQueue.main.async { self.showCorruptedConfigurationAlert(backupURL) }
        }
        if store.shortcuts.isEmpty || !registrationFailures.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    /// 在访达中再次打开 QuickOpen 时显示设置窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: 热键

    @discardableResult
    private func reloadHotKeysAndMenu() -> [UUID: OSStatus] {
        hotKeyManager.unregisterAll()
        var failures: [UUID: OSStatus] = [:]

        for shortcut in store.shortcuts {
            guard let hotKey = shortcut.hotKey else { continue }
            let status = hotKeyManager.register(id: shortcut.id, hotKey: hotKey) { [weak self] in
                guard let self, let current = self.store.shortcut(id: shortcut.id) else { return }
                self.launch(current)
            }
            if status != noErr { failures[shortcut.id] = status }
        }

        if let overviewHotKey = preferences.overviewHotKey {
            let status = hotKeyManager.register(
                id: SettingsContext.overviewHotKeyID,
                hotKey: overviewHotKey,
                onRelease: { [weak self] in self?.overview.hotKeyReleased() },
                action: { [weak self] in self?.overviewHotKeyPressed(overviewHotKey) }
            )
            if status != noErr { failures[SettingsContext.overviewHotKeyID] = status }
        }

        registrationFailures = failures
        settingsContext.updateFailures(failures)
        rebuildMenu()
        return failures
    }

    private func overviewHotKeyPressed(_ hotKey: HotKey) {
        if !overview.isVisible { hud.dismiss() }
        overview.hotKeyPressed(shortcuts: store.shortcuts, hotKey: hotKey, mode: preferences.overviewMode)
    }

    /// 通过快捷键、菜单或速查面板打开 App。
    private func launch(_ shortcut: AppShortcut) {
        if overview.isVisible { overview.dismiss() }
        let outcome = launcher.activate(shortcut)
        if outcome != .missing { showHUD(for: shortcut, outcome: outcome, force: false) }
    }

    private func showHUD(for shortcut: AppShortcut, outcome: LaunchOutcome, force: Bool) {
        guard force || preferences.showsLaunchHUD else { return }
        hud.show(
            shortcut,
            outcome: outcome,
            position: preferences.hudPosition,
            duration: preferences.hudDuration
        )
    }

    @objc private func preferencesChanged() {
        launcher.hidesWhenFrontmost = preferences.hidesWhenFrontmost
        // 速查面板快捷键的重新注册由录制流程（SettingsContext）负责，这里只刷新菜单。
        rebuildMenu()
    }

    // MARK: 菜单栏

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusBarIcon.make()
            button.toolTip = "QuickOpen"
        }
        statusItem = item
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let overviewItem = NSMenuItem(title: "显示速查面板", action: #selector(showOverviewFromMenu), keyEquivalent: "")
        overviewItem.target = self
        overviewItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        if registrationFailures[SettingsContext.overviewHotKeyID] == nil {
            Self.applyKeyEquivalent(preferences.overviewHotKey, to: overviewItem)
        }
        menu.addItem(overviewItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        if !registrationFailures.isEmpty {
            let warning = NSMenuItem(
                title: "\(registrationFailures.count) 个快捷键被占用，点此处理",
                action: #selector(showSettings),
                keyEquivalent: ""
            )
            warning.target = self
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
            menu.addItem(warning)
        }

        if !store.shortcuts.isEmpty {
            menu.addItem(.separator())
            if #available(macOS 14.0, *) {
                menu.addItem(NSMenuItem.sectionHeader(title: "App"))
            }
            for shortcut in store.shortcuts {
                let item = NSMenuItem(
                    title: shortcut.appName,
                    action: #selector(activateApplication(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = shortcut.id.uuidString
                let icon = NSWorkspace.shared.icon(forFile: shortcut.appPath)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                if registrationFailures[shortcut.id] != nil {
                    item.title = "\(shortcut.appName)（快捷键被占用）"
                } else {
                    // 使用系统菜单的右对齐快捷键样式展示。
                    Self.applyKeyEquivalent(shortcut.hotKey, to: item)
                }
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

    /// 把 HotKey 显示为菜单项右侧的系统快捷键样式。
    private static func applyKeyEquivalent(_ hotKey: HotKey?, to item: NSMenuItem) {
        guard let hotKey, let character = keyEquivalentCharacter(for: hotKey.keyCode) else { return }
        item.keyEquivalent = character
        item.keyEquivalentModifierMask = hotKey.modifierFlags
    }

    private static func keyEquivalentCharacter(for keyCode: UInt32) -> String? {
        let special: [UInt32: Int] = [
            36: 0x0D, 48: 0x09, 49: 0x20, 51: 0x08, 53: 0x1B, 117: 0x7F,
            123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey,
            125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey,
            115: NSHomeFunctionKey, 119: NSEndFunctionKey,
            116: NSPageUpFunctionKey, 121: NSPageDownFunctionKey,
            122: NSF1FunctionKey, 120: NSF2FunctionKey, 99: NSF3FunctionKey, 118: NSF4FunctionKey,
            96: NSF5FunctionKey, 97: NSF6FunctionKey, 98: NSF7FunctionKey, 100: NSF8FunctionKey,
            101: NSF9FunctionKey, 109: NSF10FunctionKey, 103: NSF11FunctionKey, 111: NSF12FunctionKey,
            105: NSF13FunctionKey, 107: NSF14FunctionKey, 113: NSF15FunctionKey, 106: NSF16FunctionKey,
            64: NSF17FunctionKey, 79: NSF18FunctionKey, 80: NSF19FunctionKey, 90: NSF20FunctionKey
        ]
        if let scalar = special[keyCode].flatMap({ UnicodeScalar($0) }) {
            return String(Character(scalar))
        }
        let name = HotKeyFormatter.keyName(for: keyCode)
        return name.count == 1 ? name.lowercased() : nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        hud.dismiss()
    }

    // MARK: 动作

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(context: settingsContext)
            controller.onShowOverview = { [weak self] in self?.showOverviewFromMenu() }
            settingsWindowController = controller
        }
        settingsWindowController?.present()
    }

    @objc private func showOverviewFromMenu() {
        hud.dismiss()
        // 从菜单打开时修饰键没有按住，始终使用切换模式。延后一拍，等菜单收起。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overview.show(shortcuts: self.store.shortcuts, mode: .toggle, triggerHotKey: nil)
        }
    }

    @objc private func activateApplication(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let shortcut = store.shortcut(id: id) else { return }
        launch(shortcut)
    }

    private func showCorruptedConfigurationAlert(_ backupURL: URL) {
        let alert = NSAlert()
        alert.messageText = "快捷键配置文件无法读取"
        alert.informativeText = "原文件已备份为 \(backupURL.lastPathComponent)，QuickOpen 将以空配置启动。"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "在访达中显示")
        alert.alertStyle = .warning
        AppLauncher.activateSelf()
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([backupURL])
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

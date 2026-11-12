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
    /// 全局快捷键工具需要随时即时响应：关闭 App Nap，避免热键回调和定时器被系统推迟。
    /// App 平时只在 runloop 中空闲等待，不会增加耗电。
    private var noNapActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        noNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "QuickOpen responds to global shortcuts"
        )
        NSApp.appearance = preferences.appearanceMode.appearance
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
        // “按住显示”需要输入监控权限才能可靠检测松开；首次使用时请求一次。
        if preferences.overviewMode == .hold, !hotKey.modifierFlags.isEmpty {
            InputMonitoring.requestOnceIfNeeded()
        }
        overview.hotKeyPressed(shortcuts: store.shortcuts, hotKey: hotKey, mode: preferences.overviewMode)
    }

    /// 通过快捷键、菜单或速查面板打开 App。
    private func launch(_ shortcut: AppShortcut) {
        if overview.isVisible { overview.dismissForLaunch() }
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
        let appearance = preferences.appearanceMode.appearance
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
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
        // 与设置页一致：按键位时按修饰键分组、组内按键位排序；自定义顺序时保持用户顺序。
        let ordered = preferences.shortcutsListOrder == .custom ? store.shortcuts
            : ShortcutListBuilder.items(for: store.shortcuts, order: .byKey).compactMap { item -> AppShortcut? in
                if case .app(let id) = item { return store.shortcut(id: id) } else { return nil }
            }
        let overviewTitle = L("Show Overview", "显示速查面板")
        let overviewKey = registrationFailures[SettingsContext.overviewHotKeyID] == nil ? preferences.overviewHotKey : nil
        let width = max(250, ([MenuShortcutItemView.preferredWidth(title: overviewTitle, hotKey: overviewKey)]
            + ordered.map { MenuShortcutItemView.preferredWidth(title: $0.appName, hotKey: $0.hotKey) }).max() ?? 0)

        let overviewItem = NSMenuItem(title: overviewTitle, action: #selector(showOverviewFromMenu), keyEquivalent: "")
        overviewItem.target = self
        let gridIcon = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        gridIcon?.isTemplate = true
        overviewItem.view = MenuShortcutItemView(title: overviewTitle, icon: gridIcon, hotKey: overviewKey,
                                                 unavailable: false, width: width) { [weak self] in self?.showOverviewFromMenu() }
        menu.addItem(overviewItem)

        let settingsItem = NSMenuItem(title: L("Settings…", "设置…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        if !registrationFailures.isEmpty {
            let warning = NSMenuItem(
                title: L("\(registrationFailures.count) shortcut(s) unavailable — click to fix", "\(registrationFailures.count) 个快捷键被占用，点此处理"),
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
            for shortcut in ordered {
                let item = NSMenuItem(title: shortcut.appName, action: #selector(activateApplication(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = shortcut.id.uuidString
                let id = shortcut.id
                let unavailable = registrationFailures[shortcut.id] != nil
                item.view = MenuShortcutItemView(
                    title: unavailable ? L("\(shortcut.appName) (shortcut unavailable)", "\(shortcut.appName)（快捷键被占用）") : shortcut.appName,
                    icon: AppIcons.icon(forPath: shortcut.appPath, size: 18),
                    hotKey: shortcut.hotKey, unavailable: unavailable, width: width
                ) { [weak self] in
                    guard let self, let current = self.store.shortcut(id: id) else { return }
                    self.launch(current)
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("Quit QuickOpen", "退出 QuickOpen"), action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
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
        alert.messageText = L("Couldn’t read the shortcuts file", "快捷键配置文件无法读取")
        alert.informativeText = L("The original file was backed up as \(backupURL.lastPathComponent). QuickOpen will start with an empty list.", "原文件已备份为 \(backupURL.lastPathComponent)，QuickOpen 将以空配置启动。")
        alert.addButton(withTitle: L("OK", "好"))
        alert.addButton(withTitle: L("Show in Finder", "在访达中显示"))
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

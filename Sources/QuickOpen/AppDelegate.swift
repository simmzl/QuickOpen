import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ShortcutStore()
    private let preferences = Preferences()
    private let hotKeyManager = GlobalHotKeyManager()
    private let launcher = AppLauncher()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    /// 最近一次注册失败的快捷键（id → 错误码）。
    private var registrationFailures: [UUID: OSStatus] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launcher.hidesWhenFrontmost = preferences.hidesWhenFrontmost
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

    @discardableResult
    private func reloadHotKeysAndMenu() -> [UUID: OSStatus] {
        hotKeyManager.unregisterAll()
        var failures: [UUID: OSStatus] = [:]

        for shortcut in store.shortcuts {
            guard let hotKey = shortcut.hotKey else { continue }
            let status = hotKeyManager.register(id: shortcut.id, hotKey: hotKey) { [weak self] in
                guard let self, let current = self.store.shortcut(id: shortcut.id) else { return }
                self.launcher.activate(current)
            }
            if status != noErr { failures[shortcut.id] = status }
        }

        registrationFailures = failures
        settingsWindowController?.registrationFailures = failures
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

        if !registrationFailures.isEmpty {
            let warning = NSMenuItem(
                title: "⚠︎ \(registrationFailures.count) 个快捷键被占用，点此处理",
                action: #selector(showSettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
        }

        if !store.shortcuts.isEmpty {
            menu.addItem(.separator())
            for shortcut in store.shortcuts {
                let suffix: String
                if registrationFailures[shortcut.id] != nil {
                    suffix = "    ⚠︎ 被占用"
                } else {
                    suffix = shortcut.hotKey.map { "    \($0.displayString)" } ?? "    未设置"
                }
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
        let hideItem = NSMenuItem(
            title: "再按一次快捷键隐藏 App",
            action: #selector(toggleHidesWhenFrontmost(_:)),
            keyEquivalent: ""
        )
        hideItem.target = self
        hideItem.state = preferences.hidesWhenFrontmost ? .on : .off
        menu.addItem(hideItem)

        let loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : (LoginItem.requiresApproval ? .mixed : .off)
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 QuickOpen", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController(
                store: store,
                hotKeyManager: hotKeyManager,
                onShortcutsChanged: { [weak self] in self?.reloadHotKeysAndMenu() ?? [:] }
            )
            controller.registrationFailures = registrationFailures
            settingsWindowController = controller
        }
        settingsWindowController?.present()
    }

    @objc private func activateApplication(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let id = UUID(uuidString: rawID),
              let shortcut = store.shortcut(id: id) else { return }
        launcher.activate(shortcut)
    }

    @objc private func toggleHidesWhenFrontmost(_ sender: NSMenuItem) {
        preferences.hidesWhenFrontmost.toggle()
        launcher.hidesWhenFrontmost = preferences.hidesWhenFrontmost
        rebuildMenu()
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更改登录项"
            alert.informativeText = error.localizedDescription
                + "\n\n请确认 QuickOpen 位于“应用程序”文件夹中。"
            alert.alertStyle = .warning
            AppLauncher.activateSelf()
            alert.runModal()
        }
        if LoginItem.requiresApproval {
            LoginItem.openSystemSettings()
        }
        rebuildMenu()
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

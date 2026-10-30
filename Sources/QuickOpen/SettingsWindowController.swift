import AppKit
import Carbon
import UniformTypeIdentifiers

private final class AppCellView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let pathLabel = NSTextField(labelWithString: "")
    let appIconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        appIconView.imageScaling = .scaleProportionallyUpOrDown

        [nameLabel, pathLabel, appIconView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            appIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            appIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            appIconView.widthAnchor.constraint(equalToConstant: 30),
            appIconView.heightAnchor.constraint(equalToConstant: 30),
            nameLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pathLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class ShortcutButton: NSButton {
    var shortcutID: UUID?
}

private final class DeleteButton: NSButton {
    var shortcutID: UUID?
}

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: ShortcutStore
    private let hotKeyManager: GlobalHotKeyManager
    private let onShortcutsChanged: () -> [UUID: OSStatus]

    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "还没有添加 App\n点击下方按钮开始设置")
    private let hintLabel = NSTextField(labelWithString: "快捷键至少需要包含 ⌘、⌥、⌃ 或 ⇧ 中的一个")
    private var recordingID: UUID?
    private var recordingMonitor: Any?

    init(
        store: ShortcutStore,
        hotKeyManager: GlobalHotKeyManager,
        onShortcutsChanged: @escaping () -> [UUID: OSStatus]
    ) {
        self.store = store
        self.hotKeyManager = hotKeyManager
        self.onShortcutsChanged = onShortcutsChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickOpen 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 560, height: 380)

        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        tableView.reloadData()
        updateEmptyState()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store.shortcuts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard store.shortcuts.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let shortcut = store.shortcuts[row]

        switch identifier.rawValue {
        case "application":
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AppCellView
                ?? AppCellView(frame: .zero)
            cell.identifier = identifier
            cell.nameLabel.stringValue = shortcut.appName
            cell.pathLabel.stringValue = shortcut.bundleIdentifier ?? shortcut.appPath
            cell.appIconView.image = NSWorkspace.shared.icon(forFile: shortcut.appPath)
            return cell

        case "hotkey":
            let button = tableView.makeView(withIdentifier: identifier, owner: self) as? ShortcutButton
                ?? ShortcutButton(title: "", target: self, action: #selector(recordShortcut(_:)))
            button.identifier = identifier
            button.target = self
            button.action = #selector(recordShortcut(_:))
            button.shortcutID = shortcut.id
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            if recordingID == shortcut.id {
                button.title = "请按快捷键…"
            } else {
                button.title = shortcut.hotKey?.displayString ?? "录制"
            }
            return button

        case "delete":
            let deleteImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
                ?? NSImage(size: NSSize(width: 16, height: 16))
            let button = tableView.makeView(withIdentifier: identifier, owner: self) as? DeleteButton
                ?? DeleteButton(
                    image: deleteImage,
                    target: self,
                    action: #selector(deleteShortcut(_:))
                )
            button.identifier = identifier
            button.target = self
            button.action = #selector(deleteShortcut(_:))
            button.shortcutID = shortcut.id
            button.bezelStyle = .inline
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = "删除 \(shortcut.appName)"
            return button

        default:
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        finishRecording(shouldReregister: true)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "App 快捷键")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: "按下全局快捷键，让目标 App 立即来到前台；未运行时会自动启动。")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        let applicationColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("application"))
        applicationColumn.title = "App"
        applicationColumn.minWidth = 260
        applicationColumn.resizingMask = .autoresizingMask
        let hotKeyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hotkey"))
        hotKeyColumn.title = "快捷键"
        hotKeyColumn.width = 150
        hotKeyColumn.minWidth = 130
        hotKeyColumn.maxWidth = 180
        hotKeyColumn.resizingMask = .userResizingMask
        let deleteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("delete"))
        deleteColumn.title = ""
        deleteColumn.width = 42
        deleteColumn.minWidth = 42
        deleteColumn.maxWidth = 42
        deleteColumn.resizingMask = []

        [applicationColumn, hotKeyColumn, deleteColumn].forEach(tableView.addTableColumn)
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.borderType = .bezelBorder

        let addButton = NSButton(title: "添加 App…", target: self, action: #selector(addApplication))
        addButton.bezelStyle = .rounded
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail

        let spacer = NSView()
        let footer = NSStackView(views: [addButton, spacer, hintLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.maximumNumberOfLines = 2

        [header, scrollView, footer, emptyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        updateEmptyState()
    }

    @objc private func addApplication() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要绑定快捷键的 App"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            let addedIDs = self.store.addApplications(at: panel.urls)
            self.tableView.reloadData()
            self.updateEmptyState()
            _ = self.onShortcutsChanged()

            if addedIDs.count == 1 {
                self.beginRecording(id: addedIDs[0])
            } else if addedIDs.isEmpty, !panel.urls.isEmpty {
                self.showAlert(message: "没有添加新 App", detail: "所选 App 已经在列表中。")
            }
        }
    }

    @objc private func recordShortcut(_ sender: ShortcutButton) {
        guard let id = sender.shortcutID else { return }
        beginRecording(id: id)
    }

    @objc private func deleteShortcut(_ sender: DeleteButton) {
        guard let id = sender.shortcutID else { return }
        if recordingID == id { finishRecording(shouldReregister: false) }
        store.remove(id: id)
        tableView.reloadData()
        updateEmptyState()
        _ = onShortcutsChanged()
    }

    private func beginRecording(id: UUID) {
        if recordingID != nil { finishRecording(shouldReregister: false) }
        recordingID = id
        hotKeyManager.unregisterAll()
        hintLabel.stringValue = "按下新快捷键 · Esc 取消 · Delete 清除"
        hintLabel.textColor = .controlAccentColor
        tableView.reloadData()

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent) {
        guard let id = recordingID else { return }

        if event.keyCode == 53 {
            finishRecording(shouldReregister: true)
            return
        }

        let carbonModifiers = HotKey.carbonModifiers(from: event.modifierFlags)
        if (event.keyCode == 51 || event.keyCode == 117), carbonModifiers == 0 {
            finishRecording(shouldReregister: false)
            store.updateHotKey(nil, for: id)
            _ = onShortcutsChanged()
            return
        }

        guard carbonModifiers != 0 else {
            NSSound.beep()
            hintLabel.stringValue = "请同时按住 ⌘、⌥、⌃ 或 ⇧ 中的至少一个"
            return
        }

        let hotKey = HotKey(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        guard !store.uses(hotKey, excluding: id) else {
            NSSound.beep()
            hintLabel.stringValue = "这个快捷键已经分配给列表中的其他 App"
            return
        }

        let previousHotKey = store.shortcut(id: id)?.hotKey
        finishRecording(shouldReregister: false)
        store.updateHotKey(hotKey, for: id)
        let failures = onShortcutsChanged()

        if let status = failures[id] {
            store.updateHotKey(previousHotKey, for: id)
            _ = onShortcutsChanged()
            let detail = status == eventHotKeyExistsErr
                ? "该快捷键已被系统或其他应用占用，请换一个。"
                : "系统无法注册该快捷键（错误码 \(status)）。"
            showAlert(message: "快捷键不可用", detail: detail)
        }
        tableView.reloadData()
    }

    private func finishRecording(shouldReregister: Bool) {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        recordingID = nil
        hintLabel.stringValue = "快捷键至少需要包含 ⌘、⌥、⌃ 或 ⇧ 中的一个"
        hintLabel.textColor = .secondaryLabelColor
        tableView.reloadData()
        if shouldReregister { _ = onShortcutsChanged() }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !store.shortcuts.isEmpty
    }

    private func showAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }
}

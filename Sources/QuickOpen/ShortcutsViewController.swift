import AppKit
import UniformTypeIdentifiers

/// 设置窗口「快捷键」页：App 列表、录制、拖拽排序、拖入 .app 添加。
final class ShortcutsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let context: SettingsContext
    private let tableView = ShortcutTableView()
    private let scrollView = NSScrollView()
    private let emptyView = EmptyStateView()
    private let hintLabel = NSTextField(labelWithString: "")
    private static let rowDragType = NSPasteboard.PasteboardType("com.simmzl.quickopen.row")
    private static var defaultHint: String { L("Single keys or combinations · Drag to reorder · Drop apps here to add", "支持单键或组合键 · 拖动可排序 · 可把 App 直接拖进来") }

    init(context: SettingsContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        title = L("Shortcuts", "快捷键")
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = SettingsBackdrop(frame: NSRect(x: 0, y: 0, width: 660, height: 480))
        view = root
        buildInterface()
        context.onChange.append { [weak self] in self?.refresh() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(runningApplicationsChanged),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(runningApplicationsChanged),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refresh() {
        tableView.reloadData()
        let isEmpty = context.store.shortcuts.isEmpty
        emptyView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
        if context.recordingTarget == nil || context.recordingTarget == SettingsContext.overviewHotKeyID {
            setHint(Self.defaultHint, highlighted: false)
        }
    }

    @objc private func runningApplicationsChanged() {
        guard view.window?.isVisible == true else { return }
        tableView.reloadData()
    }

    // MARK: 界面

    private func buildInterface() {
        let titleLabel = NSTextField(labelWithString: L("App Shortcuts", "App 快捷键"))
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: L("Press a shortcut to bring its app to the front, or launch it if it isn’t running.", "按下快捷键，目标 App 立即来到前台；未运行时自动启动。"))
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 60
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if #available(macOS 11.0, *) { tableView.style = .plain }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.rowDragType, .fileURL])
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.onDeleteKey = { [weak self] row in self?.confirmDelete(row: row) }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        emptyView.onAdd = { [weak self] in self?.addApplication() }
        emptyView.onDropApplications = { [weak self] urls in self?.add(urls) }

        let addButton = NSButton(title: L("Add App…", "添加 App…"), target: self, action: #selector(addApplication))
        addButton.applyGlassStyle()
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        addButton.imagePosition = .imageLeading
        addButton.keyEquivalent = "n"
        addButton.keyEquivalentModifierMask = [.command]

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [addButton, hintLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        [header, scrollView, emptyView, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            emptyView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            emptyView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18)
        ])
        setHint(Self.defaultHint, highlighted: false)
    }

    private func setHint(_ text: String, highlighted: Bool) {
        hintLabel.stringValue = text
        hintLabel.textColor = highlighted ? Theme.accentText : .secondaryLabelColor
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        context.store.shortcuts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard context.store.shortcuts.indices.contains(row) else { return nil }
        let shortcut = context.store.shortcuts[row]
        let identifier = NSUserInterfaceItemIdentifier("ShortcutRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ShortcutRowView
            ?? ShortcutRowView()
        cell.identifier = identifier
        cell.configure(
            shortcut: shortcut,
            isRunning: isRunning(shortcut),
            isRecording: context.recordingTarget == shortcut.id,
            failure: context.registrationFailures[shortcut.id]
        )
        cell.onRecord = { [weak self] in self?.beginRecording(id: shortcut.id) }
        cell.onDelete = { [weak self] in
            guard let self, let index = self.context.store.shortcuts.firstIndex(where: { $0.id == shortcut.id })
            else { return }
            self.confirmDelete(row: index)
        }
        cell.onPreview = { [weak self] in self?.context.previewHUD(shortcut) }
        cell.onReveal = {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: shortcut.appPath)])
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CardRowView()
    }

    private func isRunning(_ shortcut: AppShortcut) -> Bool {
        context.isRunning(shortcut)
    }

    // MARK: 拖拽：行内排序 + 从访达拖入 .app

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard context.recordingTarget == nil else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowDragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        if info.draggingSource as? NSTableView === tableView {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        guard !Self.applicationURLs(from: info.draggingPasteboard).isEmpty else { return [] }
        tableView.setDropRow(-1, dropOperation: .on) // 高亮整个列表
        return .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        if info.draggingSource as? NSTableView === tableView {
            guard let raw = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.rowDragType),
                  let source = Int(raw) else { return false }
            context.store.move(from: source, to: row)
            context.reload()
            return true
        }
        let urls = Self.applicationURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        add(urls)
        return true
    }

    static func applicationURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter { $0.pathExtension.lowercased() == "app" }
    }

    // MARK: 操作

    @objc func addApplication() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = L("Choose apps to assign shortcuts to", "选择要绑定快捷键的 App")
        panel.prompt = L("Add", "添加")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.add(panel.urls)
        }
    }

    private func add(_ urls: [URL]) {
        let addedIDs = context.store.addApplications(at: urls)
        context.reload()
        if addedIDs.count == 1 {
            if let row = context.store.shortcuts.firstIndex(where: { $0.id == addedIDs[0] }) {
                tableView.scrollRowToVisible(row)
            }
            beginRecording(id: addedIDs[0])
        } else if addedIDs.isEmpty, !urls.isEmpty {
            SettingsContext.showAlert(message: L("No new apps added", "没有添加新 App"), detail: L("The selected apps are already in the list.", "所选 App 已经在列表中。"), window: view.window)
        }
    }

    private func confirmDelete(row: Int) {
        guard context.store.shortcuts.indices.contains(row) else { return }
        let shortcut = context.store.shortcuts[row]
        if context.recordingTarget == shortcut.id { context.cancelRecording() }
        context.store.remove(id: shortcut.id)
        context.reload()
    }

    private func beginRecording(id: UUID) {
        setHint(L("Press a new shortcut · Esc to cancel · Delete to clear", "按下新快捷键 · Esc 取消 · Delete 清除"), highlighted: true)
        let previous = context.store.shortcut(id: id)?.hotKey
        context.beginRecording(
            target: id,
            onHint: { [weak self] message in self?.setHint(message, highlighted: true) },
            apply: { [weak self] hotKey in self?.context.store.updateHotKey(hotKey, for: id) },
            revert: { [weak self] in self?.context.store.updateHotKey(previous, for: id) },
            window: view.window
        )
    }
}

// MARK: - 行视图

/// 玻璃卡片背景的行。
private final class CardRowView: NSTableRowView {
    private let card = GlassSurface(kind: .card, cornerRadius: 14)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        card.translatesAutoresizingMaskIntoConstraints = true
        addSubview(card, positioned: .below, relativeTo: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        card.frame = bounds.insetBy(dx: 6, dy: 0)
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        // 单元格视图总是在玻璃卡片之上（用 frame 布局，重新插入不会丢约束）。
        if subview !== card, subviews.first !== card, card.superview === self {
            addSubview(card, positioned: .below, relativeTo: nil)
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
    override var isEmphasized: Bool { get { false } set {} }
}

private final class ShortcutRowView: NSTableCellView {
    var onRecord: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?
    var onReveal: (() -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    /// 中性的“运行中”小圆点。
    private let runningBadge = DotView()
    private let hotKeyControl = HotKeyControl()
    private let deleteButton = NSButton()
    private var hoverArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle

        runningBadge.wantsLayer = true
        runningBadge.toolTip = L("Running", "正在运行")
        runningBadge.setAccessibilityLabel(L("Running", "正在运行"))
        runningBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            runningBadge.widthAnchor.constraint(equalToConstant: 6),
            runningBadge.heightAnchor.constraint(equalToConstant: 6)
        ])

        let nameRow = NSStackView(views: [nameLabel, runningBadge])
        nameRow.orientation = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .centerY
        let texts = NSStackView(views: [nameRow, detailLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        hotKeyControl.target = self
        hotKeyControl.action = #selector(record)

        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: L("Remove", "删除"))
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(delete)
        deleteButton.alphaValue = 0.45

        [iconView, texts, hotKeyControl, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            texts.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: hotKeyControl.leadingAnchor, constant: -12),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            hotKeyControl.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -10),
            hotKeyControl.widthAnchor.constraint(equalToConstant: 172),
            hotKeyControl.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        menu = makeContextMenu()
    }

    required init?(coder: NSCoder) { nil }

    func configure(shortcut: AppShortcut, isRunning: Bool, isRecording: Bool, failure: OSStatus?) {
        iconView.image = AppIcons.icon(forPath: shortcut.appPath, size: 36)
        nameLabel.stringValue = shortcut.appName
        runningBadge.isHidden = !isRunning
        deleteButton.toolTip = L("Remove \(shortcut.appName)", "删除 \(shortcut.appName)")

        hotKeyControl.hotKey = shortcut.hotKey
        hotKeyControl.isRecording = isRecording
        hotKeyControl.isWarning = failure != nil
        if let failure {
            detailLabel.stringValue = "⚠︎ " + failure.hotKeyFailureDescription
            detailLabel.textColor = .systemRed
            hotKeyControl.toolTip = L("Click to record again", "点击重新录制")
        } else {
            if let warning = shortcut.hotKey?.typingWarning {
                detailLabel.stringValue = "⚠︎ " + warning
                detailLabel.textColor = .systemOrange
            } else {
                detailLabel.stringValue = shortcut.bundleIdentifier ?? shortcut.appPath
                detailLabel.textColor = .secondaryLabelColor
            }
            hotKeyControl.toolTip = shortcut.hotKey == nil ? L("Click to record a shortcut", "点击录制快捷键") : L("Click to change the shortcut", "点击修改快捷键")
        }
        if !FileManager.default.fileExists(atPath: shortcut.appPath),
           shortcut.bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) == nil {
            detailLabel.stringValue = L("⚠︎ App not found — it may have been moved or uninstalled", "⚠︎ 找不到此 App，可能已被移动或卸载")
            detailLabel.textColor = .systemOrange
            iconView.alphaValue = 0.5
        } else {
            iconView.alphaValue = 1
        }
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Record Shortcut", "录制快捷键"), action: #selector(record), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Preview Launch Hint", "预览启动提示"), action: #selector(preview), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("Show in Finder", "在访达中显示"), action: #selector(reveal), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Remove", "删除"), action: #selector(delete), keyEquivalent: "").target = self
        return menu
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { deleteButton.animator().alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { deleteButton.animator().alphaValue = 0.45 }

    @objc private func record() { onRecord?() }
    @objc private func delete() { onDelete?() }
    @objc private func preview() { onPreview?() }
    @objc private func reveal() { onReveal?() }
}

/// 支持 Delete 键删除当前行的表格。
private final class ShortcutTableView: NSTableView {
    var onDeleteKey: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), selectedRow >= 0 {
            onDeleteKey?(selectedRow)
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - 空状态

private final class EmptyStateView: NSView {
    var onAdd: (() -> Void)?
    var onDropApplications: (([URL]) -> Void)?
    private var isDropTarget = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])

        let symbol = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .light)
        symbol.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        symbol.contentTintColor = .tertiaryLabelColor

        let title = NSTextField(labelWithString: L("No apps yet", "还没有添加 App"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let detail = NSTextField(labelWithString: L("Drag apps here from Finder or Applications,\nor choose them with the button below.", "把 App 从访达或“应用程序”拖到这里，\n或点击下方按钮选择。"))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 2

        let button = NSButton(title: L("Choose Apps…", "选择 App…"), target: self, action: #selector(add))
        button.applyGlassStyle()
        button.controlSize = .large
        button.keyEquivalent = "\r"

        let stack = NSStackView(views: [symbol, title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func add() { onAdd?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.lineWidth = isDropTarget ? 2 : 1
        (isDropTarget ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        if isDropTarget {
            NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
            path.fill()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = !ShortcutsViewController.applicationURLs(from: sender.draggingPasteboard).isEmpty
        isDropTarget = ok
        return ok ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isDropTarget = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        let urls = ShortcutsViewController.applicationURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDropApplications?(urls)
        return true
    }
}

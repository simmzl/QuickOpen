import AppKit
import UniformTypeIdentifiers

/// 设置窗口「快捷键」页：App 列表、录制、拖拽排序、拖入 .app 添加。
final class ShortcutsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let context: SettingsContext
    private let tableView = ShortcutTableView()
    private let scrollView = NSScrollView()
    private let emptyView = EmptyStateView()
    private let hintLabel = NSTextField(labelWithString: "")
    private let keyboardView = KeyboardMapView()
    private let styleControl = PillSegmentedControl()
    private let orderControl = PillSegmentedControl()
    private let countLabel = NSTextField(labelWithString: "")
    private var subbar: NSStackView!
    /// 列表当前显示的行（分组标题 + App）。
    private var items: [ShortcutListItem] = []
    /// 鼠标所在的行，用于行背景高亮。
    private var hoveredRow: Int?
    /// 在键盘视图里点空闲键后「添加 App…」：添加完成后直接绑定到这个快捷键。
    private var pendingAssignHotKey: HotKey?
    private static let rowDragType = NSPasteboard.PasteboardType("com.simmzl.quickopen.row")
    private static var defaultHint: String { L("Click a keycap to change it · Hover for more · Drop apps here to add", "点击键帽修改快捷键 · 悬停显示更多操作 · 可把 App 直接拖进来") }
    private static var keyboardHint: String { L("Hover to preview · Click a key to assign · Hold ⌃⌥⇧⌘ to switch groups", "悬停查看 · 点击键帽绑定 · 按住 ⌃⌥⇧⌘ 切换分组 · 可把 App 拖进来") }
    private var idleHint: String { style == .keyboard ? Self.keyboardHint : Self.defaultHint }

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

    private var style: ShortcutsViewStyle { context.preferences.shortcutsViewStyle }

    private var order: ShortcutsListOrder { context.preferences.shortcutsListOrder }

    func refresh() {
        items = ShortcutListBuilder.items(for: context.store.shortcuts, order: order)
        tableView.reloadData()
        let isEmpty = context.store.shortcuts.isEmpty
        let keyboard = style == .keyboard
        emptyView.isHidden = !isEmpty || keyboard
        scrollView.isHidden = isEmpty || keyboard
        subbar.isHidden = isEmpty || keyboard
        orderControl.selectedIndex = order == .byKey ? 0 : 1
        countLabel.stringValue = Self.countText(context.store.shortcuts)
        keyboardView.isHidden = !keyboard
        styleControl.selectedIndex = keyboard ? 1 : 0
        keyboardView.shortcuts = context.store.shortcuts
        keyboardView.overviewHotKey = context.preferences.overviewHotKey
        keyboardView.failures = context.registrationFailures
        keyboardView.recordingTarget = context.recordingTarget
        if context.recordingTarget == nil || context.recordingTarget == SettingsContext.overviewHotKeyID {
            setHint(idleHint, highlighted: false)
        }
    }

    /// “8 个 App · 6 个单键，1 组组合键”
    static func countText(_ shortcuts: [AppShortcut]) -> String {
        let bound = shortcuts.filter { $0.hotKey != nil }
        let singles = bound.filter { $0.hotKey!.modifiers == 0 }.count
        let combos = Set(bound.compactMap { $0.hotKey!.modifiers == 0 ? nil : $0.hotKey!.modifiers }).count
        let unset = shortcuts.count - bound.count
        var text = L("\(shortcuts.count) apps", "\(shortcuts.count) 个 App")
        if combos == 0, unset == 0 {
            text += L(" · all on single keys", " · 全部为单键")
        } else {
            text += L(" · \(singles) single keys, \(combos) modifier combination\(combos == 1 ? "" : "s")",
                      " · \(singles) 个单键，\(combos) 组组合键")
            if unset > 0 { text += L(" · \(unset) not set", " · \(unset) 个未设置") }
        }
        return text
    }

    @objc private func runningApplicationsChanged() {
        guard view.window?.isVisible == true else { return }
        tableView.reloadData()
    }

    // MARK: 界面

    private func buildInterface() {
        let titleLabel = NSTextField(labelWithString: L("App Shortcuts", "App 快捷键"))
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        let subtitleLabel = NSTextField(labelWithString: L("Press a shortcut to bring its app to the front, or launch it if it isn’t running.", "按下快捷键，目标 App 立即来到前台；未运行时自动启动。"))
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        styleControl.segments = ShortcutsViewStyle.allCases.map {
            .init(title: $0.title, symbol: $0 == .list ? "list.bullet" : "keyboard",
                  toolTip: $0 == .list ? L("Show as a list", "以列表显示") : L("Show on a keyboard", "在键盘上显示"))
        }
        styleControl.target = self
        styleControl.action = #selector(styleChanged)

        keyboardView.onRecord = { [weak self] id in self?.beginRecording(id: id) }
        keyboardView.onDelete = { [weak self] id in
            guard let self, let row = self.context.store.shortcuts.firstIndex(where: { $0.id == id }) else { return }
            self.confirmDelete(row: row)
        }
        keyboardView.onPreview = { [weak self] id in
            guard let self, let shortcut = self.context.store.shortcut(id: id) else { return }
            self.context.previewHUD(shortcut)
        }
        keyboardView.onReveal = { [weak self] id in
            guard let shortcut = self?.context.store.shortcut(id: id) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: shortcut.appPath)])
        }
        keyboardView.onAssign = { [weak self] id, hotKey in self?.assign(hotKey, to: id) }
        keyboardView.onDropApplications = { [weak self] urls in self?.add(urls) }
        keyboardView.onAddAndAssign = { [weak self] hotKey in
            self?.pendingAssignHotKey = hotKey
            self?.addApplication()
        }

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        orderControl.size = .small
        orderControl.segments = [
            .init(title: ShortcutsListOrder.byKey.title, symbol: "keyboard.badge.ellipsis",
                  toolTip: L("Group by modifiers, sort by key", "按修饰键分组、按键位排序")),
            .init(title: ShortcutsListOrder.custom.title, symbol: "line.3.horizontal",
                  toolTip: L("Drag to reorder (also the overview and menu order)", "拖动排序（也是速查面板和菜单的顺序）"))
        ]
        orderControl.target = self
        orderControl.action = #selector(orderChanged)
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        subbar = NSStackView(views: [countLabel, spacer, orderControl])
        subbar.orientation = .horizontal
        subbar.alignment = .centerY

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if #available(macOS 11.0, *) { tableView.style = .plain }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.rowDragType, .fileURL])
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.onHoverRow = { [weak self] row in self?.setHoveredRow(row) }
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.onDeleteKey = { [weak self] row in
            guard let self, let id = self.appID(at: row),
                  let index = self.context.store.shortcuts.firstIndex(where: { $0.id == id }) else { return }
            self.confirmDelete(row: index)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        emptyView.onAdd = { [weak self] in self?.addApplication() }
        emptyView.onDropApplications = { [weak self] urls in self?.add(urls) }

        let addButton = PrimaryButton(title: L("Add App", "添加 App"), symbol: "plus", target: self, action: #selector(addApplication))
        addButton.toolTip = L("Add apps (⌘N)", "添加 App（⌘N）")
        addButton.keyEquivalent = "n"
        addButton.keyEquivalentModifierMask = [.command]

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [addButton, hintLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 14

        [header, styleControl, subbar, scrollView, emptyView, keyboardView, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(lessThanOrEqualTo: styleControl.leadingAnchor, constant: -12),
            styleControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            styleControl.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            keyboardView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            keyboardView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            subbar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 22),
            subbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            subbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            scrollView.topAnchor.constraint(equalTo: subbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
            emptyView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            emptyView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22)
        ])
        setHint(idleHint, highlighted: false)
    }

    /// 键盘模式下由键盘视图接收 Esc / 修饰键；列表模式不预先聚焦。
    var preferredFirstResponder: NSResponder? {
        style == .keyboard && context.store.shortcuts.isEmpty == false ? keyboardView : nil
    }

    @objc private func styleChanged() {
        let newStyle: ShortcutsViewStyle = styleControl.selectedIndex == 1 ? .keyboard : .list
        guard newStyle != style else { return }
        if context.recordingTarget != nil { context.cancelRecording() }
        context.preferences.shortcutsViewStyle = newStyle
        keyboardView.resetGroup()
        refresh()
        if newStyle == .keyboard { view.window?.makeFirstResponder(keyboardView) }
    }

    /// 键盘视图里把某个 App 直接绑定到点中的组合键。走与录制相同的冲突检查和注册流程。
    private func assign(_ hotKey: HotKey, to id: UUID) {
        if let message = HotKeyConflictChecker.conflict(
            for: hotKey, shortcuts: context.store.shortcuts,
            overviewHotKey: context.preferences.overviewHotKey, excludingShortcut: id
        ).message {
            SettingsContext.showAlert(message: L("\(hotKey.displayString) is unavailable", "快捷键 \(hotKey.displayString) 不可用"),
                                      detail: message, window: view.window)
            return
        }
        let previous = context.store.shortcut(id: id)?.hotKey
        context.store.updateHotKey(hotKey, for: id)
        let failures = context.reload()
        if let status = failures[id] {
            context.store.updateHotKey(previous, for: id)
            context.reload()
            SettingsContext.showAlert(message: L("\(hotKey.displayString) is unavailable", "快捷键 \(hotKey.displayString) 不可用"),
                                      detail: status.hotKeyFailureDescription, window: view.window)
        }
    }

    private func setHint(_ text: String, highlighted: Bool) {
        hintLabel.stringValue = text
        hintLabel.textColor = highlighted ? Theme.accentText : .secondaryLabelColor
    }

    // MARK: 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    private func appID(at row: Int) -> UUID? {
        guard items.indices.contains(row), case .app(let id) = items[row] else { return nil }
        return id
    }

    /// 某一行在所在分组中是否是首行 / 末行（用于拼接圆角卡片）。
    private func groupEdges(at row: Int) -> (first: Bool, last: Bool) {
        let first = row == 0 || appID(at: row - 1) == nil
        let last = row == items.count - 1 || appID(at: row + 1) == nil
        return (first, last)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard items.indices.contains(row), case .header = items[row] else { return 56 }
        return row == 0 ? 26 : 38
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        switch items[row] {
        case .header(let modifiers, let count):
            let identifier = NSUserInterfaceItemIdentifier("GroupHeader")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? GroupHeaderView ?? GroupHeaderView()
            cell.identifier = identifier
            cell.configure(modifiers: modifiers, count: count)
            return cell
        case .app(let id):
            guard let shortcut = context.store.shortcut(id: id) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("ShortcutListRow")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ShortcutListRowView ?? ShortcutListRowView()
            cell.identifier = identifier
            cell.configure(
                shortcut: shortcut,
                isRunning: isRunning(shortcut),
                isRecording: context.recordingTarget == shortcut.id,
                failure: context.registrationFailures[shortcut.id],
                showsGrip: order == .custom
            )
            cell.onRecord = { [weak self] in self?.beginRecording(id: id) }
            cell.onDelete = { [weak self] in
                guard let self, let index = self.context.store.shortcuts.firstIndex(where: { $0.id == id }) else { return }
                self.confirmDelete(row: index)
            }
            cell.onPreview = { [weak self] in
                guard let self, let current = self.context.store.shortcut(id: id) else { return }
                self.context.previewHUD(current)
            }
            cell.onReveal = {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: shortcut.appPath)])
            }
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard appID(at: row) != nil else { return PlainRowView() }
        let rowView = GroupedRowView()
        let edges = groupEdges(at: row)
        rowView.isFirstInGroup = edges.first
        rowView.isLastInGroup = edges.last
        rowView.separatorInset = order == .custom ? 80 : 58
        rowView.isHovered = hoveredRow == row
        return rowView
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { appID(at: row) != nil }

    private func setHoveredRow(_ row: Int?) {
        let row = row.flatMap { appID(at: $0) != nil ? $0 : nil }
        guard row != hoveredRow else { return }
        if let old = hoveredRow, let view = tableView.rowView(atRow: old, makeIfNecessary: false) as? GroupedRowView { view.isHovered = false }
        hoveredRow = row
        if let row, let view = tableView.rowView(atRow: row, makeIfNecessary: false) as? GroupedRowView { view.isHovered = true }
    }

    @objc private func orderChanged() {
        let newOrder: ShortcutsListOrder = orderControl.selectedIndex == 1 ? .custom : .byKey
        guard newOrder != order else { return }
        context.preferences.shortcutsListOrder = newOrder
        refresh()
    }

    private func isRunning(_ shortcut: AppShortcut) -> Bool {
        context.isRunning(shortcut)
    }

    // MARK: 拖拽：行内排序 + 从访达拖入 .app

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        // 只有“自定义顺序”可以拖动排序；按键位时顺序由快捷键决定。
        guard context.recordingTarget == nil, order == .custom, appID(at: row) != nil else { return nil }
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
            guard response == .OK else { self?.pendingAssignHotKey = nil; return }
            self?.add(panel.urls)
        }
    }

    private func add(_ urls: [URL]) {
        let pending = pendingAssignHotKey
        pendingAssignHotKey = nil
        let addedIDs = context.store.addApplications(at: urls)
        context.reload()
        if let pending, let first = addedIDs.first {
            assign(pending, to: first)
            return
        }
        if addedIDs.count == 1 {
            if let row = items.firstIndex(of: .app(addedIDs[0])) {
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

/// 支持 Delete 键删除当前行的表格。
private final class ShortcutTableView: NSTableView {
    var onDeleteKey: ((Int) -> Void)?
    /// 鼠标所在行变化（nil 表示离开表格）。
    var onHoverRow: ((Int?) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        onHoverRow?(row >= 0 ? row : nil)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverRow?(nil)
    }

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

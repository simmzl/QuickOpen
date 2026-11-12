import AppKit

/// 系统设置风格的工具栏分页窗口：「快捷键」「通用」。
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum Tab: String, CaseIterable {
        case shortcuts
        case general
        case about

        var title: String {
            switch self {
            case .shortcuts: return L("Shortcuts", "快捷键")
            case .general: return L("General", "通用")
            case .about: return L("About", "关于")
            }
        }

        var symbol: String {
            switch self {
            case .shortcuts: return "command.square"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }

        var identifier: NSToolbarItem.Identifier { .init(rawValue) }
    }

    let context: SettingsContext
    private let shortcutsController: ShortcutsViewController
    private let generalController: GeneralViewController
    private let aboutController = AboutViewController()
    private var currentTab: Tab = .shortcuts
    /// 默认尺寸放得下一把清晰的键盘；窗口可拖拽放大，尺寸会被记住。
    private static let defaultSize = NSSize(width: 900, height: 720)
    private static let minimumSize = NSSize(width: 680, height: 560)
    private static let frameAutosaveName = "QuickOpenSettingsWindow"

    var onShowOverview: (() -> Void)? {
        get { generalController.onShowOverview }
        set { generalController.onShowOverview = newValue }
    }

    init(context: SettingsContext) {
        self.context = context
        shortcutsController = ShortcutsViewController(context: context)
        generalController = GeneralViewController(context: context)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        window.toolbarStyle = .preference
        // 让磨砂背景延伸到标题栏下方，整窗一体。
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .visible
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "QuickOpenSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = Tab.shortcuts.identifier
        window.toolbar = toolbar

        select(.shortcuts)
        window.center()
        // 恢复用户上次拖拽后的尺寸和位置（首次使用默认尺寸）。
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    required init?(coder: NSCoder) { nil }

    func present(tab: String? = nil) {
        if let tab, let target = Tab(rawValue: tab) { select(target) }
        shortcutsController.refresh()
        generalController.refresh()
        showWindow(nil)
        AppLauncher.activateSelf()
        window?.orderFrontRegardless()
        window?.makeKey()
        resetFocus()
    }

    /// 打开窗口或切换页面时，AppKit 会把焦点交给第一个可聚焦的控件
    /// （开启“键盘导航”时连按钮、链接也会出现焦点环）。这里不预先聚焦任何控件；
    /// 只有键盘视图需要接收 Esc，交给页面自己处理。
    private func resetFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if self.currentTab == .shortcuts, let target = self.shortcutsController.preferredFirstResponder {
                window.makeFirstResponder(target)
            } else {
                window.makeFirstResponder(nil)
            }
        }
    }

    func showGeneralTab() { present(tab: Tab.general.rawValue) }

    private func select(_ tab: Tab) {
        guard let window else { return }
        context.cancelRecording()
        currentTab = tab
        window.toolbar?.selectedItemIdentifier = tab.identifier
        // 窗口标题始终是 App 名，当前页由工具栏选中状态表示。
        window.title = "QuickOpen"
        let controller: NSViewController
        switch tab {
        case .shortcuts: controller = shortcutsController
        case .general: controller = generalController
        case .about: controller = aboutController
        }
        // 保持窗口位置与尺寸不变，仅替换内容（两个页面共用用户调整后的尺寸）。
        let frame = window.frame
        window.contentViewController = controller
        window.initialFirstResponder = nil
        window.setFrame(frame, display: true)
        resetFocus()
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue), tab != currentTab else { return }
        select(tab)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        context.cancelRecording()
    }

    /// 录制期间所有热键都已注销；窗口一旦失焦就结束录制并恢复热键。
    /// 打开 sheet（如添加 App 面板）时窗口也会失焦，此时没有在录制，不受影响。
    func windowDidResignKey(_ notification: Notification) {
        context.cancelRecording()
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.identifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.identifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.identifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = Tab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        return item
    }
}

import AppKit

/// 系统设置风格的工具栏分页窗口：「快捷键」「通用」。
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum Tab: String, CaseIterable {
        case shortcuts
        case general

        var title: String {
            switch self {
            case .shortcuts: return "快捷键"
            case .general: return "通用"
            }
        }

        var symbol: String {
            switch self {
            case .shortcuts: return "command.square"
            case .general: return "gearshape"
            }
        }

        var identifier: NSToolbarItem.Identifier { .init(rawValue) }
    }

    let context: SettingsContext
    private let shortcutsController: ShortcutsViewController
    private let generalController: GeneralViewController
    private var currentTab: Tab = .shortcuts
    private static let contentSize = NSSize(width: 660, height: 500)

    var onShowOverview: (() -> Void)? {
        get { generalController.onShowOverview }
        set { generalController.onShowOverview = newValue }
    }

    init(context: SettingsContext) {
        self.context = context
        shortcutsController = ShortcutsViewController(context: context)
        generalController = GeneralViewController(context: context)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
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
    }

    func showGeneralTab() { present(tab: Tab.general.rawValue) }

    private func select(_ tab: Tab) {
        guard let window else { return }
        context.cancelRecording()
        currentTab = tab
        window.toolbar?.selectedItemIdentifier = tab.identifier
        window.title = tab.title
        let controller: NSViewController = tab == .shortcuts ? shortcutsController : generalController
        // 保持窗口左上角位置与尺寸不变，仅替换内容。
        let frame = window.frame
        window.contentViewController = controller
        window.setContentSize(Self.contentSize)
        window.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
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

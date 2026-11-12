import AppKit
import ObjectiveC

/// 全局光标规范：所有可点击的控件悬停时显示手形光标（与自绘的键帽、快捷键输入框、链接一致）。
///
/// AppKit 的系统控件（按钮、复选框、单选框、弹出菜单、滑块、分段控件、开关……）默认是箭头光标。
/// 这里替换 `NSControl.resetCursorRects`，在原有光标区域（如文本框的 I 形光标）之外，
/// 给启用状态的可点击控件加上手形光标。自绘控件自己实现了 `resetCursorRects`，不受影响。
enum PointerCursor {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(NSView.resetCursorRects)
        let replacement = #selector(NSControl.quickOpen_resetCursorRects)
        guard let originalMethod = class_getInstanceMethod(NSControl.self, original),
              let replacementMethod = class_getInstanceMethod(NSControl.self, replacement) else { return }
        // NSControl 自身实现了 resetCursorRects，只交换它，不影响其他 NSView。
        if class_addMethod(NSControl.self, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(NSControl.self, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    /// 工具栏页签（快捷键 / 通用 / 关于）：可点击区域是整个页签（图标 + 文字），
    /// 而系统只把其中的小图标做成按钮，所以在每个页签上盖一层只负责光标、不拦截点击的视图。
    static func installToolbarCursor(in window: NSWindow?) {
        guard let frameView = window?.contentView?.superview else { return }
        for viewer in descendants(of: frameView) where NSStringFromClass(type(of: viewer)) == "NSToolbarItemViewer" {
            guard !viewer.subviews.contains(where: { $0 is PointingHandOverlay }) else { continue }
            let overlay = PointingHandOverlay(frame: viewer.bounds)
            overlay.autoresizingMask = [.width, .height]
            viewer.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        window?.invalidateCursorRects(for: frameView)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }

    fileprivate static func showsPointingHand(_ control: NSControl) -> Bool {
        guard control.isEnabled, !control.isHidden, control.window != nil else { return false }
        // 菜单栏图标、窗口左上角的红绿灯保持系统行为。
        if control is NSStatusBarButton || NSStringFromClass(type(of: control)).hasPrefix("_NSTheme") { return false }
        return control is NSButton || control is NSSlider || control is NSSegmentedControl
            || control is NSSwitch || control is NSStepper || control is NSColorWell
    }
}

extension NSControl {
    /// 交换后此方法名指向系统原实现；外部请勿直接调用。
    @objc fileprivate func quickOpen_resetCursorRects() {
        quickOpen_resetCursorRects()
        if PointerCursor.showsPointingHand(self) {
            addCursorRect(visibleRect, cursor: .pointingHand)
        }
    }
}

/// 只提供手形光标区域的透明视图：不绘制、不参与点击和辅助功能。
private final class PointingHandOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func isAccessibilityElement() -> Bool { false }
}

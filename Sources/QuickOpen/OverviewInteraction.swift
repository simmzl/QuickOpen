import Foundation

/// 速查面板的交互状态机（不依赖 UI，便于测试）。
///
/// 按住模式（hold）：
/// - 按下快捷键显示面板；按住修饰键时每按一次触发键，选中项前进一格。
/// - 松开修饰键：有选中项则打开它，否则关闭面板。
/// 切换模式（toggle，从菜单打开或在设置中选择）：再按一次快捷键关闭。
struct OverviewInteraction {
    enum Effect: Equatable {
        case none
        case dismiss
        case launch(index: Int)
    }

    let mode: OverviewMode
    private(set) var selection: Int?
    let itemCount: Int
    /// 触发键当前是否按着（过滤按住不放时的重复按下事件）。
    private(set) var triggerIsDown = true

    init(mode: OverviewMode, itemCount: Int) {
        self.mode = mode
        self.itemCount = itemCount
    }

    /// 面板已显示时，速查面板快捷键再次按下。
    mutating func triggerPressed() -> Effect {
        guard !triggerIsDown else { return .none } // 自动重复
        triggerIsDown = true
        switch mode {
        case .hold:
            advance(by: 1)
            return .none
        case .toggle:
            return .dismiss
        }
    }

    mutating func triggerReleased() {
        triggerIsDown = false
    }

    /// 按住模式下修饰键已松开（单键快捷键则为该键松开）。
    func modifiersReleased() -> Effect {
        guard mode == .hold else { return .none }
        if let selection, (0..<itemCount).contains(selection) {
            return .launch(index: selection)
        }
        return .dismiss
    }

    mutating func advance(by delta: Int) {
        guard itemCount > 0 else { return }
        guard let current = selection else {
            selection = delta >= 0 ? 0 : itemCount - 1
            return
        }
        selection = ((current + delta) % itemCount + itemCount) % itemCount
    }

    mutating func moveVertically(by rows: Int, columns: Int) {
        guard itemCount > 0 else { return }
        guard let current = selection else {
            selection = 0
            return
        }
        let target = current + rows * columns
        if (0..<itemCount).contains(target) { selection = target }
    }

    mutating func select(_ index: Int?) {
        selection = index.flatMap { (0..<itemCount).contains($0) ? $0 : nil }
    }
}

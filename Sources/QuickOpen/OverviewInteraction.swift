import Foundation

/// 速查面板的交互状态机（不依赖 UI，便于测试）。
///
/// 按住模式（hold）：
/// - 按下快捷键显示面板；按住修饰键时每按一次触发键，选中项前进一格。
/// - 松开修饰键：有选中项则打开它；没有选中项且是一次“轻按”（很快松开）则转为切换模式常驻；
///   否则直接关闭。
/// 切换模式（toggle）：再按一次快捷键关闭。
struct OverviewInteraction {
    enum Effect: Equatable {
        case none
        case dismiss
        case launch(index: Int)
        /// 轻按：面板保持显示，改用切换模式操作。
        case becomeToggle
    }

    /// 短于此时长且未做任何选择的松开，视为轻按。
    static let quickTapInterval: TimeInterval = 0.3

    private(set) var mode: OverviewMode
    private(set) var selection: Int?
    let itemCount: Int
    let shownAt: TimeInterval
    /// 触发键当前是否按着（过滤按住不放时的重复按下事件）。
    private(set) var triggerIsDown = true

    init(mode: OverviewMode, itemCount: Int, shownAt: TimeInterval) {
        self.mode = mode
        self.itemCount = itemCount
        self.shownAt = shownAt
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
    mutating func modifiersReleased(at now: TimeInterval) -> Effect {
        guard mode == .hold else { return .none }
        if let selection, (0..<itemCount).contains(selection) {
            return .launch(index: selection)
        }
        if now - shownAt < Self.quickTapInterval {
            mode = .toggle
            return .becomeToggle
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

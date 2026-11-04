import AppKit
import ServiceManagement

/// 速查面板的呼出方式。
enum OverviewMode: String, CaseIterable {
    /// 按住修饰键时显示，松开即关闭（类似 ⌘Tab）。
    case hold
    /// 按一次显示，再按一次或 Esc 关闭。
    case toggle

    var title: String {
        switch self {
        case .hold: return L("Hold to show (closes when modifiers are released)", "按住显示（松开修饰键关闭）")
        case .toggle: return L("Toggle (press again or Esc to close)", "切换显示（再按一次或 Esc 关闭）")
        }
    }
}

/// 启动提示在屏幕中的位置。
enum HUDPosition: String, CaseIterable {
    case center
    case bottom

    var title: String {
        switch self {
        case .center: return L("Center of screen", "屏幕中央")
        case .bottom: return L("Bottom of screen", "屏幕底部")
        }
    }
}

extension Notification.Name {
    static let quickOpenPreferencesChanged = Notification.Name("QuickOpenPreferencesChanged")
}

/// 轻量的用户偏好，保存在 UserDefaults。修改后会发出 `.quickOpenPreferencesChanged`。
final class Preferences {
    private enum Key {
        static let hidesWhenFrontmost = "hidesWhenFrontmost"
        static let overviewHotKey = "overviewHotKey"
        static let overviewMode = "overviewMode"
        static let showsLaunchHUD = "showsLaunchHUD"
        static let hudPosition = "hudPosition"
        static let hudDuration = "hudDuration"
    }

    static let hudDurationRange: ClosedRange<Double> = 0.3...2.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.hidesWhenFrontmost: true,
            Key.overviewMode: OverviewMode.hold.rawValue,
            Key.showsLaunchHUD: true,
            Key.hudPosition: HUDPosition.center.rawValue,
            Key.hudDuration: 0.7
        ])
    }

    /// 目标 App 已在前台时，再按一次快捷键隐藏它。
    var hidesWhenFrontmost: Bool {
        get { defaults.bool(forKey: Key.hidesWhenFrontmost) }
        set { defaults.set(newValue, forKey: Key.hidesWhenFrontmost); changed() }
    }

    /// 速查面板快捷键；nil 表示用户主动清除（关闭速查面板快捷键）。
    var overviewHotKey: HotKey? {
        get {
            guard let data = defaults.data(forKey: Key.overviewHotKey) else { return .defaultOverview }
            if data.isEmpty { return nil }
            return (try? JSONDecoder().decode(HotKey.self, from: data)) ?? .defaultOverview
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data()
            defaults.set(data, forKey: Key.overviewHotKey)
            changed()
        }
    }

    var overviewMode: OverviewMode {
        get { OverviewMode(rawValue: defaults.string(forKey: Key.overviewMode) ?? "") ?? .hold }
        set { defaults.set(newValue.rawValue, forKey: Key.overviewMode); changed() }
    }

    var showsLaunchHUD: Bool {
        get { defaults.bool(forKey: Key.showsLaunchHUD) }
        set { defaults.set(newValue, forKey: Key.showsLaunchHUD); changed() }
    }

    var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: defaults.string(forKey: Key.hudPosition) ?? "") ?? .center }
        set { defaults.set(newValue.rawValue, forKey: Key.hudPosition); changed() }
    }

    /// 启动提示的停留时长（秒），限制在 `hudDurationRange` 内。
    var hudDuration: Double {
        get { Self.clampDuration(defaults.double(forKey: Key.hudDuration)) }
        set { defaults.set(Self.clampDuration(newValue), forKey: Key.hudDuration); changed() }
    }

    static func clampDuration(_ value: Double) -> Double {
        min(max(value, hudDurationRange.lowerBound), hudDurationRange.upperBound)
    }

    private func changed() {
        NotificationCenter.default.post(name: .quickOpenPreferencesChanged, object: self)
    }
}

/// 基于 SMAppService（macOS 13+）的开机自启。状态由系统维护，不额外持久化。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 需要用户在“系统设置 › 通用 › 登录项”中批准。
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}

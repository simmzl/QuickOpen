import Foundation
import ServiceManagement

/// 轻量的用户偏好，保存在 UserDefaults。
final class Preferences {
    private enum Key {
        static let hidesWhenFrontmost = "hidesWhenFrontmost"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.hidesWhenFrontmost: true])
    }

    /// 目标 App 已在前台时，再按一次快捷键隐藏它。
    var hidesWhenFrontmost: Bool {
        get { defaults.bool(forKey: Key.hidesWhenFrontmost) }
        set { defaults.set(newValue, forKey: Key.hidesWhenFrontmost) }
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

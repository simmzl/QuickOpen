import AppKit
import Foundation

/// 界面语言。默认跟随系统；系统首选语言不是中文时使用英文。
///
/// 选择会写入本 App 的 `AppleLanguages`，系统在下次启动时据此选择本地化
/// （包括打开面板、警告框按钮等系统自带的文字）。
enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    private static let appleLanguagesKey = "AppleLanguages"
    private static let choiceKey = "interfaceLanguage"

    /// 用户在设置中的选择。
    static var choice: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: choiceKey) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey)
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: appleLanguagesKey)
            }
        }
    }

    /// 本次运行实际使用的语言（启动时确定，运行中不变）。
    static var current: AppLanguage { override ?? launchLanguage }

    /// 仅供测试（例如分别渲染中英文截图）。
    static var override: AppLanguage?

    private static let launchLanguage: AppLanguage = {
        switch choice {
        case .english, .simplifiedChinese: return choice
        case .system: return resolve(Locale.preferredLanguages)
        }
    }()

    /// 根据首选语言列表决定界面语言：第一个是中文则用中文，否则英文。
    static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        guard let first = preferredLanguages.first?.lowercased() else { return .english }
        return first.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    var title: String {
        switch self {
        case .system: return L("Follow System", "跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

/// 返回当前界面语言对应的文案。
@inline(__always)
func L(_ english: String, _ chinese: String) -> String {
    AppLanguage.current == .simplifiedChinese ? chinese : english
}

enum AppRelauncher {
    /// 启动一个新的实例（等当前进程退出后再打开），然后退出。
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

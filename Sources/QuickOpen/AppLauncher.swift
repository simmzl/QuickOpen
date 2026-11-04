import AppKit
import Foundation

enum LaunchOutcome: Equatable {
    /// 已运行，被切到前台（必要时重新打开窗口）。
    case activated
    /// 未运行，正在启动。
    case launched
    /// 已在前台，按设置被隐藏。
    case hidden
    /// 找不到 App。
    case missing
}

final class AppLauncher {
    /// 目标 App 已在最前面时，再按一次快捷键是否隐藏它。
    var hidesWhenFrontmost = true

    @discardableResult
    func activate(_ shortcut: AppShortcut) -> LaunchOutcome {
        if let running = runningApplication(for: shortcut) {
            if hidesWhenFrontmost, running.isActive, !running.isHidden {
                running.hide()
                return .hidden
            }
            if running.isHidden { running.unhide() }
            // 通过 NSWorkspace 打开已运行的 App 会发送 reopen 事件，
            // 行为等同点击 Dock 图标：没有窗口时 App 会自己新建一个。
            if let url = running.bundleURL {
                open(url, appName: shortcut.appName, fallback: running)
            } else {
                Self.bringToFront(running)
            }
            return .activated
        }

        guard let applicationURL = resolvedApplicationURL(for: shortcut) else {
            showMissingApplicationAlert(shortcut)
            return .missing
        }
        open(applicationURL, appName: shortcut.appName, fallback: nil)
        return .launched
    }

    func runningApplication(for shortcut: AppShortcut) -> NSRunningApplication? {
        if let bundleIdentifier = shortcut.bundleIdentifier {
            return NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first { !$0.isTerminated }
        }
        let path = URL(fileURLWithPath: shortcut.appPath).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first {
            !$0.isTerminated && $0.bundleURL?.standardizedFileURL.path == path
        }
    }

    /// 兼容 macOS 13 与 14+ 的强制前台激活。
    static func bringToFront(_ application: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            application.activate(from: .current, options: [.activateAllWindows])
            application.activate(options: [.activateAllWindows])
        } else {
            application.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    /// 让 QuickOpen 自己来到前台（用于打开设置窗口、弹窗）。
    static func activateSelf() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func open(_ url: URL, appName: String, fallback: NSRunningApplication?) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                if let error {
                    if let fallback {
                        Self.bringToFront(fallback)
                    } else {
                        self.showLaunchError(error, appName: appName)
                    }
                    return
                }
                if let application, !application.isActive {
                    Self.bringToFront(application)
                }
            }
        }
    }

    private func resolvedApplicationURL(for shortcut: AppShortcut) -> URL? {
        if let bundleIdentifier = shortcut.bundleIdentifier,
           let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return installedURL
        }

        let storedURL = URL(fileURLWithPath: shortcut.appPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: storedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return storedURL
    }

    private func showMissingApplicationAlert(_ shortcut: AppShortcut) {
        let alert = NSAlert()
        alert.messageText = L("Can’t find \(shortcut.appName)", "找不到 \(shortcut.appName)")
        alert.informativeText = L("The app may have been moved or uninstalled. Remove it in QuickOpen and add it again.", "这个 App 可能已被移动或卸载。请在 QuickOpen 中删除后重新添加。")
        alert.alertStyle = .warning
        Self.activateSelf()
        alert.runModal()
    }

    private func showLaunchError(_ error: Error, appName: String) {
        let alert = NSAlert()
        alert.messageText = L("Couldn’t open \(appName)", "无法打开 \(appName)")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        Self.activateSelf()
        alert.runModal()
    }
}

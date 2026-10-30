import AppKit
import Foundation

final class AppLauncher {
    @discardableResult
    func activate(_ shortcut: AppShortcut) -> Bool {
        if let bundleIdentifier = shortcut.bundleIdentifier,
           let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) {
            return running.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }

        guard let applicationURL = resolvedApplicationURL(for: shortcut) else {
            showMissingApplicationAlert(shortcut)
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) {
            application, error in
            if let error {
                DispatchQueue.main.async {
                    self.showLaunchError(error, appName: shortcut.appName)
                }
                return
            }
            application?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        return true
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
        alert.messageText = "找不到 \(shortcut.appName)"
        alert.informativeText = "这个 App 可能已被移动或卸载。请在 QuickOpen 中删除后重新添加。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showLaunchError(_ error: Error, appName: String) {
        let alert = NSAlert()
        alert.messageText = "无法打开 \(appName)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

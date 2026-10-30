import Foundation

final class ShortcutStore {
    private(set) var shortcuts: [AppShortcut] = []
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(baseDirectory: URL? = nil) {
        let applicationSupportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseDirectory ?? applicationSupportDirectory
            .appendingPathComponent("QuickOpen", isDirectory: true)
        fileURL = directory.appendingPathComponent("shortcuts.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if baseDirectory == nil {
            migrateLegacyConfigurationIfNeeded(from: applicationSupportDirectory)
        }
        load()
    }

    @discardableResult
    func addApplications(at urls: [URL]) -> [UUID] {
        var addedIDs: [UUID] = []

        for inputURL in urls {
            let url = inputURL.resolvingSymlinksInPath().standardizedFileURL
            guard url.pathExtension.lowercased() == "app" else { continue }

            let bundle = Bundle(url: url)
            let bundleIdentifier = bundle?.bundleIdentifier
            let alreadyExists = shortcuts.contains { shortcut in
                if let bundleIdentifier, shortcut.bundleIdentifier == bundleIdentifier {
                    return true
                }
                return URL(fileURLWithPath: shortcut.appPath).standardizedFileURL == url
            }
            guard !alreadyExists else { continue }

            let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let shortcut = AppShortcut(
                appName: displayName,
                bundleIdentifier: bundleIdentifier,
                appPath: url.path
            )
            shortcuts.append(shortcut)
            addedIDs.append(shortcut.id)
        }

        if !addedIDs.isEmpty { save() }
        return addedIDs
    }

    func remove(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        save()
    }

    func updateHotKey(_ hotKey: HotKey?, for id: UUID) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[index].hotKey = hotKey
        save()
    }

    func shortcut(id: UUID) -> AppShortcut? {
        shortcuts.first { $0.id == id }
    }

    func uses(_ hotKey: HotKey, excluding id: UUID) -> Bool {
        shortcuts.contains { $0.id != id && $0.hotKey == hotKey }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            shortcuts = try decoder.decode([AppShortcut].self, from: data)
        } catch {
            NSLog("QuickOpen: failed to decode shortcuts: %@", error.localizedDescription)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(shortcuts).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("QuickOpen: failed to save shortcuts: %@", error.localizedDescription)
        }
    }

    private func migrateLegacyConfigurationIfNeeded(from applicationSupportDirectory: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let legacyURL = applicationSupportDirectory
            .appendingPathComponent("AppKey", isDirectory: true)
            .appendingPathComponent("shortcuts.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: legacyURL, to: fileURL)
        } catch {
            NSLog("QuickOpen: failed to migrate AppKey configuration: %@", error.localizedDescription)
        }
    }
}

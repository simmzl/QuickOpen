import Foundation

final class ShortcutStore {
    private(set) var shortcuts: [AppShortcut] = []
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    /// 配置文件损坏时备份到的路径（如有）。
    private(set) var corruptedBackupURL: URL?

    var configurationURL: URL { fileURL }

    /// - Parameters:
    ///   - baseDirectory: 存放 shortcuts.json 的目录；nil 表示 ~/Library/Application Support/QuickOpen。
    ///   - legacyDirectory: 旧版 AppKey 配置所在目录；nil 且使用默认目录时为 Application Support/AppKey。
    init(baseDirectory: URL? = nil, legacyDirectory: URL? = nil) {
        let applicationSupportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseDirectory ?? applicationSupportDirectory
            .appendingPathComponent("QuickOpen", isDirectory: true)
        fileURL = directory.appendingPathComponent("shortcuts.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let legacy = legacyDirectory
            ?? (baseDirectory == nil
                ? applicationSupportDirectory.appendingPathComponent("AppKey", isDirectory: true)
                : nil)
        if let legacy {
            migrateLegacyConfigurationIfNeeded(from: legacy)
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

    /// 把 `source` 位置的条目移动到 `destination`（NSTableView 拖拽语义：插入到该行之前）。
    func move(from source: Int, to destination: Int) {
        guard shortcuts.indices.contains(source),
              (0...shortcuts.count).contains(destination) else { return }
        let target = destination > source ? destination - 1 : destination
        guard target != source else { return }
        let item = shortcuts.remove(at: source)
        shortcuts.insert(item, at: target)
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
            backUpCorruptedConfiguration()
        }
    }

    /// 解析失败时把原文件改名保留，避免后续 save() 覆盖用户数据。
    private func backUpCorruptedConfiguration() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("shortcuts.corrupted-\(formatter.string(from: Date())).json")
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
            corruptedBackupURL = backupURL
        } catch {
            NSLog("QuickOpen: failed to back up corrupted shortcuts: %@", error.localizedDescription)
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

    private func migrateLegacyConfigurationIfNeeded(from legacyDirectory: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let legacyURL = legacyDirectory.appendingPathComponent("shortcuts.json")
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

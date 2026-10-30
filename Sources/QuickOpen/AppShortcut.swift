import AppKit
import Carbon
import Foundation

enum HotKeyValidation: Equatable {
    case valid
    /// 允许使用，但这个键（单键或仅 ⇧）在所有 App 中都会被拦截，无法正常输入。
    case interferesWithTyping
}

struct HotKey: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        HotKeyFormatter.displayString(for: self)
    }

    /// F1–F20 的虚拟键码。这些键不产生字符，单独使用不影响打字。
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]

    /// 默认的速查面板快捷键：⌃⌥Space。
    static let defaultOverview = HotKey(keyCode: 49, modifiers: UInt32(controlKey | optionKey))

    /// 仅修饰键部分对应的 NSEvent 标志，用于“按住显示”模式检测松开。
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// 任何按键都可以作为快捷键（包括不带修饰键的单键），这里只判断是否会影响正常输入。
    static func validate(keyCode: UInt32, modifiers: UInt32) -> HotKeyValidation {
        let typingModifiersOnly = modifiers == 0 || modifiers == UInt32(shiftKey)
        if typingModifiersOnly, !functionKeyCodes.contains(keyCode) { return .interferesWithTyping }
        return .valid
    }

    var interferesWithTyping: Bool {
        Self.validate(keyCode: keyCode, modifiers: modifiers) == .interferesWithTyping
    }

    /// 单键提示文字，例如“单键 A 会在所有 App 中被拦截，无法正常输入该键”。
    var typingWarning: String? {
        guard interferesWithTyping else { return nil }
        return "\(displayString) 会在所有 App 中被拦截，无法再正常输入该键"
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

struct AppShortcut: Codable, Equatable, Identifiable {
    let id: UUID
    var appName: String
    var bundleIdentifier: String?
    var appPath: String
    var hotKey: HotKey?

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String?,
        appPath: String,
        hotKey: HotKey? = nil
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.hotKey = hotKey
    }
}

enum HotKeyFormatter {
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
        33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥",
        49: "Space", 50: "`", 51: "⌫", 53: "Esc", 64: "F17", 71: "Clear",
        76: "⌤", 79: "F18", 80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16",
        107: "F14", 109: "F10", 111: "F12", 113: "F15", 115: "↖", 116: "⇞",
        117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func displayString(for hotKey: HotKey) -> String {
        keyCaps(for: hotKey).joined()
    }

    /// 拆分成一颗颗键帽，按 macOS 标准顺序：⌃ ⌥ ⇧ ⌘ 键。
    static func keyCaps(for hotKey: HotKey) -> [String] {
        var result: [String] = []
        if hotKey.modifiers & UInt32(controlKey) != 0 { result.append("⌃") }
        if hotKey.modifiers & UInt32(optionKey) != 0 { result.append("⌥") }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { result.append("⇧") }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { result.append("⌘") }
        result.append(keyName(for: hotKey.keyCode))
        return result
    }

    static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key\(keyCode)"
    }
}

import AppKit
import Carbon
import Foundation

enum HotKeyValidation: Equatable {
    case valid
    /// 没有任何修饰键。
    case needsModifier
    /// 只有 ⇧ 加普通键，会吃掉正常的大写输入。
    case shiftOnly
}

struct HotKey: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        HotKeyFormatter.displayString(for: self)
    }

    /// F1–F20 的虚拟键码。这些键不产生字符，允许仅与 ⇧ 组合。
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]

    static func validate(keyCode: UInt32, modifiers: UInt32) -> HotKeyValidation {
        if modifiers == 0 { return .needsModifier }
        if modifiers == UInt32(shiftKey), !functionKeyCodes.contains(keyCode) { return .shiftOnly }
        return .valid
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
        var result = ""
        if hotKey.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if hotKey.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyNames[hotKey.keyCode] ?? "Key\(hotKey.keyCode)"
        return result
    }
}

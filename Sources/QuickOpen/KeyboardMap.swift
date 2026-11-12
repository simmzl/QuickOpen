import AppKit
import Carbon

/// 键盘视图的数据层：Mac 键盘布局、按修饰键分组、分组配色、系统占用的组合键。
/// 与绘制无关，便于单元测试。

// MARK: - 布局

struct KeyboardKey {
    enum LegendAlignment { case center, leading, trailing }

    /// Carbon 虚拟键码；nil 表示装饰键（电源键）。
    let keyCode: UInt32?
    /// 印在键帽正面的文字。
    let legend: String
    /// 以“键”为单位的位置（左上角为原点）。
    let frame: CGRect
    let alignment: LegendAlignment
    let smallLegend: Bool

    /// 修饰键对应的 Carbon 修饰位（⌃⌥⇧⌘），其他键为 nil。
    var modifier: UInt32? { keyCode.flatMap { KeyboardLayout.modifierBits[$0] } }
    /// 不能作为快捷键主键的键：fn、caps lock、电源键。
    var isInert: Bool { keyCode == nil || KeyboardLayout.inertKeyCodes.contains(keyCode!) }
    var isHalfHeight: Bool { frame.height < 0.7 }
    var isShort: Bool { frame.height < 0.95 }
}

enum KeyboardLayout {
    /// 主键区宽 15 个键位。
    static let width: CGFloat = 15
    static let height: CGFloat = 6.02

    static let modifierBits: [UInt32: UInt32] = [
        59: UInt32(controlKey), 62: UInt32(controlKey),
        58: UInt32(optionKey), 61: UInt32(optionKey),
        56: UInt32(shiftKey), 60: UInt32(shiftKey),
        55: UInt32(cmdKey), 54: UInt32(cmdKey)
    ]
    /// fn、caps lock 无法注册为全局快捷键。
    static let inertKeyCodes: Set<UInt32> = [63, 57]

    static let keys: [KeyboardKey] = build()

    /// 键码 → 键（同一个修饰键左右各一颗时取左侧那颗）。
    static let keyByCode: [UInt32: KeyboardKey] = {
        var map: [UInt32: KeyboardKey] = [:]
        for key in keys { if let code = key.keyCode, map[code] == nil { map[code] = key } }
        return map
    }()

    /// 键在键盘上的阅读顺序（从上到下、从左到右），用于“按键位”排序；不在布局里的键排最后。
    static func readingOrder(of keyCode: UInt32) -> CGFloat {
        guard let key = keyByCode[keyCode] else { return 99_999 + CGFloat(keyCode) }
        return key.frame.minY * 100 + key.frame.minX
    }

    /// 每个修饰位在键盘上的主键（左侧那颗）。
    static func primaryKeyCode(forModifier bit: UInt32) -> UInt32? {
        switch bit {
        case UInt32(controlKey): return 59
        case UInt32(optionKey): return 58
        case UInt32(shiftKey): return 56
        case UInt32(cmdKey): return 55
        default: return nil
        }
    }

    private typealias Entry = (code: UInt32?, legend: String, width: CGFloat, align: KeyboardKey.LegendAlignment, small: Bool)

    private static func k(_ code: UInt32?, _ legend: String, _ width: CGFloat = 1,
                          _ align: KeyboardKey.LegendAlignment = .center, small: Bool = false) -> Entry {
        (code, legend, width, align, small)
    }

    /// 间隔用 code = nil、legend = ""。
    private static func gap(_ width: CGFloat) -> Entry { (nil, "\u{0}", width, .center, false) }

    private static func build() -> [KeyboardKey] {
        let letters: [Character: UInt32] = [
            "Q": 12, "W": 13, "E": 14, "R": 15, "T": 17, "Y": 16, "U": 32, "I": 34, "O": 31, "P": 35,
            "A": 0, "S": 1, "D": 2, "F": 3, "G": 5, "H": 4, "J": 38, "K": 40, "L": 37,
            "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "N": 45, "M": 46
        ]
        func row(_ chars: String) -> [Entry] { chars.map { k(letters[$0]!, String($0)) } }

        let rows: [(y: CGFloat, h: CGFloat, keys: [Entry])] = [
            (0, 0.82, [
                k(53, "esc"), gap(0.25),
                k(122, "F1"), k(120, "F2"), k(99, "F3"), k(118, "F4"), gap(0.25),
                k(96, "F5"), k(97, "F6"), k(98, "F7"), k(100, "F8"), gap(0.25),
                k(101, "F9"), k(109, "F10"), k(103, "F11"), k(111, "F12"), gap(0.25),
                k(nil, "◉")
            ]),
            (1.02, 1, [
                k(50, "~ `"), k(18, "! 1"), k(19, "@ 2"), k(20, "# 3"), k(21, "$ 4"), k(23, "% 5"),
                k(22, "^ 6"), k(26, "& 7"), k(28, "* 8"), k(25, "( 9"), k(29, ") 0"), k(27, "_ -"),
                k(24, "+ ="), k(51, "delete", 2, .trailing)
            ]),
            (2.02, 1, [k(48, "tab", 1.5, .leading)] + row("QWERTYUIOP") +
                [k(33, "{ ["), k(30, "} ]"), k(42, "| \\", 1.5)]),
            (3.02, 1, [k(57, "caps lock", 1.75, .leading)] + row("ASDFGHJKL") +
                [k(41, ": ;"), k(39, "\" '"), k(36, "return", 2.25, .trailing)]),
            (4.02, 1, [k(56, "⇧ shift", 2.25, .leading)] + row("ZXCVBNM") +
                [k(43, "< ,"), k(47, "> ."), k(44, "? /"), k(60, "shift ⇧", 2.75, .trailing)]),
            (5.02, 1, [
                k(63, "fn", 1, .leading), k(59, "⌃ control", 1, .leading, small: true),
                k(58, "⌥ option", 1, .leading, small: true), k(55, "⌘ command", 1.25, .leading, small: true),
                k(49, "", 5.5),
                k(54, "⌘ command", 1.25, .trailing, small: true), k(61, "⌥ option", 1, .trailing, small: true)
            ])
        ]

        var result: [KeyboardKey] = []
        for row in rows {
            var x: CGFloat = 0
            for entry in row.keys {
                if entry.legend != "\u{0}" {
                    result.append(KeyboardKey(keyCode: entry.code, legend: entry.legend,
                                              frame: CGRect(x: x, y: row.y, width: entry.width, height: row.h),
                                              alignment: entry.align, smallLegend: entry.small))
                }
                x += entry.width
            }
        }
        // 方向键：倒 T，占最后一行右侧 3 个键位。
        let y: CGFloat = 5.02, ax: CGFloat = 12
        result += [
            KeyboardKey(keyCode: 123, legend: "←", frame: CGRect(x: ax, y: y + 0.5, width: 1, height: 0.5), alignment: .center, smallLegend: false),
            KeyboardKey(keyCode: 126, legend: "↑", frame: CGRect(x: ax + 1, y: y, width: 1, height: 0.5), alignment: .center, smallLegend: false),
            KeyboardKey(keyCode: 125, legend: "↓", frame: CGRect(x: ax + 1, y: y + 0.5, width: 1, height: 0.5), alignment: .center, smallLegend: false),
            KeyboardKey(keyCode: 124, legend: "→", frame: CGRect(x: ax + 2, y: y + 0.5, width: 1, height: 0.5), alignment: .center, smallLegend: false)
        ]
        return result
    }
}

// MARK: - 修饰键分组

enum KeymapGroups {
    static let allModifiers: UInt32 = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    /// 按 macOS 标准顺序 ⌃ ⌥ ⇧ ⌘ 排列。
    static let orderedBits: [(bit: UInt32, glyph: String)] = [
        (UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")
    ]

    static func glyphs(_ modifiers: UInt32) -> [String] {
        orderedBits.filter { modifiers & $0.bit != 0 }.map(\.glyph)
    }

    static func title(_ modifiers: UInt32) -> String {
        modifiers == 0 ? L("Single key", "单键") : glyphs(modifiers).joined()
    }

    /// 分组顺序：单键在前，然后按修饰键个数、再按 ⌃⌥⇧⌘ 顺序。
    static func sorted(_ groups: some Sequence<UInt32>) -> [UInt32] {
        Array(Set(groups)).sorted { a, b in
            let ca = a.nonzeroBitCount, cb = b.nonzeroBitCount
            if ca != cb { return ca < cb }
            return sortKey(a) < sortKey(b)
        }
    }

    /// ⌃ 权重最高、⌘ 最低：同样个数时 ⌥ 组排在 ⌘ 组前面（与 ⌃⌥⇧⌘ 书写顺序一致）。
    private static func sortKey(_ m: UInt32) -> Int {
        orderedBits.enumerated().reduce(0) { acc, item in
            acc + (m & item.element.bit != 0 ? 0 : (1 << (3 - item.offset)))
        }
    }

    /// 修饰键组合有哪些已绑定 App。
    static func groups(of shortcuts: [AppShortcut]) -> [UInt32] {
        sorted(shortcuts.compactMap { $0.hotKey?.modifiers })
    }
}

// MARK: - 配色

/// OKLab / OKLCH 颜色，便于在感知均匀的空间里取同一亮度、同一彩度的一组颜色，
/// 以及在 OKLab 中混色（避免在 LCH 里插值时色相绕圈偏红）。
struct OKLab: Equatable {
    var l: Double, a: Double, b: Double

    init(l: Double, a: Double, b: Double) { self.l = l; self.a = a; self.b = b }

    /// OKLCH，h 为角度。
    init(l: Double, c: Double, h: Double) {
        let rad = h * .pi / 180
        self.init(l: l, a: c * cos(rad), b: c * sin(rad))
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = lin(c.redComponent), g = lin(c.greenComponent), bl = lin(c.blueComponent)
        let lc = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let mc = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let sc = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        self.init(l: 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc,
                  a: 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc,
                  b: 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc)
    }

    func mixed(with other: OKLab, _ t: Double) -> OKLab {
        OKLab(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }

    func color(alpha: CGFloat = 1) -> NSColor {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        func gamma(_ v: Double) -> CGFloat {
            let v = min(max(v, 0), 1)
            return CGFloat(v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)
        }
        return NSColor(srgbRed: gamma(4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S),
                       green: gamma(-1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S),
                       blue: gamma(-0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S),
                       alpha: alpha)
    }
}

func oklch(_ l: Double, _ c: Double, _ h: Double, alpha: CGFloat = 1) -> NSColor {
    OKLab(l: l, c: c, h: h).color(alpha: alpha)
}

extension NSColor {
    /// 在 OKLab 中与另一颜色混合，`amount` 为另一颜色所占比例。
    func mix(_ other: NSColor, _ amount: Double) -> NSColor {
        OKLab(self).mixed(with: OKLab(other), amount).color(alpha: alphaComponent)
    }
}

enum KeymapPalette {
    /// 一组同亮度、同彩度、色相分散的颜色：没有哪组特别刺眼，也没有哪组看不清。
    private static let fixed: [UInt32: (Double, Double, Double)] = [
        0: (0.5, 0.02, 260),                                              // 石墨灰：单键
        UInt32(optionKey): (0.66, 0.15, 38),                              // 珊瑚
        UInt32(controlKey | optionKey): (0.64, 0.11, 175),                // 青绿
        UInt32(optionKey | cmdKey): (0.6, 0.14, 262),                     // 雾蓝
        UInt32(controlKey | optionKey | cmdKey): (0.68, 0.13, 85),        // 赭黄
        UInt32(shiftKey | cmdKey): (0.62, 0.15, 330),                     // 兰紫
        UInt32(cmdKey): (0.6, 0.13, 220),
        UInt32(controlKey): (0.63, 0.12, 140),
        UInt32(controlKey | cmdKey): (0.62, 0.14, 300),
        UInt32(optionKey | shiftKey): (0.64, 0.14, 15)
    ]

    /// 分组颜色；未预设的组合按黄金角取色相，保证稳定且与已有颜色分开。
    static func color(for modifiers: UInt32) -> NSColor {
        if let (l, c, h) = fixed[modifiers] { return oklch(l, c, h) }
        let hue = (Double(modifiers >> 8) * 137.508).truncatingRemainder(dividingBy: 360)
        return oklch(0.63, 0.13, hue)
    }
}

// MARK: - 系统占用

struct ReservedCombo {
    let hotKey: HotKey
    let name: String
}

enum ReservedCombos {
    private static let cmd = UInt32(cmdKey), shift = UInt32(shiftKey), ctrl = UInt32(controlKey), opt = UInt32(optionKey)

    /// macOS 和常见 App 的通用快捷键。绑定这些组合会覆盖原有行为，或无法注册。
    static var system: [ReservedCombo] {
        [
            (49, cmd, L("Spotlight", "Spotlight")), (48, cmd, L("App Switcher", "切换 App")),
            (12, cmd, L("Quit", "退出")), (13, cmd, L("Close Window", "关闭窗口")),
            (8, cmd, L("Copy", "拷贝")), (9, cmd, L("Paste", "粘贴")), (7, cmd, L("Cut", "剪切")),
            (6, cmd, L("Undo", "撤销")), (0, cmd, L("Select All", "全选")), (1, cmd, L("Save", "存储")),
            (4, cmd, L("Hide", "隐藏")), (46, cmd, L("Minimize", "最小化")), (43, cmd, L("Settings", "设置")),
            (45, cmd, L("New", "新建")), (31, cmd, L("Open", "打开")), (35, cmd, L("Print", "打印")),
            (3, cmd, L("Find", "查找")), (17, cmd, L("New Tab", "新标签页")),
            (20, cmd | shift, L("Screenshot", "截屏")), (21, cmd | shift, L("Screenshot", "截屏")),
            (23, cmd | shift, L("Screenshot", "截屏工具")),
            (12, ctrl | cmd, L("Lock Screen", "锁屏")), (3, ctrl | cmd, L("Full Screen", "全屏")),
            (49, ctrl | cmd, L("Emoji", "表情")),
            (53, opt | cmd, L("Force Quit", "强制退出")),
            (49, ctrl, L("Input Source", "切换输入法"))
        ].map { ReservedCombo(hotKey: HotKey(keyCode: $0.0, modifiers: $0.1), name: $0.2) }
    }

    /// 加上 QuickOpen 自己的速查面板快捷键。
    static func all(overview: HotKey?) -> [ReservedCombo] {
        var list = system
        if let overview { list.insert(ReservedCombo(hotKey: overview, name: L("QuickOpen Overview", "QuickOpen 速查面板")), at: 0) }
        return list
    }
}

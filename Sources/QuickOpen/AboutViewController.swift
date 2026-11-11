import AppKit

/// 设置窗口「关于」页：App 信息、作者与 GitHub 仓库。
final class AboutViewController: NSViewController {
    static let repositoryURL = URL(string: "https://github.com/simmzl/QuickOpen")!
    static let authorURL = URL(string: "https://github.com/simmzl")!
    static let releasesURL = URL(string: "https://github.com/simmzl/QuickOpen/releases")!
    static let issuesURL = URL(string: "https://github.com/simmzl/QuickOpen/issues")!

    init() {
        super.init(nibName: nil, bundle: nil)
        title = L("About", "关于")
    }

    required init?(coder: NSCoder) { nil }

    /// 仅供测试：渲染 README 截图时使用仓库 Info.plist 中的版本号。
    static var versionOverride: (short: String, build: String?)?

    private var version: String {
        if let override = Self.versionOverride {
            return override.build.map { L("Version \(override.short) (\($0))", "版本 \(override.short)（\($0)）") }
                ?? L("Version \(override.short)", "版本 \(override.short)")
        }
        // 只读取 QuickOpen 自己的版本号（测试等环境下 Bundle.main 不是本 App）。
        let info = Bundle.main.bundleIdentifier == "com.simmzl.quickopen" ? Bundle.main.infoDictionary : nil
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?): return L("Version \(s) (\(b))", "版本 \(s)（\(b)）")
        case let (s?, nil): return L("Version \(s)", "版本 \(s)")
        default: return L("Development build", "开发版本")
        }
    }

    override func loadView() {
        view = SettingsBackdrop(frame: NSRect(x: 0, y: 0, width: 660, height: 480))

        let icon = NSImageView(image: AppIcons.brandLogo)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 112),
            icon.heightAnchor.constraint(equalToConstant: 112)
        ])

        let name = NSTextField(labelWithString: "QuickOpen")
        name.font = .systemFont(ofSize: 26, weight: .bold)
        let versionLabel = NSTextField(labelWithString: version)
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true
        let tagline = NSTextField(wrappingLabelWithString: L(
            "One key, one app. Open or switch to any Mac app with a global shortcut.",
            "一个键，打开一个 App。用全局快捷键直达任意 Mac App。"
        ))
        tagline.font = .systemFont(ofSize: 13)
        tagline.alignment = .center
        tagline.preferredMaxLayoutWidth = 420

        let info = GlassSurface(kind: .card, cornerRadius: 16)
        let rows = NSStackView(views: [
            infoRow(L("Author", "作者"), link: "Simmzl · github.com/simmzl", url: Self.authorURL),
            infoRow(L("Repository", "仓库"), link: "github.com/simmzl/QuickOpen", url: Self.repositoryURL),
            infoRow(L("License", "许可证"), text: "MIT"),
            infoRow(L("Requires", "系统要求"), text: L("macOS 13 Ventura or later", "macOS 13 Ventura 或更新版本"))
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false
        info.contentView.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: info.contentView.topAnchor, constant: 16),
            rows.bottomAnchor.constraint(equalTo: info.contentView.bottomAnchor, constant: -16),
            rows.leadingAnchor.constraint(equalTo: info.contentView.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: info.contentView.trailingAnchor, constant: -20)
        ])
        info.translatesAutoresizingMaskIntoConstraints = false
        info.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let repoButton = button(L("View on GitHub", "在 GitHub 上查看"), symbol: "chevron.left.forwardslash.chevron.right", url: Self.repositoryURL)
        let releasesButton = button(L("Releases", "版本发布"), symbol: "arrow.down.circle", url: Self.releasesURL)
        let issuesButton = button(L("Report an Issue", "反馈问题"), symbol: "exclamationmark.bubble", url: Self.issuesURL)
        let buttons = NSStackView(views: [repoButton, releasesButton, issuesButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let copyright = NSTextField(labelWithString: "© 2026 Simmzl · MIT License")
        copyright.font = .systemFont(ofSize: 11)
        copyright.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [icon, name, versionLabel, tagline, info, buttons, copyright])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(2, after: name)
        stack.setCustomSpacing(14, after: versionLabel)
        stack.setCustomSpacing(22, after: tagline)
        stack.setCustomSpacing(18, after: info)
        stack.setCustomSpacing(18, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    private func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: AppLanguage.current == .simplifiedChinese ? 64 : 84).isActive = true
        return label
    }

    private func infoRow(_ title: String, text: String) -> NSView {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 13)
        value.isSelectable = true
        return row(label(title), value)
    }

    private func infoRow(_ title: String, link: String, url: URL) -> NSView {
        let value = LinkButton(title: link, url: url)
        return row(label(title), value)
    }

    private func row(_ label: NSView, _ value: NSView) -> NSView {
        let row = NSStackView(views: [label, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 14
        return row
    }

    private func button(_ title: String, symbol: String, url: URL) -> NSButton {
        let button = LinkButton(title: title, url: url, plain: false)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        return button
    }
}

/// 打开网址的按钮：链接样式（主题色文字）或普通玻璃按钮。
private final class LinkButton: NSButton {
    private let url: URL

    init(title: String, url: URL, plain: Bool = true) {
        self.url = url
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(open)
        toolTip = url.absoluteString
        if plain {
            isBordered = false
            bezelStyle = .inline
            attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.linkColor
            ])
        } else {
            applyGlassStyle()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    @objc private func open() { NSWorkspace.shared.open(url) }
}

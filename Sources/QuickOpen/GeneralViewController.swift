import AppKit

/// 设置窗口「通用」页：开机自启、隐藏行为、速查面板、启动提示。
final class GeneralViewController: NSViewController {
    private let context: SettingsContext
    /// 请求打开速查面板（预览）。
    var onShowOverview: (() -> Void)?

    private let loginCheckbox = NSButton(checkboxWithTitle: "登录时启动 QuickOpen", target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let hideCheckbox = NSButton(checkboxWithTitle: "App 已在最前面时，再按一次快捷键将其隐藏", target: nil, action: nil)

    private let overviewControl = HotKeyControl()
    private let overviewNote = NSTextField(labelWithString: "")
    private let holdRadio = NSButton(radioButtonWithTitle: OverviewMode.hold.title, target: nil, action: nil)
    private let toggleRadio = NSButton(radioButtonWithTitle: OverviewMode.toggle.title, target: nil, action: nil)

    private let hudCheckbox = NSButton(checkboxWithTitle: "按下 App 快捷键时，在屏幕上显示 App 图标与快捷键", target: nil, action: nil)
    private let positionPopup = NSPopUpButton()
    private let durationSlider = NSSlider()
    private let durationLabel = NSTextField(labelWithString: "")
    private let previewButton = NSButton(title: "预览", target: nil, action: nil)

    init(context: SettingsContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        title = "通用"
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = SettingsBackdrop(frame: NSRect(x: 0, y: 0, width: 660, height: 480))
        buildInterface()
        context.onChange.append { [weak self] in self?.refresh() }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refresh() {
        let preferences = context.preferences
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off
        if LoginItem.requiresApproval {
            loginNote.stringValue = "需要在“系统设置 › 通用 › 登录项”中允许 QuickOpen。"
            loginNote.textColor = .systemOrange
        } else {
            loginNote.stringValue = "将 QuickOpen 放在“应用程序”文件夹中后再开启。"
            loginNote.textColor = .secondaryLabelColor
        }
        hideCheckbox.state = preferences.hidesWhenFrontmost ? .on : .off

        overviewControl.hotKey = preferences.overviewHotKey
        overviewControl.placeholder = "已关闭 · 点击录制"
        overviewControl.isRecording = context.recordingTarget == SettingsContext.overviewHotKeyID
        if let status = context.registrationFailures[SettingsContext.overviewHotKeyID] {
            overviewControl.isWarning = true
            overviewNote.stringValue = "⚠︎ " + status.hotKeyFailureDescription
            overviewNote.textColor = .systemRed
        } else if !overviewControl.isRecording {
            overviewControl.isWarning = false
            if let warning = preferences.overviewHotKey?.typingWarning {
                overviewNote.stringValue = "⚠︎ " + warning
                overviewNote.textColor = .systemOrange
            } else {
                overviewNote.stringValue = "一键查看所有 App 的快捷键。支持单键或组合键 · 点击修改"
                overviewNote.textColor = .secondaryLabelColor
            }
        }
        holdRadio.state = preferences.overviewMode == .hold ? .on : .off
        toggleRadio.state = preferences.overviewMode == .toggle ? .on : .off

        hudCheckbox.state = preferences.showsLaunchHUD ? .on : .off
        positionPopup.selectItem(at: HUDPosition.allCases.firstIndex(of: preferences.hudPosition) ?? 0)
        durationSlider.doubleValue = preferences.hudDuration
        durationLabel.stringValue = String(format: "%.1f 秒", preferences.hudDuration)
        [positionPopup, durationSlider, previewButton].forEach { $0.isEnabled = preferences.showsLaunchHUD }
    }

    // MARK: 界面

    private func buildInterface() {
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        hideCheckbox.target = self
        hideCheckbox.action = #selector(toggleHide)

        overviewControl.target = self
        overviewControl.action = #selector(recordOverview)
        holdRadio.target = self
        holdRadio.action = #selector(changeMode(_:))
        toggleRadio.target = self
        toggleRadio.action = #selector(changeMode(_:))
        let openOverview = NSButton(title: "打开速查面板", target: self, action: #selector(showOverview))
        openOverview.applyGlassStyle()

        hudCheckbox.target = self
        hudCheckbox.action = #selector(toggleHUD)
        positionPopup.addItems(withTitles: HUDPosition.allCases.map(\.title))
        positionPopup.target = self
        positionPopup.action = #selector(changePosition)
        durationSlider.minValue = Preferences.hudDurationRange.lowerBound
        durationSlider.maxValue = Preferences.hudDurationRange.upperBound
        durationSlider.numberOfTickMarks = 8
        durationSlider.allowsTickMarkValuesOnly = false
        durationSlider.target = self
        durationSlider.action = #selector(changeDuration)
        durationSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        previewButton.applyGlassStyle()
        previewButton.target = self
        previewButton.action = #selector(previewHUD)

        [loginNote, overviewNote].forEach {
            $0.font = .systemFont(ofSize: 11)
            $0.textColor = .secondaryLabelColor
            $0.lineBreakMode = .byWordWrapping
            $0.maximumNumberOfLines = 2
            $0.preferredMaxLayoutWidth = 470
        }

        let general = section("通用", rows: [
            stack([loginCheckbox]),
            indent(loginNote),
            stack([hideCheckbox])
        ])

        let overview = section("速查面板", rows: [
            labeled("快捷键", stack([overviewControl, openOverview], spacing: 10)),
            labeled("", overviewNote),
            labeled("呼出方式", stack([holdRadio, toggleRadio], vertical: true, spacing: 6))
        ])

        let hud = section("启动提示", rows: [
            stack([hudCheckbox]),
            labeled("位置", positionPopup),
            labeled("停留时间", stack([durationSlider, durationLabel, previewButton], spacing: 10))
        ])

        let content = NSStackView(views: [general, overview, hud])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        [general, overview, hud].forEach {
            $0.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    private func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        return stack
    }

    private func indent(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: -4),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = control is NSStackView && (control as? NSStackView)?.orientation == .vertical
            ? .top : .centerY
        row.spacing = 12
        return row
    }

    /// 带标题的圆角分组卡片。
    private func section(_ title: String, rows: [NSView]) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        let box = GlassSurface(kind: .card, cornerRadius: 16)
        let inner = NSStackView(views: rows)
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.contentView.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.contentView.topAnchor, constant: 14),
            inner.leadingAnchor.constraint(equalTo: box.contentView.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(lessThanOrEqualTo: box.contentView.trailingAnchor, constant: -16),
            inner.bottomAnchor.constraint(equalTo: box.contentView.bottomAnchor, constant: -14)
        ])

        let wrapper = NSStackView(views: [header, box])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 7
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true
        return wrapper
    }

    // MARK: 操作

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(loginCheckbox.state == .on)
        } catch {
            SettingsContext.showAlert(
                message: "无法更改登录项",
                detail: error.localizedDescription + "\n\n请确认 QuickOpen 位于“应用程序”文件夹中。",
                window: view.window
            )
        }
        if LoginItem.requiresApproval { LoginItem.openSystemSettings() }
        context.notify()
    }

    @objc private func toggleHide() {
        context.preferences.hidesWhenFrontmost = hideCheckbox.state == .on
    }

    @objc private func changeMode(_ sender: NSButton) {
        context.preferences.overviewMode = sender === holdRadio ? .hold : .toggle
        refresh()
    }

    @objc private func recordOverview() {
        overviewNote.stringValue = "按下新快捷键 · Esc 取消 · Delete 关闭速查面板快捷键"
        overviewNote.textColor = Theme.accentText
        let previous = context.preferences.overviewHotKey
        context.beginRecording(
            target: SettingsContext.overviewHotKeyID,
            onHint: { [weak self] message in
                self?.overviewNote.stringValue = message
                self?.overviewNote.textColor = Theme.accentText
            },
            apply: { [weak self] hotKey in self?.context.preferences.overviewHotKey = hotKey },
            revert: { [weak self] in self?.context.preferences.overviewHotKey = previous },
            window: view.window
        )
    }

    @objc private func showOverview() {
        onShowOverview?()
    }

    @objc private func toggleHUD() {
        context.preferences.showsLaunchHUD = hudCheckbox.state == .on
        refresh()
    }

    @objc private func changePosition() {
        let index = positionPopup.indexOfSelectedItem
        guard HUDPosition.allCases.indices.contains(index) else { return }
        context.preferences.hudPosition = HUDPosition.allCases[index]
    }

    @objc private func changeDuration() {
        // 以 0.1 秒为步进。
        let value = (durationSlider.doubleValue * 10).rounded() / 10
        context.preferences.hudDuration = value
        durationLabel.stringValue = String(format: "%.1f 秒", value)
    }

    @objc private func previewHUD() {
        let sample = context.store.shortcuts.first { $0.hotKey != nil }
            ?? context.store.shortcuts.first
            ?? AppShortcut(
                appName: "QuickOpen",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                appPath: Bundle.main.bundlePath,
                hotKey: context.preferences.overviewHotKey
            )
        context.previewHUD(sample)
    }
}

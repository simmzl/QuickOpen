import AppKit

/// 设置窗口「通用」页：开机自启、隐藏行为、速查面板、启动提示。
final class GeneralViewController: NSViewController {
    private let context: SettingsContext
    /// 请求打开速查面板（预览）。
    var onShowOverview: (() -> Void)?

    private let loginCheckbox = NSButton(checkboxWithTitle: L("Launch QuickOpen at login", "登录时启动 QuickOpen"), target: nil, action: nil)
    private let loginNote = NSTextField(labelWithString: "")
    private let hideCheckbox = NSButton(checkboxWithTitle: L("Press the shortcut again to hide an app that’s already in front", "App 已在最前面时，再按一次快捷键将其隐藏"), target: nil, action: nil)

    private let overviewControl = HotKeyControl()
    private let overviewNote = NSTextField(labelWithString: "")
    private let holdRadio = NSButton(radioButtonWithTitle: OverviewMode.hold.title, target: nil, action: nil)
    private let toggleRadio = NSButton(radioButtonWithTitle: OverviewMode.toggle.title, target: nil, action: nil)
    private let permissionNote = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "", target: nil, action: nil)
    private let permissionRow = NSStackView()

    private let hudCheckbox = NSButton(checkboxWithTitle: L("Show the app icon and shortcut on screen when you use a shortcut", "按下 App 快捷键时，在屏幕上显示 App 图标与快捷键"), target: nil, action: nil)
    private let positionPopup = NSPopUpButton()
    private let durationSlider = NSSlider()
    private let durationLabel = NSTextField(labelWithString: "")
    private let previewButton = NSButton(title: L("Preview", "预览"), target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private let languageNote = NSTextField(labelWithString: "")
    private let appearanceControl = PillSegmentedControl()

    init(context: SettingsContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        title = L("General", "通用")
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
            loginNote.stringValue = L("Allow QuickOpen in System Settings › General › Login Items.", "需要在“系统设置 › 通用 › 登录项”中允许 QuickOpen。")
            loginNote.textColor = .systemOrange
        } else {
            loginNote.stringValue = L("Move QuickOpen to the Applications folder before turning this on.", "将 QuickOpen 放在“应用程序”文件夹中后再开启。")
            loginNote.textColor = .secondaryLabelColor
        }
        hideCheckbox.state = preferences.hidesWhenFrontmost ? .on : .off
        appearanceControl.selectedIndex = AppearanceMode.allCases.firstIndex(of: preferences.appearanceMode) ?? 0

        overviewControl.hotKey = preferences.overviewHotKey
        overviewControl.placeholder = L("Off · Click to record", "已关闭 · 点击录制")
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
                overviewNote.stringValue = L("See every app’s shortcut at a glance. Single keys or combinations · Click to change", "一键查看所有 App 的快捷键。支持单键或组合键 · 点击修改")
                overviewNote.textColor = .secondaryLabelColor
            }
        }
        holdRadio.state = preferences.overviewMode == .hold ? .on : .off
        toggleRadio.state = preferences.overviewMode == .toggle ? .on : .off
        refreshPermission()

        hudCheckbox.state = preferences.showsLaunchHUD ? .on : .off
        positionPopup.selectItem(at: HUDPosition.allCases.firstIndex(of: preferences.hudPosition) ?? 0)
        durationSlider.doubleValue = preferences.hudDuration
        durationLabel.stringValue = String(format: L("%.1f s", "%.1f 秒"), preferences.hudDuration)
        [positionPopup, durationSlider, previewButton].forEach {
            $0.isEnabled = preferences.showsLaunchHUD
            // 启用状态变化后重新计算光标区域（禁用的控件不显示手形光标）。
            view.window?.invalidateCursorRects(for: $0)
        }
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
        permissionNote.font = .systemFont(ofSize: 11)
        permissionNote.lineBreakMode = .byWordWrapping
        permissionNote.maximumNumberOfLines = 2
        permissionNote.preferredMaxLayoutWidth = 360
        permissionButton.applyGlassStyle()
        permissionButton.controlSize = .small
        permissionButton.target = self
        permissionButton.action = #selector(grantPermission)
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        permissionRow.spacing = 8
        permissionRow.setViews([permissionNote, permissionButton], in: .leading)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        let openOverview = NSButton(title: L("Open Overview", "打开速查面板"), target: self, action: #selector(showOverview))
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
            $0.preferredMaxLayoutWidth = 460
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.title))
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: AppLanguage.choice) ?? 0)
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage)
        languageNote.font = .systemFont(ofSize: 11)
        languageNote.textColor = .secondaryLabelColor
        languageNote.isHidden = true

        // 与「快捷键」页的列表 / 键盘切换使用同一个胶囊分段控件。
        appearanceControl.segments = AppearanceMode.allCases.map { mode in
            .init(title: mode.title,
                  symbol: mode == .system ? "circle.lefthalf.filled" : mode == .light ? "sun.max" : "moon",
                  toolTip: nil)
        }
        appearanceControl.target = self
        appearanceControl.action = #selector(changeAppearance)

        let general = section(L("General", "通用"), rows: [
            labeled(L("Language", "语言"), stack([languagePopup, languageNote], spacing: 10)),
            labeled(L("Appearance", "外观"), appearanceControl),
            checkbox(loginCheckbox, note: loginNote),
            checkbox(hideCheckbox, note: nil)
        ])

        let overview = section(L("Overview", "速查面板"), rows: [
            labeled(L("Shortcut", "快捷键"), stack([overviewControl, openOverview], spacing: 10)),
            labeled("", overviewNote),
            labeled(L("Behavior", "呼出方式"), stack([holdRadio, toggleRadio], vertical: true, spacing: 6)),
            labeled("", permissionRow)
        ])

        let hud = section(L("Launch Hint", "启动提示"), rows: [
            checkbox(hudCheckbox, note: nil),
            labeled(L("Position", "位置"), positionPopup),
            labeled(L("Duration", "停留时间"), stack([durationSlider, durationLabel, previewButton], spacing: 10))
        ])

        let content = NSStackView(views: [general, overview, hud])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 22
        content.translatesAutoresizingMaskIntoConstraints = false

        // 内容超出窗口高度时可以滚动。
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            // 文档宽度跟随窗口，卡片右侧不会被裁掉。
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
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

    /// 复选框 + 下方说明文字：说明与复选框标题左对齐，不与上一行重叠。
    private func checkbox(_ box: NSButton, note: NSTextField?) -> NSView {
        guard let note else { return box }
        let column = NSStackView(views: [box, note])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        note.translatesAutoresizingMaskIntoConstraints = false
        let titleOffset: CGFloat = 20
        column.setCustomSpacing(2, after: box)
        note.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: titleOffset).isActive = true
        return column
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: AppLanguage.current == .simplifiedChinese ? 64 : 72).isActive = true
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
        inner.spacing = 12
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
                message: L("Couldn’t change the login item", "无法更改登录项"),
                detail: error.localizedDescription + L("\n\nMake sure QuickOpen is in the Applications folder.", "\n\n请确认 QuickOpen 位于“应用程序”文件夹中。"),
                window: view.window
            )
        }
        if LoginItem.requiresApproval { LoginItem.openSystemSettings() }
        context.notify()
    }

    @objc private func changeLanguage() {
        let index = languagePopup.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(index) else { return }
        let choice = AppLanguage.allCases[index]
        guard choice != AppLanguage.choice else { return }
        AppLanguage.choice = choice
        languageNote.stringValue = L("Takes effect after restart.", "重启 QuickOpen 后生效。")
        languageNote.isHidden = false

        let alert = NSAlert()
        alert.messageText = L("Restart QuickOpen to change the language?", "重启 QuickOpen 以切换语言？")
        alert.addButton(withTitle: L("Restart Now", "立即重启"))
        alert.addButton(withTitle: L("Later", "稍后"))
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { AppRelauncher.relaunch() }
        }
    }

    @objc private func changeAppearance() {
        let index = appearanceControl.selectedIndex
        guard AppearanceMode.allCases.indices.contains(index) else { return }
        context.preferences.appearanceMode = AppearanceMode.allCases[index]
    }

    @objc private func toggleHide() {
        context.preferences.hidesWhenFrontmost = hideCheckbox.state == .on
    }

    /// “按住显示”所需的输入监控权限状态。
    private func refreshPermission() {
        let needsPermission = context.preferences.overviewMode == .hold
        permissionRow.isHidden = !needsPermission
        guard needsPermission else { return }
        if InputMonitoring.isGranted {
            permissionNote.stringValue = L("✓ Input Monitoring allowed", "✓ 已允许“输入监控”")
            permissionNote.textColor = .secondaryLabelColor
            permissionButton.isHidden = true
        } else {
            permissionNote.stringValue = L(
                "Hold mode needs Input Monitoring to detect when you release the keys.",
                "“按住显示”需要“输入监控”权限来检测按键松开。"
            )
            permissionNote.textColor = .systemOrange
            permissionButton.title = L("Allow…", "去允许…")
            permissionButton.isHidden = false
        }
    }

    @objc private func grantPermission() {
        // 第一次会弹出系统提示；之前拒绝过则直接打开系统设置。
        if !InputMonitoring.request() { InputMonitoring.openSystemSettings() }
    }

    @objc private func appDidBecomeActive() {
        refreshPermission()
    }

    @objc private func changeMode(_ sender: NSButton) {
        context.preferences.overviewMode = sender === holdRadio ? .hold : .toggle
        refresh()
    }

    @objc private func recordOverview() {
        overviewNote.stringValue = L("Press a new shortcut · Esc to cancel · Delete to turn off", "按下新快捷键 · Esc 取消 · Delete 关闭速查面板快捷键")
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
        durationLabel.stringValue = String(format: L("%.1f s", "%.1f 秒"), value)
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

/// 坐标原点在左上角，滚动视图内容从顶部开始排列。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

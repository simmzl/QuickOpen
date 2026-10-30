# QuickOpen

一个原生、轻量的 macOS 菜单栏 App 启动器。

## 功能

- 为任意 `.app` 设置全局快捷键，支持组合键或单个键（单个字母键会在所有 App 中被拦截，界面会提示）
- App 已运行时立即切换到前台（没有窗口时会新开一个）；未运行时自动启动
- 再按一次快捷键隐藏 App（可关闭）
- **速查面板**：按 `⌃⌥Space`（可修改）在屏幕中央以网格显示所有 App 的图标与快捷键
  - 按住显示：按住 ⌃⌥ 期间显示，连按 Space 选择，松开打开；轻按一下则面板常驻
  - 切换显示：再按一次或 Esc 关闭，方向键选择，↩ 打开
  - 面板中直接按 App 快捷键或点击图标都可以打开
- **启动提示**：每次按 App 快捷键时在屏幕上短暂显示该 App 的图标与快捷键，帮助记忆
- 快捷键冲突检测、被占用提示；拖动排序；从访达直接拖入 App
- 登录时启动
- 不需要“辅助功能”权限
- 纯 AppKit + Carbon，零第三方依赖

## 使用

1. 打开 `dist/QuickOpen.dmg`。
2. 将 `QuickOpen` 拖入“应用程序”。
3. 首次打开 QuickOpen。
4. 点击“添加 App…”并选择应用。
5. 按下要绑定的快捷键：可以是组合键，也可以是单个键（如 F5）。
6. 以后在任何界面按下该快捷键即可呼出目标 App。

菜单栏中的 `⌘` 图标可以打开速查面板、设置、手动切换 App 或退出。速查面板与启动提示的选项在「设置 › 通用」中。

## 构建

需要 Xcode Command Line Tools 与 Swift 6：

```bash
./scripts/build-dmg.sh
```

构建结果位于 `dist/QuickOpen.app` 和 `dist/QuickOpen.dmg`。默认同时构建 Apple Silicon 与 Intel 架构。Release 构建使用 `-Osize`、链接期死代码裁剪和符号裁剪，以尽量减小体积。

如需公开分发且不出现 Gatekeeper 警告，请安装 `Developer ID Application` 证书。构建脚本会自动使用它；也可以显式指定：

```bash
QUICKOPEN_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh
```

如已使用 `notarytool store-credentials` 保存公证凭据，可以同时完成公证：

```bash
QUICKOPEN_NOTARY_PROFILE="quickopen-notary" ./scripts/build-dmg.sh
```

配置文件保存在：

```text
~/Library/Application Support/QuickOpen/shortcuts.json
```

首次启动会自动复制旧版 AppKey 的配置，不会删除原文件。配置文件损坏时会备份为 `shortcuts.corrupted-<时间>.json`，不会被覆盖。

## 测试

```bash
swift test
# 生成界面截图（浅色/深色）以检查布局：
QUICKOPEN_SNAPSHOT_DIR=/tmp/qo-shots swift test --filter SnapshotTests
```

# QuickOpen

一个原生、轻量的 macOS 菜单栏 App 启动器。

## 功能

- 为任意 `.app` 设置全局快捷键
- App 已运行时立即切换到前台
- App 未运行时自动启动并激活
- 快捷键和 App 列表保存在本机
- 不需要“辅助功能”权限
- 纯 AppKit + Carbon，零第三方依赖

## 使用

1. 打开 `dist/QuickOpen.dmg`。
2. 将 `QuickOpen` 拖入“应用程序”。
3. 首次打开 QuickOpen。
4. 点击“添加 App…”并选择应用。
5. 按下要绑定的快捷键（至少包含一个修饰键）。
6. 以后在任何界面按下该快捷键即可呼出目标 App。

菜单栏中的 `⌘` 图标可以打开设置、手动切换 App 或退出。

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

首次启动会自动复制旧版 AppKey 的配置，不会删除原文件。

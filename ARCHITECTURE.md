# Tinycast 项目架构导航（中文）

**用途：修改任何代码之前，先在本文件定位目标模块，再进入对应目录与功能文档。**

分层规则与设计原理见 [docs/architecture.md](docs/architecture.md)；写码规范见
[docs/standards.md](docs/standards.md)；验收标准见 [docs/testing.md](docs/testing.md)；
每个功能的细节与不变量见 [docs/features/](docs/features/README.md) 对应文档。

## 1. 项目是什么

原生 macOS 菜单栏启动器：模糊应用启动、全局与每应用热键、文本/图片剪贴板历史、内联计算器、
悬浮笔记、片段、Quicklinks、emoji 选择器，并能在 JavaScriptCore 中原生运行
Raycast 扩展。

| 约束 | 内容 |
| --- | --- |
| 系统目标 | macOS 26+，macOS 27 优先 |
| 语言与并发 | Swift 6 语言模式，完全严格并发，数据竞争是编译错误 |
| UI | SwiftUI + AppKit，`LSUIElement` 配件应用（无 Dock 图标） |
| 依赖 | 零第三方依赖；Carbon 仅用于系统级组合键注册（刻意的能力缺口） |
| 工程 | XcodeGen 生成工程（改 `project.yml` 后必须 `xcodegen generate`） |
| 规模参考 | `Tinycast/` 下约 540 个 Swift 文件、22 个功能模块（2026-10 统计） |

## 2. 顶层目录地图

| 目录 | 内容 |
| --- | --- |
| `Tinycast/App/` | 组合根：`TinycastLaunch`（@main）、`TinycastApp`、`AppDelegate`、`AppCore` |
| `Tinycast/Palette/` | 面板外壳：`PalettePanel`、`PaletteWindowController`、`RootPaletteView`、`PaletteScreen` 协议、`PaletteCoordinator`、`PaletteState` |
| `Tinycast/Windows/` | 非面板 AppKit 表面：`AppWindowController`、`Dialog/`、`HUD/` |
| `Tinycast/Features/` | 每个功能一个目录（见第 6 节地图） |
| `Tinycast/DesignSystem/` | 共享视觉原语；`Theme.swift` 是唯一设计 token 源 |
| `Tinycast/Platform/` | 系统垫片：`Permissions`、`NotificationToken`、`AppPaths`、`HealthTicker` 等 |
| `Tinycast/Resources/` | 生成资源：`RaycastRuntime.generated.js`、`EmojiKeywords/`、听写音效 |
| `Tests/` | 独立测试 harness，一文件一个，无 XCTest target，直接编译交付源码 |
| `Scripts/` | 全部可执行脚本：测试、lint、格式化、数据生成、打包 |
| `docs/` | 英文工程文档（规则与不变量的权威来源） |

## 3. 四层分层

每个成熟子系统收敛为同一套四层；目录树上的对应关系是 `Model/` → `Service/` → 可观察状态 → `UI/`。

| 层 | 目录 | 规则 |
| --- | --- | --- |
| PURE（只决策） | `Features/*/Model/` | 仅 Foundation（数据需要时可含 SQLite3/CoreGraphics）。**禁止 import AppKit/SwiftUI**——harness 直接编译交付源码，违规即编译失败。时钟、文件系统、汇率等环境事实一律注入参数 |
| EFFECT（做事情） | `Features/*/Service/` | 全部平台 IO：`AXUIElement`、`CGEventTap`、`NSWorkspace.open`、`URLSession`、`FileManager`、CoreAudio |
| OBSERVABLE STATE | Store/Session 类型 | `@MainActor @Observable`（禁 `ObservableObject`/`@Published`），归 Service 或 UI 侧所有 |
| VIEW（渲染） | `Features/*/UI/`、`Settings/` | SwiftUI 视图 + 该功能的 coordinator，声明式、薄、无策略 |

模型纯度自查：`grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/` 必须为空。

## 4. 组合根与所有权

- **`AppCore`（`App/AppCore.swift`）是唯一所有者。** `@MainActor` 单例，拥有全部 stores、managers、
  monitors、共享状态、各 feature coordinator 和窗口控制器。新的长生命周期状态必须加在
  `AppCore` 上并在 `start()` 接线，**不允许出现第二个单例**。
- 启动链：`TinycastLaunch`（钉界面语言）→ `TinycastApp`（单一 `MenuBarExtra` scene）→
  `AppDelegate.applicationDidFinishLaunching` → `AppCore.shared.start(launchedByUser:)`。
  `start()` 一屏读尽整个启动顺序。
- 视图通过 `@Environment` 拿 `AppCore` 作 **locator**：动作调该功能 coordinator
  （`core.quicklinkCoordinator.deleteQuicklink(…)`），视图永不绕过 coordinator 直改 store；
  只读渲染 store 合法。
- 重活（应用扫描、图片解码、shell 执行、汇率拉取）一律离主线程。仅有一个 actor，是刻意的。
- 剪贴板 OCR 跑在独立 bundled helper 进程，管道通信、用完即回收。

## 5. 窗口与表面

| 表面 | 载体 | 拥有者 |
| --- | --- | --- |
| 命令面板 | 无边框浮动 `NSPanel` + `NSHostingView`（`Palette/PalettePanel.swift`） | `PaletteWindowController` 独占 frame |
| Settings / Onboarding | 有标题 `NSWindow`（`Windows/AppWindowController.swift`） | `SettingsCoordinator` / `OnboardingCoordinator` |
| Notes | 常驻非激活 `NotesPanel` | `NotesWindowController` |
| 对话框 | `DialogPanel` | `DialogController`（唯一 presenter，async 呈现，一次一个） |
| HUD | `MessageHUDController` | `HUDPresenter`（独占一次性自动消退策略） |

**铁律：禁用 `NSAlert` 与系统 popover**——提问走 `DialogController`，报告走 `HUDPresenter`。
外观与动效只由 `AppCore.applyAppearance()` / `applyMotion()` 全局投射，别处不得再设。

## 6. 功能模块地图

大功能按 `Model/ Service/ UI/ Settings/` 四件套拆分，小功能保持扁平；下表"构成"只列与四件套不同的特例。

| 模块 | 职责 | 构成特例 | 详情 |
| --- | --- | --- | --- |
| `Launcher/` | 启动器核心：`AppIndex` 扫描、模糊匹配、排序/建议、别名、收藏、可见性 | | [launcher.md](docs/features/launcher.md) |
| `Clipboard/` | 剪贴板历史（文本/图片，SQLite）；OCR 与缩略图走外部 helper 进程 | | [clipboard.md](docs/features/clipboard.md) |
| `Calculator/` | 内联计算器：Foundation-only `CalcEngine` + 历史 + 汇率换算 | | [calculator.md](docs/features/calculator.md) |
| `Emoji/` | emoji 选择器（palette 子屏） | | [emoji.md](docs/features/emoji.md) |
| `Extensions/` | Raycast 扩展运行时（JavaScriptCore 跑预构建 CommonJS） | 隔离铁律见下 | [extensions.md](docs/features/extensions.md) |
| `FileSearch/` | Search Files 面板屏：搜自建文件索引 | 含 `Helper/` | [file-search.md](docs/features/file-search.md) |
| `HotKeys/` | 全局/每应用热键、Hyper Key、双击修饰键（Carbon 自研） | 无 `Settings/`（Shortcuts 面板属设置外壳） | [hotkeys.md](docs/features/hotkeys.md) |
| `Notes/` | 悬浮常驻 Markdown 笔记（TextKit 2） | | [notes.md](docs/features/notes.md) |
| `Quicklinks/` | URL/搜索/文件/deeplink 变一等命令 | | [quicklinks.md](docs/features/quicklinks.md) |
| `Snippets/` | 文本片段模板与关键词展开 | | [snippets.md](docs/features/snippets.md) |
| `CustomCommands/` | 自定义 shell 命令注册为可搜索命令 | | [custom-commands.md](docs/features/custom-commands.md) |
| `TextInjection/` | 文本注入（`TextInjector`/`Paster`） | 仅 `Service/` | |
| `Uninstall/` | 卸载应用并清理残留文件 | 无 `Settings/` | [uninstall.md](docs/features/uninstall.md) |
| `Dictionary/` | Define Word 词典查询 | | [dictionary.md](docs/features/dictionary.md) |
| `AppleShortcuts/` | Apple Shortcuts 作为 launcher 独立分区 | | [apple-shortcuts.md](docs/features/apple-shortcuts.md) |
| `Backup/` | `.tinycast` 备份导出/导入 | 无 `UI/` | [backup.md](docs/features/backup.md) |
| `Settings/` | **设置外壳**：`SettingsCoordinator`、`AppSettings`、settings.json 镜像、`Panes/`（General、Permissions） | 本体即外壳，无 UI/ 子目录 | [settings-file.md](docs/features/settings-file.md) |
| `Onboarding/` | 首启引导（扁平 4 文件） | 扁平 | |

两点特殊位置：

- `Features/PaletteRowIndex.swift` 在 Features 顶层——扁平选择索引归 palette 所有，不归任何功能。
- **`Extensions/` 是隔离区**：扩展所需的视图、行、菜单、几何常量全部写在自己目录内，
  不得进 `DesignSystem/`、不得挂上 `Theme`。宁可复制也不共享"扩展长什么样"。

## 7. 共享层与生成文件

**共享层**

- `DesignSystem/`：`Theme`（唯一 token 源）、`KeyCapChip`、`Tooltip`、`SymbolImage`、
  `GlassEffectView`、`PopoverMenu`、`SettingsComponents`、`Scrolling/`、`Interaction/`。
  `Scrolling/EdgeDissolve.swift` 与 `ThinScrollbar.swift` **禁改**（目测调校，动了就是视觉回归）。
- `Platform/`：`Permissions`、`LaunchAtLogin`、`InputSourceSwitcher`、`ScreenTarget`、
  `AppDisplayName`、`NotificationToken`、`AppPaths`、`Signposts`、`HealthTicker`、`Memo`、
  `ActivationPolicy`、`Images/`、`Compression/`。

**生成文件（禁止手改，改脚本后重新生成）**

| 生成物 | 来源 |
| --- | --- |
| `EmojiData.generated.swift`、`Resources/EmojiKeywords/` | `node Scripts/gen-emoji.js` |
| `CurrencyData.generated.swift` | `node Scripts/gen-currencies.js` |
| `CountryZoneData.generated.swift` | `node Scripts/gen-countries.js` |
| `Resources/RaycastRuntime.generated.js` | `Scripts/raycast-runtime/build.mjs`（已提交，构建无需 Node） |

## 8. 测试与脚本

- `Tests/` 一文件一 harness，**直接编译 `Tinycast/` 交付源码**——这是 `Model/` 纯度的强制机制。
  跑法：`./Scripts/run-tests.sh`。
- 常用脚本：`lint.sh`（lint）、`format.sh`（格式化）、`sync-strings.sh`（本地化同步，改文案后必须跑，
  八种语言同次翻译）、`build-dmg.sh`、`verify-signature.sh`、`gen-*.js`（数据生成）。

## 9. 常见修改定位速查

| 要做的事 | 先看哪里 |
| --- | --- |
| 改某功能的设置页 | `Features/<功能>/Settings/`；无主功能的面板在 `Features/Settings/Panes/` |
| 新增偏好项 | `AppSettings` + `AppSettingsKey` + `SettingsFileSchema` 绑定（exhaustive switch 会逼你绑） |
| 加 launcher 命令/分区 | `AppEntry.Kind` 加 case（唯一分类来源），再看 `Features/Launcher/` |
| 改面板（palette）外观/交互 | `Palette/` + `DesignSystem/Theme` |
| 改热键行为 | `Features/HotKeys/` |
| 改 Raycast 扩展运行 | `Features/Extensions/`；runtime 改动走 `Scripts/raycast-runtime/build.mjs` 重新生成 |
| 改对话框/HUD | `Windows/Dialog/`、`Windows/HUD/`，经 `DialogController`/`HUDPresenter`，禁 `NSAlert` |
| 加长生命周期状态 | `App/AppCore.swift` + `start()` 接线，禁新单例 |
| 写纯逻辑/算法 | `Features/*/Model/`（禁 AppKit/SwiftUI，环境事实注入） |
| 加平台能力垫片 | `Platform/` |
| 改用户可见文案 | 改 `Localizable.xcstrings` → `./Scripts/sync-strings.sh` → 八语言同次翻译 |
| 改工程结构/加文件目标 | `project.yml` → `xcodegen generate`，两个都提交 |

## 10. 协作约定（本仓库工作规则）

- **审查代码派发子 agent 时，最多同时 5 个。**
- **修改代码前，先查本文件定位落点**，再进对应功能目录与其 `docs/features/*.md` 读不变量。
- **git 提交信息用中文，按逻辑单元适时提交**，不要攒一大坨。
- 完成定义（见 [docs/testing.md](docs/testing.md)）：`run-tests.sh` 通过；Debug 构建无新警告；
  `lint.sh` 干净；`Model/` 纯度 grep 为空；被改错的文档同 commit 修复。

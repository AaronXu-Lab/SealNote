# AGENTS.md

SealNote（“Seal Note”）是一款基于 SwiftUI 的、采用端到端加密的快速记录便签应用。它通过单一代码库构建两个 App Target：**SealNote** (iOS 17+，同时支持 iPhone/iPad) 和 **SealNoteMac** (macOS 26+)；工程另外包含 `SealNoteCLI`、`SealNoteTests` 和 `SealNoteMacTests` Targets。

## 构建 / 运行 / 测试

本项目没有独立的 `Package.swift` 或 CocoaPods 配置文件，但 Xcode 项目 (`SealNote.xcodeproj`) 通过 Swift Package Manager 集成了外部依赖，使用 Swift 5。

- **默认 Xcode 工具链：** 开发、构建、测试默认使用 Xcode Beta：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild ...`。除非用户明确要求打开 Xcode，请只使用命令行工具（`xcodebuild`、`xcrun`、`./script/build_and_run.sh`），不要启动 Xcode GUI。开始构建前如需确认工具链，用 `xcodebuild -version` 或 `xcode-select -p` 检查即可。
- **运行 Mac 应用：** `./script/build_and_run.sh`（构建 Scheme `SealNoteMac`，终止任何运行中的实例，然后启动它）。可选参数：`--verify`（构建并确认进程已启动）、`--logs`、`--telemetry`（流式传输 `subsystem == com.xuweinan.sealnote` 的日志）、`--debug`（使用 lldb 调试）。
- **手动构建 Target：** macOS 使用 `xcodebuild -project SealNote.xcodeproj -scheme SealNoteMac -destination 'platform=macOS' build`；iOS/iPadOS 使用 `xcodebuild -project SealNote.xcodeproj -scheme SealNote -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' build`。也可以使用 `./script/verify.sh ios-build` 和 `./script/verify.sh mac-build`。
- **测试：** `SealNoteTests` Target 与 **`SealNote`** (iOS/iPadOS) Scheme 绑定；macOS 测试使用 `SealNoteMacTests` 和 **`SealNoteMac`** Scheme。优先使用 `./script/verify.sh ios-test`、`./script/verify.sh mac-test`，脚本会负责发现可用模拟器。运行单个 iOS 测试时，在命令后追加 `-only-testing:SealNoteTests/CryptoServiceTests/<method>`；需要验证 iPad 时，将 destination 指定为现有的 iPad 模拟器，例如 `platform=iOS Simulator,name=iPad Air 11-inch (M4)`。

## 平台隔离

共享代码位于 `SealNote/` 的根目录下。平台特定的代码通过 `#if os(iOS)` / `#if os(macOS)` 以及 `Mac/` 子文件夹进行隔离，macOS 子文件夹包括：`App/Mac`、`Views/Mac`、`Stores/Mac`。macOS 版本是一个菜单栏应用（使用 `MacMenuBarController`、`NSStatusItem`），带有悬浮的便签窗口 (`StickyNoteWindow`)；iOS/iPadOS 版本使用 `WindowGroup` → `ContentView`，当前主界面仍以 `NavigationStack` 为基础，iPad 自适应导航应在 iOS 侧实现，不要影响 macOS UI。新增功能前先确定它是共享功能、iOS/iPadOS 专属功能还是 macOS 专属功能，然后再放置文件。

## 存储架构（核心抽象）

便签是 **Markdown 文件，而不是数据库**。每篇便签对应一个 `<noteId>.md` 文件：正常笔记文件位于 vault 根目录，废纸篓文件位于 `trash/`，由 YAML 属性前言（frontmatter，包含 `note_id`、`created_at`、`updated_at`，可选 `title`）和正文组成。`MarkdownNoteFile.parse(from:)` 负责手写的属性前言解析。

- `VaultStorage`（协议）对文件系统进行了抽象。有两个实现类：**`ICloudVaultStorage`**（首选）和 **`LocalFallbackStorage`**。在 iOS/iPadOS 的默认初始化流程中，`VaultStore` 会根据 `SettingsStore.pinnedStorageRoot` 和 iCloud 可用性选择存储；首次选择后会持久化根目录，避免 iCloud 短暂不可用时静默分叉数据。iCloud 根目录不可用但已固定为 iCloud 时，当前启动会临时使用本地存储并标记 mismatch，不能把它当成新的独立 vault。
- `NoteIndex` 存储在 vault 根目录的 `notes.json` 中，是便签清单：每个便签的 `NoteIndexEntry` 记录了 `mode`（`.plain`/`.encrypted`）、`location` 以及废纸篓元数据（`deletedAt`、`purgeAfter`、`originalLocation`）。在修改便签时，请保持索引与实际的 `.md` 文件同步。
- **`VaultStore`**（`@MainActor`、`.shared` 单例、`ObservableObject`）是所有便签状态的唯一事实来源 —— 包括已解密的便签、明文便签、锁定的加密预览、废纸篓、搜索/标签过滤。UI 观察该对象，所有修改都通过它进行。

## 加密模型

- 钥匙串 (`KeychainStore`) 中存储了单一的 256 位对称保险库密钥 (`VaultKeyManager`)。该密钥可以导出/导入为 Base64 格式，以便相同的保险库可以在不同设备间解密 (`needsKeyExport`)。
- 每篇便签的加密**仅针对正文**：属性前言（frontmatter）保持明文，以便索引和同步仍能正常工作。`CryptoService.encryptMarkdownBody` 使用 AES-GCM 加密，布局为 `nonce ‖ ciphertext ‖ tag`，进行 base64url 编码，并带有字面前缀 **`snenc:v1:`**。`MarkdownNoteFile.isEncrypted` 根据该前缀进行判断 —— 如果该前缀发生变更，请确保 `MarkdownNoteFile` 和 `CryptoService` 中的 `encryptedPrefix` 保持一致。
- 当密钥缺失时，明文正文将通过 `NoteObfuscator` 显示为混淆的 base64 文本，以便锁定的内容在视觉上与真实的密文预览相匹配。

## 快捷键

新增或调整 macOS 快捷键时，默认必须同步接入设置页的“快捷键”配置，并通过 `ShortcutStore` 作为单一来源读取实际按键；除非用户明确要求不要提供设置入口。不要只在 View、菜单或事件监听器中写死新的快捷键。

## 编辑器架构

- iOS/iPadOS 的 `NoteEditorView` 和 macOS 的 `StickyNoteEditorView` 共用 `NoteEditorContentView`，平台容器只负责导航、窗口和平台专属命令；编辑器正文、预览及格式化行为应优先在共享组件中实现。
- `EditorSession` 是编辑期间正文状态与保存调度的唯一写入者。它负责防抖、串行保存、保存期间的新修改续写，以及关闭前刷新；不要在 View 中新增并行的自动保存任务或直接绕过会话写入 `VaultStore`。
- Markdown 格式化的纯文本操作集中在 `MarkdownFormatter`，新增语法操作时应补充 `MacMarkdownFormatterTests`，并在涉及 macOS Target 时同步覆盖 `SealNoteMacTests`。

## 备注

- 规划文档（`开发计划.md`、`macOS开发计划.md`、`Seal Note_PRD_*.md`）使用中文编写，描述产品意图和路线图；它们可能包含历史阶段内容，若与当前代码或用户明确需求冲突，以当前代码和用户需求为准。iOS 稳定化及 iPad 状态参考 `docs/ios-stabilization.md`。
- `script/` 是唯一的自动化脚本目录；CI 仅包含 `.github/workflows/auto-merge-owner-prs.yml`。

## 分平台规则

当前阶段默认进行 iOS/iPadOS 版本开发：除非用户明确指定 macOS、共享跨平台逻辑，或点名 `SealNoteMac` Scheme，新需求、缺陷修复、构建验证和 UI 调整默认针对 `SealNote` Scheme 及 iPad 体验。涉及 macOS 时只修改 macOS 相关代码；不要因为共享代码存在就改变 macOS 专属 UI 行为。

现在 mac 端笔记的容器样式已经很完美了，比如工具栏的透明，按钮的系统默认 glass button 效果，在接下来的需求中如果没有必要不要调整它

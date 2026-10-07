# iOS / iPadOS AaronUI 组件替换清单

当前使用 `AaronUI-SwiftUI 0.3.0`。范围为 Seal Note iOS / iPadOS，最低系统版本为 iOS 26。macOS 继续使用原来的组件实现。

## 0.3.0 升级检查（2026-10-07）

- 从 0.1.1 升至远程最新发布标签 0.3.0，更新最低依赖版本与 `Package.resolved`；其他依赖版本不变。
- 核对 Button、Input、Item、Selection、EmptyState、Dialog 和语义色接口；现有调用保持兼容，无需修改业务代码。0.3.0 移除的旧 Toast API 未被本项目使用。
- 开关、复选框和单选框的按压反馈现在只缩放指示器；Item 支持窄屏下将较宽的尾部控件移到下一行，并允许标题换行。这些变化由组件库直接提供。
- 新增 Slider 和主题色覆盖接口属于可选能力，本次升级保留现有系统滑块与配色策略。
- Xcode Beta：`SealNote` Scheme 在 `iPad Air 11-inch (M4)` / iOS 27 模拟器目标构建通过。本次完成源码兼容性检查与编译验证，未进行运行时交互或视觉验收。

## 已替换

| 原界面组件 | AaronUI 实现 | 使用位置 |
| --- | --- | --- |
| 工具栏普通按钮、主操作按钮 | `AUIButtonStyle` | 首页、设置、编辑器、回收站；保留原 action、disabled 条件及系统工具栏位置 |
| 重试、密钥操作、展开正文、筛选标签 | `AUIButton` / `AUIButtonStyle` | 首页、卡片、设置、独立笔记窗口 |
| 搜索框与清空按钮 | `AUIInput` + `AUIButton` | 首页和回收站；保留原查询绑定、防抖及过滤逻辑 |
| 重命名输入 | `AUIInput` | 重命名确认弹窗；保留空标题禁用条件 |
| 布尔设置 | `AUISwitchToggleStyle` | 双列布局、自动命名、隐私保护、维护日志及暂未开放的加密／标签设置 |
| 单项选择 | `AUIRadio` | 主题色、应用图标；图标变更仍先确认 |
| 笔记多选控件 | `AUICheckboxToggleStyle` | 普通笔记卡片的多选状态（批量操作目前未开放） |
| 设置项、信息行 | `AUIItem` | 设置各子页面、密钥状态、同步错误提示 |
| 设置分组及分隔线 | `AUIItemSectionGroup` | `SWSectionPanel` 的 iOS 实现；库负责行分隔 |
| 卡片表面 | `AUIItemSurface` | 普通笔记、加密占位、回收站、同步提示、加载占位 |
| 状态徽标 | `AUIBadge` | `SWStatusBadge` 的 iOS 实现；成功使用 green，错误使用 red，中性／警示使用 primary 并保留文字和图标 |
| 空状态、错误状态 | `AUIEmptyState` | 首页、回收站、独立笔记窗口、未选择笔记 |
| 初始加载占位 | `AUISkeleton` | 首页三张骨架卡片 |
| 窗口加载提示 | `AUILoading` | iPad 独立笔记窗口 |
| 图形标识 | `AUISymbol` | 隐私遮罩、页面头与空状态 |
| 普通消息与确认弹窗 | `auiDialog` + `AUIDialogAction` | 删除、恢复、清空、清理、错误、操作结果、重命名、图标切换及简单密钥提示 |

`IOSAaronUI.swift` 只封装搜索绑定和模态呈现；实际控件来自 AaronUI。弹窗放在透明的系统全屏模态层中，让遮罩覆盖导航栏，并隔离底层界面的键盘和辅助功能交互。共享 `SWComponents.swift` 与 `DesignSystem.swift` 使用 `#if os(iOS)` 保持 macOS 实现独立。

## 无法直接替换、保留的组件

| 组件 | 位置 | 保留原因 |
| --- | --- | --- |
| Markdown 正文编辑器、语法高亮及预览 | `NoteEditorContentView.swift`、`MarkdownHighlighter.swift`、`NoteCardView.swift` | `AUIInputArea` 是普通多行输入，不提供富文本高亮、光标／选区、格式操作、中文输入处理及现有编辑会话接口。卡片表面已替换，正文渲染保留。 |
| 字号与行高滑块 | `SettingsView.swift` | 初次迁移时 0.1.1 没有 Slider；0.3.0 已提供 AUISlider，本次依赖升级保留现有系统滑块、范围、步进和数值绑定，外层行使用 AUIItem。 |
| 系统导航栈、返回按钮、导航工具栏容器 | 首页、设置和编辑器 | `AUITopbar` 是布局组件，不负责导航历史、系统返回手势、工具栏溢出或窗口命令。可替换的工具栏按钮已使用库样式。 |
| 系统菜单、上下文菜单及滑动操作 | 笔记卡片、编辑器、回收站 | AaronUI 的 `Menu.swift` 明确将弹出菜单映射为原生 `Menu` / `Button` / `Section`；`AUIMenuPanel` 只适用于内联面板。库没有 swipe actions 替代品。菜单触发按钮已接入库样式。 |
| 笔记编辑 Sheet、iPad 全屏切换和独立窗口 | `HomeView.swift`、`NoteEditorView.swift`、`IPadNoteWindow.swift` | `auiSheet` 自带顶部栏、滚动容器和预设 detents，不支持当前编辑器焦点、交互关闭限制、大小切换及窗口移交协议。保留容器及 EditorSession 生命周期。 |
| 设置导航 Sheet、回收站 Sheet | `SettingsView.swift`、`HomeView.swift` | 页面自身包含导航栈；库 Sheet 的附加顶部栏／滚动容器会重复导航并改变现有呈现尺寸。内部控件已替换。 |
| 系统分享面板 | `ShareSheet` | `UIActivityViewController` 提供系统分享扩展和文件交接；组件库没有对应系统能力。 |
| 系统文件选择器 | 密钥导入 `.fileImporter` | 需要系统文档提供器、iCloud 下载和安全作用域 URL；组件库没有对应能力。 |
| 复杂密钥处理确认 | `KeyManagementView.activeAlertActions` | 多条长文本破坏性操作；库 Dialog 的操作区固定为单行 HStack，按钮文字只显示一行，在 iPhone 宽度下无法完整显示操作含义。保留原生 Alert；该入口当前受功能开关隐藏。 |
| 主题色样本与应用图标样本 | 外观设置 | 属于产品内容预览，需要保留实际主题色／图标语义。选择控件已替换为 AUIRadio。 |
| 系统图标变更确认、Face ID／密码验证 | UIKit / LocalAuthentication 系统界面 | 由系统提供，不能由组件库替代。 |
| 列表、网格、滚动布局、下拉刷新、隐私遮罩逻辑 | 首页、回收站、设置 | 库不提供等价的数据容器和系统生命周期能力；保留 SwiftUI 容器与状态逻辑，内部展示组件已迁移。 |

## 组件库限制

- AaronUI 0.3.0 已提供 `AUIColorTheme` 浅色／深色语义色覆盖接口，本项目尚未接入。主题选择仍作用于 Seal Note 的画布、正文和保留的系统控件；AaronUI 控件采用组件库自身颜色。
- Badge 没有 warning 色值，警示状态通过原有文字／图标表达，未在消费端复制一套黄色徽标。
- 未修改远程组件库，未开启原先暂停的加密、标签、Markdown 预览或批量操作功能。

## 初次迁移验证结果（0.1.1）

- Xcode Beta：SealNote iOS Simulator 构建通过；SealNoteMac 构建通过。
- iPhone 17 Pro / iOS 27 模拟器：检查首页、设置导航、字号／行高行、开关和重命名弹窗；修正滑块行高度、弹窗内容重叠及自定义 ToggleStyle 不遵循 labelsHidden 导致的重复标签。取消重命名后原笔记保持不变。
- `./script/verify.sh ios-test`：共 193 项，191 项通过，2 项失败。失败为 `SettingsStoreTests.testRecentNotesLimitIsClamped` 和 `testRecentNotesLimitPersists`；旧测试期待 3～12 范围及 7 的持久化，当前未改动的 SettingsStore 使用 5／10／15 档位。未在此次 UI 迁移中修改该 macOS 设置或测试。
- 当前验证环境只有 iOS 27 runtime；未声称已在 iOS 26 真机或 iPad 上完成运行时检查。iPad 分支已随 iOS Target 编译。

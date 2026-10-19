# macOS AaronUI 接入

开发阶段与 iOS 共用本地 `../AaronUI-SwiftUI` 依赖，SealNoteMac 已链接 AaronUI。路径与切回 GitHub 的方式见[来源切换说明](aaronui-dependency.md)。

## 已替换

- SWStatusBadge → AUIBadge；警示状态保留明确文字／图标，库没有独立的 warning Badge 颜色。
- SWSectionPanel → AUIItemSurface / AUIItemSectionGroup；分组线由库提供，删除 macOS SWRowDivider。
- SWSettingsRow → AUIItem。
- SWEmptyState → AUIEmptyState。
- SWFilterChip → AUIButton，保留选中状态和标签过滤行为。
- 设置页分段 Picker、Switch、Slider → AUISegmented、AUISwitchToggleStyle、AUISlider。
- 设置页普通按钮、列表行操作按钮、搜索清空／关闭按钮、介绍页关闭按钮与复选框接入库组件或样式。
- 全部笔记和回收站的业务行保留元信息／操作组合，视觉布局和表面由 AUIItem / AUIItemSurface 提供；全部笔记的悬停操作由 AUIItem.trailingHover 提供。

被替代的手绘 macOS 实现已删除；iOS 仍有调用的 SW 封装限制在 `#if os(iOS)` 内。无调用的 SWShimmer、SWPageHeader、SWFilterChip 和 SWFilterChipLabel 已删除。组件目录删除旧 SW 条目和预览，以及已经迁移的 Picker、Slider、Toggle 条目和预览，没有新增 AaronUI 展示目录。

## 主题

`MacAaronUITheme` 在应用启动及 `SettingsStore.appTheme` 变更时调用
`AUIColorTheme.brand(light:dark:).apply()`，由 AaronUI 根据 `AUIBrandPalette`
生成完整主题。应用只提供 OKLCH 品牌参数，不维护逐 token 字典；正文保持近中性，
成功／警告／错误色保留语义。现有 Web 预设不受 SealNote 的品牌调整影响。

macOS 的 `DS.primary`、`primaryDeep`、`primaryContainer`、`onPrimary` 统一读取 AaronUI
对应角色；`primary` 保留文字／tint 的墨色职责，浅色实心控件由库读取 `primaryFill`
及 `onPrimaryFill`，避免把浅填充直接当浅底上的文字。iOS 仍使用原有配色。

AaronUI 通过 Observation 原位刷新读取语义颜色的视图，已移除设置、列表、介绍和
组件目录／预览中的 `.macAaronUITheme()` 及其 `.id(appTheme)` 重建逻辑。
主题切换不再主动重置展示内容、滚动位置或编辑状态。编辑器会话与原生窗口、工具栏、
glass button 的实现保持原样。库提供颜色角色穷尽分类和覆盖检查，新增 token 时由库负责补齐。

## 暂时保留

- 设置页 Tab 使用原生 SwiftUI TabView（按用户要求恢复）；组件目录保留其条目及预览。

- SWFilterChipMenu：库按钮配合原有 NSMenu 锚点与选择回调。
- MacSettingsPage 和 macPanel：仅组合滚动、页面留白与库分组，不另绘组件。
- MacListSearchBar 的 TextField：现有自动聚焦和 Escape 关闭需要可写 FocusState；0.3.0 AUIInput 内部焦点为私有状态，没有公开的程序化聚焦绑定。清空／关闭按钮已迁移。
- 系统 Alert、ConfirmationDialog、NSAlert、文件选择和窗口：保留原生模态、键盘操作、长文本操作和平台生命周期。库 Dialog 不是这些平台行为的等价替代。
- 原生 Menu、上下文菜单、快捷键录制器：保留系统菜单与按键事件机制。
- 便签窗口容器、透明工具栏、系统 glass 按钮、Markdown 编辑器及附件交互：保留现有窗口和编辑行为。
- 组件目录里的系统控件预览用于展示仍在使用的原生能力，不批量改成库示例。

## 验证

- macOS 构建及启动检查通过；iPad Air 11-inch (M4) 模拟器目标构建通过。
- macOS 共 35 项测试通过，覆盖现有行为，并增加主题测试：六种主题／外观组合的实色按钮和正文对比度，中性正文不随主色染色。
- 电脑控制工具连接菜单栏应用超时，尚未完成运行时布局、主题切换与 VoiceOver 的视觉／交互验收。

## 正式主题预设接入验证（2026-10-19）

- SealNote 只将 `AppTheme` 映射到 `AUIColorThemePreset`，无逐 token overrides。
- 移除六处主题展示树重建调用；关于页应用图标的局部身份键仍保留，不涉及业务状态。
- `./script/verify.sh mac-test`：35 项测试通过，包含三主题、浅深两模式的正文和实色按钮对比度，以及近中性文字检查。
- 使用 Xcode Beta 执行 `./script/build_and_run.sh --review-windows`，构建并启动成功。
- macOS 设置页运行检查：粉色切至青色，Segment、面板／按钮边框、分隔线和画布同步更新，设置页保持通用标签。检测到用户操作后停止 GUI 自动化，未完成笔记草稿、列表搜索及全部导航状态的端到端检查。
- AaronUI 侧已有 `NSHostingView` 原位变色且保留 `@State` 身份的测试；应用的 `EditorSession` 及保存调度未改动。
- 当前使用本地 AaronUI 新 API；切回 GitHub 依赖前需确认对应版本已包含正式预设及 Observation 刷新能力。

## Logo 品牌主题（OKLCH）

来源是仓库中的 `Icon.icon`、`Icon2.icon`、`Icon3.icon`，取海豹腮红主色作为色相锚点。
使用 culori 将 sRGB 转为 OKLCH，保留色相，浅色填充统一 L=0.76，深色填充统一 L=0.78。
深色模式降低彩度；完整表面、线条、墨色和悬停态由 AaronUI 的品牌主题生成器负责。

| 主题 | Logo 色 | Logo OKLCH L / C / H | 浅色填充 C / Hex | 深色填充 C / Hex |
| --- | --- | --- | --- | --- |
| 粉 | #FD85A6 | 0.75846 / 0.14895 / 3.7704° | 0.125 / #F38EA8 | 0.10 / #EE9CB0 |
| 青 | #45DCEB | 0.82299 / 0.12446 / 204.7971° | 0.10 / #57C3CF | 0.075 / #7BC6CE |
| 绿 | #6FE29E | 0.82783 / 0.14347 / 155.5123° | 0.12 / #6CC890 | 0.09 / #87C99F |

这些填充色均在 sRGB 色域内。相较 Web 预设浅色主色 L=0.43，填充明显提亮；
文字／焦点墨色独立生成以保留对比度。OKLCH 定义参考 [CSS Color 4](https://www.w3.org/TR/css-color-4/#specifying-oklch)，
文字对比度校验依据 [WCAG Contrast Minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)。

### Logo 品牌主题验证

- `./script/verify.sh mac-test`：36 项测试通过，包含三主题 × 浅深模式的真实 `primaryFill` / `onPrimaryFill`、`primaryFillHover` 文字对，以及 `primaryInk` 在 surface / primarySoft / accentSubtle 上的对比度（均至少 4.5:1）。
- Xcode Beta `./script/build_and_run.sh --review-windows` 构建启动成功。
- 设置页查看了青、粉、绿三套浅色主题，实心开关、Segment 底色、线条和背景同步变色，通用标签与最近数量 10 保持。
- 恢复验证前青色主题时检测到用户操作，后续状态读取超时，未继续抢占窗口；最终主题选择以用户当前操作为准。
- 深色模式完成程序化颜色对比度验证，未操作系统外观进行视觉验收。

AaronUI 最终交接后（包含开关关闭态 `switchThumb`）再次运行 macOS 全套测试，36 项通过。
库侧最终记录为 34 项／7 suites 通过，Port Skill 更新至 1.19.0；
详见相邻库 `docs/brand-themes-2026-10-19.md`。

随后按库侧外观修正重新构建运行：Switch 无描边，开启与关闭均为白色滑块。
这项修正只改变 Switch 的外观角色，不更改三套 OKLCH 品牌参数；库侧 34 项测试重新通过，
Port Skill 为 1.19.1。SealNote 再次构建启动成功。

## 主色与控件对比修正（2026-10-19）

后续检查发现此前仅验证文字对比，漏掉白色开关滑块与浅主色轨道的对比，以及关闭轨道和分段状态的识别。
当前 AaronUI brand 生成器保持 Logo 的 H/C，选择满足文字 4.5:1、开关 3:1 的最近明度（内部目标 3.1:1）。
三主题浅色填充的实际 L 为粉 0.676、青 0.650、绿 0.646；深色为 0.673、0.652、0.650。
关闭轨道调整明度；分段选中项新增的轮廓已按用户要求撤回，保留原组件样式。详细配对、实际组件渲染和范围限制见
[组件库对比报告](../../AaronUI-SwiftUI/docs/contrast-2026-10-19.md)。此前 L=0.76/0.78 的记录保留为历史设计目标。


### 浅色实心按钮前景修正

之前的黑字来自主题 `onPrimaryFill`，不是残留 tint。浅色品牌 Fill 当前固定白字，生成器沿相同 OKLCH 色相继续降低 L 以保证正文及 hover 4.5:1。
实际浅色填充已更新为粉 #A34762、青 #00717A、绿 #047543；深色策略保留。前一节数值为历史阶段。

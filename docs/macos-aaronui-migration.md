# macOS AaronUI 接入

当前使用 AaronUI-SwiftUI 0.3.0，与 iOS 共用项目的 SPM 版本锁定。SealNoteMac 已链接 AaronUI。

## 已替换

- SWStatusBadge → AUIBadge；警示状态保留明确文字／图标，库没有独立的 warning Badge 颜色。
- SWSectionPanel → AUIItemSurface / AUIItemSectionGroup；分组线由库提供，删除 macOS SWRowDivider。
- SWSettingsRow → AUIItem。
- SWEmptyState → AUIEmptyState。
- SWFilterChip → AUIButton，保留选中状态和标签过滤行为。
- 设置页系统 TabView、分段 Picker、Switch、Slider → AUITabs、AUISegmented、AUISwitchToggleStyle、AUISlider。
- 设置页普通按钮、列表行操作按钮、搜索清空／关闭按钮、介绍页关闭按钮与复选框接入库组件或样式。
- 全部笔记和回收站的业务行保留元信息／操作组合，视觉布局和表面由 AUIItem / AUIItemSurface 提供；全部笔记的悬停操作由 AUIItem.trailingHover 提供。

被替代的手绘 macOS 实现已删除；iOS 仍有调用的 SW 封装限制在 `#if os(iOS)` 内。无调用的 SWShimmer、SWPageHeader、SWFilterChip 和 SWFilterChipLabel 已删除。组件目录删除旧 SW 条目和预览，以及已经迁移的 Picker、Slider、Toggle、TabView 条目和预览，没有新增 AaronUI 展示目录。

## 主题

`MacAaronUITheme` 在应用启动前配置 AUIColorTheme，并在 SettingsStore.appTheme 变更时重新应用。分别提供粉、青、绿的浅色／深色主色、实色按钮文字、背景、表面及中性文字配置。显式覆盖 onSurface 等文字别名，避免库默认别名跟随 primary 把正文染成主题色。

仅在设置、列表、介绍和组件目录／预览的展示内容边界刷新视图；设置选项卡、搜索及过滤状态仍在父视图，便签编辑器和 EditorSession 不重建。主题切换可能重置展示内容的滚动位置。

## 暂时保留

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

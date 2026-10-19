import Foundation
import SwiftUI
import AaronUI
import AppKit
import UniformTypeIdentifiers

struct MacSettingsView: View {
    enum Tab: Hashable {
        case general
        case editor
        case shortcuts
        case advanced
        case about
    }

    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectedTab: Tab
    @State private var recordingAction: MacShortcutRecordingAction?
    @State private var shortcutConflictMessage: String?
    @State private var settingsErrorMessage: String?
    @State private var settingsErrorTitle = "设置失败"
    @State private var isCheckingForUpdates = false
    @State private var isShowingCLIEnableConfirmation = false
    // Temporarily hidden for product-positioning reasons. Keep the state and
    // confirmation flow nearby so encrypted CLI access can be restored later.
    // @State private var isShowingCLIEncryptedAccessConfirmation = false
    #if DEBUG
    @State private var isShowingRestoreDefaultsConfirmation = false
    #endif

    init(selectedTab: Tab = .general) {
        _selectedTab = State(initialValue: selectedTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
                .tag(Tab.general)

            editorTab
                .tabItem {
                    Label("编辑器", systemImage: "textformat")
                }
                .tag(Tab.editor)

            shortcutTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }
                .tag(Tab.shortcuts)

            advancedTab
                .tabItem {
                    Label("高级", systemImage: "gearshape.2")
                }
                .tag(Tab.advanced)

            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .padding(.horizontal, DS.s4)
        .frame(
            minWidth: 640,
            idealWidth: 640,
            maxWidth: 640,
            minHeight: 660,
            idealHeight: 660,
            maxHeight: 660
        )
        .background(AUIColor.canvas)
        .background(shortcutRecorder)
        .alert(settingsErrorTitle, isPresented: settingsErrorBinding) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(settingsErrorMessage ?? "无法保存这个设置。")
        }
        .confirmationDialog(
            "启用命令行访问？",
            isPresented: $isShowingCLIEnableConfirmation,
            titleVisibility: .visible
        ) {
            Button("启用 CLI") {
                settings.setCLIAccessEnabled(true)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("启用后，本机同一用户下的 AI 或其他进程可以读取、搜索、创建、修改明文笔记，并将笔记移入应用废纸篓。只应向你信任的工具开放，用完后请及时关闭。")
        }
        // Encrypted-note CLI access is temporarily hidden for
        // product-positioning reasons. Retain this confirmation flow for a
        // possible future reintroduction.
//        .confirmationDialog(
//            "允许 CLI 访问加密笔记？",
//            isPresented: $isShowingCLIEncryptedAccessConfirmation,
//            titleVisibility: .visible
//        ) {
//            Button("允许访问", role: .destructive) {
//                settings.setCLIEncryptedAccessEnabled(true)
//            }
//            Button("取消", role: .cancel) {}
//        } message: {
//            Text("开启后，AI 或其他本机进程可以读取、全文搜索、修改加密笔记，并创建新的加密笔记。密钥不会通过 CLI 返回，但已解密正文会离开 Seal Note 界面。")
//        }
        #if DEBUG
        .confirmationDialog(
            "恢复所有默认设置？",
            isPresented: $isShowingRestoreDefaultsConfirmation
        ) {
            Button("恢复所有默认", role: .destructive) {
                restoreAllDefaults()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将恢复所有设置、快捷键和启动时的功能介绍，不会删除笔记或密钥。")
        }
        #endif
    }

    private var generalTab: some View {
        panelStack {
            macPanel("菜单栏") {
                toggleRow("启动时打开菜单栏应用", systemImage: "menubar.rectangle", isOn: launchAtLoginBinding)

                AUIItem("最近笔记数量", leading: .icon("list.number")) {
                    AUISegmented(selection: recentNotesLimitBinding, items: SettingsStore.macRecentNotesLimitOptions.map { AUISegmentItem(String($0), value: $0) }, size: .sm)
                    .accessibilityLabel("最近笔记数量")
                }
            }

            macPanel("笔记") {
                toggleRow("笔记默认置顶", systemImage: "pin.fill", isOn: $settings.pinNewNotesByDefault)

                toggleRow("新建笔记自动加密", subtitle: vaultStore.isKeyLoaded ? nil : "需要先在“密钥”中创建或加载密钥。", systemImage: "lock", isOn: newEncryptedNoteBinding)
                    .disabled(!vaultStore.isKeyLoaded)
            }

            macPanel("存储") {
                AUIItem(
                    vaultStore.isUsingICloudStorage ? "iCloud 文件夹" : "本地文件夹",
                    description: vaultStore.isUsingICloudStorage ? "笔记文件直接位于 iCloud Drive 公开文件夹中。" : "当前未使用 iCloud，已回退到本地存储。",
                    leading: .icon(vaultStore.isUsingICloudStorage ? "icloud" : "folder")
                ) {
                    AUIButton("打开存储文件夹", systemImage: "folder", iconOnly: true, variant: .ghost) {
                        openStorageFolder()
                    }
                    .help("打开存储文件夹")
                }
            }

            macPanel("主题") {
                AUIItem("主题色", leading: .icon("paintpalette")) {
                    AUISegmented(selection: $settings.appTheme, items: AppTheme.allCases.map { AUISegmentItem($0.title, value: $0) }, size: .sm)
                    .accessibilityLabel("主题色")
                }
            }
        }
    }

    private var advancedTab: some View {
        panelStack {
            let keyStatus = vaultStore.macKeyStatus
            macPanel("密钥状态") {
                AUIItem(
                    keyStatusTitle(keyStatus),
                    description: keyManagementSubtitle(for: keyStatus),
                    leading: .icon(keyManagementIcon(for: keyStatus))
                ) {
                    keyManagementActions(for: keyStatus)
                }
            }

            macPanel("访问权限") {
                toggleRow(
                    "命令行访问",
                    subtitle: "允许本机工具读写明文笔记，需保持应用运行。",
                    systemImage: "terminal",
                    isOn: cliAccessBinding
                )

                AUIItem("安装命令", description: cliInstallCommand, leading: .icon("arrow.down.to.line"), trailingType: .button) {
                    AUIButton("复制安装命令", systemImage: "doc.on.doc", iconOnly: true, variant: .ghost) {
                        copyToPasteboard(cliInstallCommand)
                    }
                    .help("复制安装命令")
                }

                // Encrypted-note CLI access is temporarily hidden for
                // product-positioning reasons. Keep this UI implementation so
                // it can be restored without rebuilding the interaction.

//
//                toggleRow(
//                    "允许访问加密笔记",
//                    subtitle: settings.cliAccessEnabled
//                        ? "允许读取、全文搜索、创建和修改当前可解锁的加密笔记。"
//                        : "请先启用命令行访问。",
//                    systemImage: "lock.open",
//                    isOn: cliEncryptedAccessBinding
//                )
//                .disabled(!settings.cliAccessEnabled)
            }
        }
    }

    private var aboutTab: some View {
        panelStack {
            macPanel("关于") {
                HStack(spacing: DS.s4) {
                    Button {
                        MacMenuBarController.shared.openIntroWindow()
                    } label: {
                        aboutLogo
                    }
                    .buttonStyle(.plain)
                    .help("打开欢迎页")
                    .accessibilityLabel("打开 Seal Note 欢迎页")
                    VStack(alignment: .leading, spacing: DS.s2) {
                        Text("Seal Note")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DS.textStrong)
                        Text("版本 \(appVersion)")
                            .font(DS.caption())
                            .foregroundStyle(DS.textSubtle)
                        Text("快速记录，不打断当前工作。")
                            .font(DS.body())
                            .foregroundStyle(DS.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowSeparator(.hidden)
            }

            macPanel("组件") {
                AUIItem("查看组件", leading: .icon("square.grid.2x2")) {
                    AUIButton("打开组件目录", systemImage: "arrow.up.right", iconOnly: true, variant: .ghost) {
                        MacMenuBarController.shared.openComponentCatalogWindow()
                    }
                    .help("打开组件目录")
                }
            }

            macPanel("维护日志") {
                AUIItem("开启日志记录", description: "记录保存、索引等元数据；不记录正文或密钥。", leading: .icon("doc.text.magnifyingglass"), trailingType: settings.maintenanceLoggingEnabled ? .buttons : .button) {
                    if settings.maintenanceLoggingEnabled {
                        HStack(spacing: DS.s2) {
                            AUIButton("打开日志文件夹", systemImage: "folder", iconOnly: true, variant: .ghost) {
                                openMaintenanceLogFolder()
                            }
                            .help("打开日志文件夹")

                            AUIButton("关闭", variant: .light, role: .destructive) {
                                settings.maintenanceLoggingEnabled = false
                            }
                        }
                    } else {
                        AUIButton("开启", variant: .light) {
                            settings.maintenanceLoggingEnabled = true
                        }
                    }
                }
            }

            VStack(spacing: DS.s3) {
                HStack(spacing: 0) {
                    Link(destination: privacyPolicyURL) {
                        Text("隐私政策")
                            .foregroundStyle(AUIColor.primary)
                    }
                    Text(" · ")
                        .foregroundStyle(DS.textSubtle)
                    Button(isCheckingForUpdates ? "正在检查…" : "检查更新") {
                        checkForUpdates()
                    }
                    .disabled(isCheckingForUpdates)
                }
                #if DEBUG
                Button("恢复所有默认") {
                    isShowingRestoreDefaultsConfirmation = true
                }
                #endif
            }
            .buttonStyle(.plain)
            .foregroundStyle(AUIColor.primary)
            .font(DS.caption())
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
        }
    }


    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://github.com/AaronXu-Lab/SealNote/blob/main/PRIVACY.md")!
    }

    #if DEBUG
    private func restoreAllDefaults() {
        do {
            try settings.restoreAllDefaults()
            shortcutStore.resetAllShortcuts()
            MacMenuBarController.shared.restoreDefaultWindowSizes()
        } catch {
            settingsErrorMessage = "无法恢复所有默认设置：\(error.localizedDescription)"
        }
    }
    #endif
    
    private var editorTab: some View {
        panelStack {
            macPanel("编辑体验") {
                AUIItem("编辑字号", leading: .icon("textformat.size"), trailingType: .dropdown) {
                    Picker("编辑字号", selection: $settings.editorFontSize) {
                        ForEach(12...18, id: \.self) { value in
                            Text(String(value)).tag(Double(value))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                AUIItem("行高", leading: .icon("line.3.horizontal.decrease"), trailingType: .dropdown) {
                    Picker("行高", selection: $settings.editorLineHeightMultiple) {
                        let options = (12...18).map { Double($0) / 10 }
                        // Preserve older slider values until the user chooses a new preset.
                        if !options.contains(settings.editorLineHeightMultiple) {
                            Text(settings.editorLineHeightMultiple.formatted(.number.precision(.fractionLength(1...2))))
                                .tag(settings.editorLineHeightMultiple)
                        }
                        ForEach(options, id: \.self) { value in
                            Text(String(format: "%.1f", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            macPanel("编辑行为") {
                toggleRow(
                    "正文宽度限制",
                    subtitle: "正文最宽约 30 个字。",
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    isOn: $settings.limitEditorMaximumWidth
                )

                toggleRow("空白笔记清理", subtitle: "关闭时自动丢弃空白笔记。", systemImage: "trash", isOn: $settings.autoDeleteEmptyNotes)

                toggleRow("自动命名", subtitle: "保存时按正文更新笔记标题。", systemImage: "text.cursor", isOn: $settings.autoRenameNotesOnSave)

                toggleRow("色值过滤", subtitle: "不将 #RRGGBB、#RRGGBBAA 识别为标签。", systemImage: "paintpalette", isOn: $settings.excludeHexColorsFromTags)
            }
        }
    }

    private var shortcutTab: some View {
        panelStack {
            macPanel("常用操作") {
                shortcutRow(
                    title: "新建笔记",
                    value: ShortcutStore.displayStringForKey(keyCode: shortcutStore.newNoteKey.keyCode, modifiers: shortcutStore.newNoteKey.modifiers),
                    isRecording: recordingAction == .newNote,
                    onRecord: { recordingAction = .newNote }
                )
                ForEach(EditorShortcutAction.allCases) { action in
                    let shortcut = shortcutStore.shortcut(for: action)
                    shortcutRow(
                        title: action.title,
                        value: ShortcutStore.displayStringForKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers),
                        isRecording: recordingAction == .editor(action),
                        onRecord: { recordingAction = .editor(action) }
                    )
                }
            }

            macPanel("Markdown 格式") {
                ForEach(MarkdownShortcutAction.allCases) { action in
                    let shortcut = shortcutStore.shortcut(for: action)
                    shortcutRow(
                        title: action.title,
                        value: ShortcutStore.displayStringForKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers),
                        isRecording: recordingAction == .markdown(action),
                        onRecord: { recordingAction = .markdown(action) }
                    )
                }
            }

            Button("恢复默认") {
                shortcutStore.resetAllShortcuts()
                recordingAction = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(AUIColor.primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowSeparator(.hidden)
        }
        .alert("快捷键冲突", isPresented: Binding(
            get: { shortcutConflictMessage != nil },
            set: { if !$0 { shortcutConflictMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(shortcutConflictMessage ?? "")
        }
    }

    private func keyStatusTitle(_ status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "未加载密钥"
        case .available:
            return "密钥已加载"
        case .invalid(.keyReplaced):
            return "密钥已被替换"
        case .invalid(.keyDownloadPending):
            return "密钥正在下载"
        case .invalid:
            return "密钥失效"
        }
    }

    private func keyManagementSubtitle(for status: MacVaultKeyStatus) -> String {
        let encryptedCount = vaultStore.encryptedEntryCount
        switch status {
        case .noReference where encryptedCount > 0:
            return "发现 \(encryptedCount) 条加密笔记，请优先加载原密钥。"
        case .noReference:
            return "当前未加载密钥。密钥只会在本机读取，不会保存到钥匙串。"
        case .available:
            return abbreviatedDisplayPath(vaultStore.keyFileDisplayPath)
                ?? "请妥善保存密钥，丢失后无法恢复加密笔记。"
        case .invalid(.keyDownloadPending):
            return "已请求 iCloud 下载密钥文件。下载完成后再打开加密笔记。"
        case .invalid where encryptedCount > 0:
            return "密钥失效，\(encryptedCount) 条加密笔记需要原密钥解锁。"
        case .invalid:
            return "密钥不可用、格式无效，或内容已被替换。"
        }
    }

    private func abbreviatedDisplayPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let cloudDocsPath = "/Library/Mobile Documents/com~apple~CloudDocs"
        guard let cloudDocsRange = standardizedPath.range(of: cloudDocsPath) else {
            return standardizedPath
        }

        let relativePath = standardizedPath[cloudDocsRange.upperBound...]
        guard relativePath.isEmpty || relativePath.hasPrefix("/") else {
            return standardizedPath
        }
        return "iCloud Drive" + relativePath
    }

    private func keyManagementIcon(for status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "lock.shield"
        case .available:
            return "checkmark.shield.fill"
        case .invalid:
            return "exclamationmark.triangle"
        }
    }

    @ViewBuilder
    private func keyManagementActions(for status: MacVaultKeyStatus) -> some View {
        switch status {
        case .noReference:
            if vaultStore.encryptedEntryCount > 0 {
                HStack(spacing: DS.s2) {
                    Button("加载已有密钥") {
                        loadKey()
                    }
                    .buttonStyle(AUIButtonStyle(variant: .fill))
                    .controlSize(.regular)
                    .tint(DS.primary)

                    Button("创建新密钥") {
                        createNewKey()
                    }
                    .buttonStyle(AUIButtonStyle(variant: .outline))
                    .controlSize(.regular)
                }
            } else {
                HStack(spacing: DS.s2) {
                    Button("创建新密钥") {
                        createNewKey()
                    }
                    .buttonStyle(AUIButtonStyle(variant: .fill))
                    .controlSize(.regular)
                    .tint(DS.primary)

                    Button("加载已有密钥") {
                        loadKey()
                    }
                    .buttonStyle(AUIButtonStyle(variant: .outline))
                    .controlSize(.regular)
                }
            }
        case .available:
            Menu {
                Button {
                    openKeyLocation()
                } label: {
                    Label("打开密钥位置", systemImage: "folder")
                }
                .labelStyle(.titleAndIcon)

                Button(role: .destructive) {
                    unloadKey()
                } label: {
                    Label("移除引用", systemImage: "link")
                }
                .labelStyle(.titleAndIcon)
            } label: {
                Label("密钥操作", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(AUIButtonStyle(variant: .ghost, contentType: .icon))
            .help("密钥操作")
        case .invalid:
            HStack(spacing: DS.s2) {
                Button("重新定位密钥") {
                    loadKey()
                }
                .buttonStyle(AUIButtonStyle(variant: .fill))
                .controlSize(.regular)
                .tint(DS.primary)

                Button("移除引用", role: .destructive) {
                    unloadKey()
                }
                .buttonStyle(AUIButtonStyle(variant: .outline))
                .controlSize(.regular)
            }
        }
    }

    private var newEncryptedNoteBinding: Binding<Bool> {
        Binding(
            get: { settings.preferredNoteMode == .encrypted },
            set: { isOn in
                settings.preferredNoteMode = isOn && vaultStore.isKeyLoaded ? .encrypted : .plain
            }
        )
    }

    private var recentNotesLimitBinding: Binding<Int> {
        Binding(
            get: { settings.macRecentNotesLimit },
            set: { settings.macRecentNotesLimit = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { isEnabled in
                do {
                    try settings.setLaunchAtLogin(isEnabled)
                } catch {
                    settingsErrorMessage = "无法更新登录项设置：\(error.localizedDescription)"
                }
            }
        )
    }

    private var cliAccessBinding: Binding<Bool> {
        Binding(
            get: { settings.cliAccessEnabled },
            set: { isEnabled in
                if isEnabled {
                    isShowingCLIEnableConfirmation = true
                } else {
                    settings.setCLIAccessEnabled(false)
                }
            }
        )
    }

    // Encrypted-note CLI access is temporarily hidden for product-positioning
    // reasons. Keep the binding implementation ready for a future reintroduction.
//    private var cliEncryptedAccessBinding: Binding<Bool> {
//        Binding(
//            get: { settings.cliEncryptedAccessEnabled },
//            set: { isEnabled in
//                if isEnabled {
//                    isShowingCLIEncryptedAccessConfirmation = true
//                } else {
//                    settings.setCLIEncryptedAccessEnabled(false)
//                }
//            }
//        )
//    }

    private var cliExecutablePath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/sealnote", isDirectory: false)
            .path
    }

    private var cliInstallCommand: String {
        let quotedPath = cliExecutablePath.replacingOccurrences(of: "'", with: "'\\''")
        return "sudo ln -sf '\(quotedPath)' /usr/local/bin/sealnote"
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var settingsErrorBinding: Binding<Bool> {
        Binding(
            get: { settingsErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    settingsErrorMessage = nil
                    settingsErrorTitle = "设置失败"
                }
            }
        )
    }

    private var shortcutRecorder: some View {
        ShortcutRecordingWindowHost(recordingAction: $recordingAction) { action, shortcut in
            if let conflict = shortcutStore.applyRecordedShortcut(shortcut, for: action) {
                let keys = ShortcutStore.displayStringForKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
                shortcutConflictMessage = "\(keys) 已用于“\(conflict)”。已保留原快捷键。"
            }
            recordingAction = nil
        }
        .frame(width: 0, height: 0)
    }

    private func panelStack<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        MacSettingsPage(content: content)
    }

    private func macPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        AUIItemSectionGroup {
            content()
        }
    }

    private func toggleRow(_ title: String, subtitle: String? = nil, systemImage: String? = nil, isOn: Binding<Bool>) -> some View {
        AUIItem(
            title,
            description: subtitle,
            leading: .icon(systemImage ?? (isOn.wrappedValue ? "checkmark.circle.fill" : "circle"))
        ) {
            Toggle(isOn: isOn) { EmptyView() }.accessibilityLabel(title)
                .labelsHidden()
                .toggleStyle(.auiSwitch)
                .tint(DS.primary)
        }
    }

    private func shortcutRow(title: String, value: String, isRecording: Bool, onRecord: @escaping () -> Void) -> some View {
        AUIItem(title, leading: .icon("keyboard"), trailingType: .button) {
            AUIButton(isRecording ? "正在录制…" : value, variant: .outline, action: onRecord)
                .monospacedDigit()
                .accessibilityLabel("录制\(title)快捷键，当前\(value)")
        }
    }

    @ViewBuilder
    private var aboutLogo: some View {
        if let image = MacAppIconController.image(for: settings.appTheme) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .id(settings.appTheme)
        } else {
            Color.clear
                .frame(width: 64, height: 64)
        }
    }

    private func openStorageFolder() {
        guard let containerURL = vaultStore.storageContainerURL else {
            let alert = NSAlert()
            alert.messageText = "无法打开文件夹"
            alert.informativeText = "当前没有可用的存储目录。"
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(containerURL, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                settingsErrorMessage = "Finder 无法打开文件夹：\(error.localizedDescription)"
            }
        }
    }

    private func openKeyLocation() {
        guard let displayPath = vaultStore.keyFileDisplayPath else {
            settingsErrorMessage = "当前没有可打开的密钥位置。"
            return
        }

        let url = URL(fileURLWithPath: displayPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parentURL = url.deletingLastPathComponent()
            if !NSWorkspace.shared.open(parentURL) {
                settingsErrorMessage = "Finder 未能打开：\(parentURL.path)"
            }
        }
    }

    private func openMaintenanceLogFolder() {
        let url = MaintenanceLogStore.shared.logsDirectory
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(url) {
                settingsErrorMessage = "Finder 未能打开：\(url.path)"
            }
        } catch {
            settingsErrorMessage = "无法打开日志文件夹：\(error.localizedDescription)"
        }
    }

    private func checkForUpdates() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        Task {
            defer { isCheckingForUpdates = false }
            await GitHubReleaseUpdateChecker.shared.checkForUpdates(alwaysShowResult: true)
        }
    }

    private func loadKey() {
        let panel = NSOpenPanel()
        panel.title = "加载已有密钥"
        panel.message = "密钥只会在本机读取，不会上传。"
        panel.allowedContentTypes = [.init(filenameExtension: "snkey")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try await vaultStore.importKeyFile(from: url)
            } catch {
                await MainActor.run {
                    handleKeyImportFailure(error, selectedURL: url)
                }
            }
        }
    }

    private func unloadKey() {
        if vaultStore.encryptedEntryCount == 0 {
            confirmRemoveKeyReference()
        } else if vaultStore.isKeyLoaded {
            confirmUsableKeyRemoval()
        } else {
            confirmInvalidKeyRemoval()
        }
    }

    private func confirmRemoveKeyReference() {
        let alert = NSAlert()
        alert.messageText = "移除密钥引用？"
        alert.informativeText = "只会让 Seal Note 忘记密钥位置，不会删除密钥本身。"
        alert.addButton(withTitle: "移除密钥引用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await vaultStore.unloadKey()
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confirmUsableKeyRemoval() {
        let alert = NSAlert()
        alert.messageText = "移除密钥引用前如何处理加密笔记？"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "移除密钥引用前，需要先删除这些加密笔记，或全部解密为明文。")
        alert.addButton(withTitle: "删除全部加密笔记")
        alert.addButton(withTitle: "先全部解密成明文")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
        case .alertSecondButtonReturn:
            decryptAllEncryptedNotesAndRemoveKey()
        default:
            break
        }
    }

    private func confirmInvalidKeyRemoval() {
        let alert = NSAlert()
        alert.messageText = "密钥失效时移除密钥引用？"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "当前密钥不可用，无法在此时解密加密笔记。若仍保留原密钥，请取消并先重新定位密钥。")
        alert.addButton(withTitle: "删除全部加密笔记")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
    }

    private func decryptAllEncryptedNotesAndRemoveKey() {
        Task { await runKeyRemovalAction { try await self.vaultStore.decryptAllEncryptedNotesAndRemoveKey() } }
    }

    private func runKeyRemovalAction(_ action: @escaping () async throws -> Int) async {
        do {
            _ = try await action()
            StickyNoteWindowManager.shared.closeAllWindows()
        } catch {
            await MainActor.run {
                if let conversionError = error as? EncryptedNoteConversionError,
                   case .filesUnavailable(_, let converted) = conversionError {
                    settingsErrorTitle = "解密尚未完成"
                    if converted > 0 {
                        StickyNoteWindowManager.shared.closeAllWindows()
                    }
                }
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private func affectedEncryptedNotesMessage(prefix: String) -> String {
        "\(prefix)\n\n受影响范围包括当前列表和回收站中的 \(vaultStore.encryptedEntryCount) 条加密笔记。"
    }

    private func createNewKey() {
        guard !vaultStore.hasKeyReference else {
            unloadKey()
            return
        }

        guard vaultStore.encryptedEntryCount == 0 else {
            confirmDeleteEncryptedNotesAndCreateKey()
            return
        }

        presentCreateKeyPanel()
    }

    private func confirmDeleteEncryptedNotesAndCreateKey() {
        let alert = NSAlert()
        alert.messageText = "创建新密钥会影响已有加密笔记"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "新密钥无法解锁现有加密笔记。继续前必须删除这些加密笔记。")
        alert.addButton(withTitle: "删除这些加密笔记并创建新密钥")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                await MainActor.run {
                    presentCreateKeyPanel()
                }
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func presentCreateKeyPanel() {
        let alert = NSAlert()
        alert.messageText = "创建新密钥？"
        alert.informativeText = "请将密钥保存到安全位置。丢失密钥将无法解密加密笔记。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let savePanel = NSSavePanel()
        savePanel.title = "保存密钥"
        savePanel.message = "保存成功后，Seal Note 会记住这个密钥的位置。"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        savePanel.nameFieldStringValue = "Seal Note-密钥-\(formatter.string(from: Date())).snkey"
        savePanel.allowedContentTypes = [.init(filenameExtension: "snkey")!]
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }

        Task {
            do {
                try await vaultStore.createKeyFile(at: saveURL)
            } catch {
                await MainActor.run {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "创建失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.addButton(withTitle: "确定")
                    errorAlert.runModal()
                }
            }
        }
    }

    private func handleKeyImportFailure(_ error: Error, selectedURL: URL) {
        guard let keyError = error as? VaultKeyFileError, keyError == .keyMismatch else {
            settingsErrorMessage = error.localizedDescription
            return
        }

        let alert = NSAlert()
        alert.messageText = "所选密钥无法解锁现有加密笔记"
        alert.informativeText = affectedEncryptedNotesMessage(prefix: "默认不会保存这次选择的密钥。")
        alert.addButton(withTitle: "重新选择密钥")
        alert.addButton(withTitle: "删除这些加密笔记并使用此密钥")
        alert.addButton(withTitle: "取消")
        if alert.buttons.indices.contains(1) {
            alert.buttons[1].hasDestructiveAction = true
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            loadKey()
        case .alertSecondButtonReturn:
            Task {
                do {
                    _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                    _ = try await vaultStore.importKeyFile(from: selectedURL)
                    StickyNoteWindowManager.shared.closeAllWindows()
                } catch {
                    await MainActor.run {
                        settingsErrorMessage = error.localizedDescription
                    }
                }
            }
        default:
            break
        }
    }
}

#Preview("设置 - 通用") {
    MacSettingsView(selectedTab: .general)
}

#Preview("设置 - 编辑器") {
    MacSettingsView(selectedTab: .editor)
}

#Preview("设置 - 快捷键") {
    MacSettingsView(selectedTab: .shortcuts)
}

#Preview("设置 - 密钥") {
    MacSettingsView(selectedTab: .advanced)
}

#Preview("设置 - 关于") {
    MacSettingsView(selectedTab: .about)
}

private struct MacSettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            content()
        }
        .auiItemListStyle()
        .scrollContentBackground(.hidden)
        .padding(.top, DS.s6)
        .padding(.horizontal, DS.s3)
        // Keep bottom breathing room inside the scrollable content so rows do not
        // disappear behind a fixed blank strip above the window's lower edge.
        .contentMargins(.bottom, DS.s4, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AUIColor.canvas)
    }
}

/// Keeps the transient recorder window scoped to the settings view's lifetime.
struct ShortcutRecordingWindowHost: NSViewRepresentable {
    @Binding var recordingAction: MacShortcutRecordingAction?
    let onRecord: (MacShortcutRecordingAction, MarkdownShortcut) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.recordingAction = $recordingAction
        guard let action = recordingAction else {
            coordinator.close()
            return
        }
        guard coordinator.window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "录制快捷键"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarSeparatorStyle = .none
        window.delegate = coordinator
        coordinator.beginRecording()
        window.contentView = NSHostingView(rootView:
            ShortcutRecordingContent(action: action, recordingAction: $recordingAction, onRecord: { action, shortcut in
                coordinator.close()
                onRecord(action, shortcut)
            })
        )
        coordinator.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var window: NSWindow?
        var recordingAction: Binding<MacShortcutRecordingAction?>?
        var shortcutStore = ShortcutStore.shared
        private var recordingToken: UUID?

        func beginRecording() {
            if recordingToken == nil { recordingToken = shortcutStore.beginShortcutRecording() }
        }

        private func finishRecording() {
            if let token = recordingToken {
                recordingToken = nil
                shortcutStore.endShortcutRecording(token)
            }
            if recordingAction?.wrappedValue != nil { recordingAction?.wrappedValue = nil }
        }

        func close() {
            let closingWindow = window
            window = nil
            finishRecording()
            closingWindow?.close()
        }

        func windowWillClose(_ notification: Notification) {
            window = nil
            finishRecording()
        }

        func windowDidResignKey(_ notification: Notification) {
            // Switching windows/apps cancels capture so no invisible recorder keeps shortcuts paused.
            close()
        }
    }
}

private struct ShortcutRecordingContent: View {
    let action: MacShortcutRecordingAction
    @Binding var recordingAction: MacShortcutRecordingAction?
    let onRecord: (MacShortcutRecordingAction, MarkdownShortcut) -> Void
    @State private var pressedKeys = ""

    var body: some View {
        VStack(spacing: DS.s4) {
            Text("正在录制：\(action.title)")
                .font(DS.body().weight(.semibold))
            Text(pressedKeys.isEmpty ? "请按下组合键" : pressedKeys)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(pressedKeys.isEmpty ? DS.textSubtle : DS.primary)
                .frame(height: 40)
                .accessibilityLabel("当前按键")
                .accessibilityValue(pressedKeys.isEmpty ? "尚未按键" : pressedKeys)
            Text("松开按键保存；按 Esc 或关闭窗口取消。")
                .font(DS.caption())
                .foregroundStyle(DS.textSecondary)
        }
        .frame(width: 360, height: 200)
        .background(ShortcutRecorderView(recordingAction: $recordingAction, onRecord: onRecord,
                                         onChange: { pressedKeys = $0 })
            .frame(width: 0, height: 0))
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var recordingAction: MacShortcutRecordingAction?
    let onRecord: (MacShortcutRecordingAction, MarkdownShortcut) -> Void
    var onChange: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onChange = onChange
        view.onCancel = { recordingAction = nil }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.recordingAction = recordingAction
        nsView.onRecord = onRecord
        nsView.onChange = onChange
        nsView.onCancel = { recordingAction = nil }
        if recordingAction != nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    static func dismantleNSView(_ nsView: RecorderView, coordinator: ()) {
        nsView.recordingAction = nil
        nsView.stopMonitoring()
    }

    final class RecorderView: NSView {
        var recordingAction: MacShortcutRecordingAction? {
            didSet {
                if recordingAction != oldValue { pendingShortcut = nil }
                updateEventMonitor()
            }
        }
        private var eventMonitor: Any?
        private var pendingShortcut: MarkdownShortcut?
        var onChange: ((String) -> Void)?
        var onRecord: ((MacShortcutRecordingAction, MarkdownShortcut) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recordingAction != nil else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateEventMonitor()
            if recordingAction != nil {
                window?.makeFirstResponder(self)
            }
        }

        func stopMonitoring() {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }

        private func updateEventMonitor() {
            guard recordingAction != nil, window != nil else {
                stopMonitoring()
                return
            }
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.consumeRecordingEvent(event) == true ? nil : event
                }
            }
        }

        @discardableResult
        func consumeRecordingEvent(_ event: NSEvent) -> Bool {
            guard recordingAction != nil, let window, window.isKeyWindow,
                  event.window === window else { return false }
            switch event.type {
            case .keyDown: keyDown(with: event)
            case .keyUp: keyUp(with: event)
            case .flagsChanged: flagsChanged(with: event)
            default: return false
            }
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recordingAction != nil else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                pendingShortcut = nil
                recordingAction = nil
                onChange?("")
                onCancel?()
                return
            }
            guard !event.isARepeat else { return }

            guard let keyEquivalent = event.charactersIgnoringModifiers?.lowercased(), !keyEquivalent.isEmpty else {
                return
            }

            let shortcut = MarkdownShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: ShortcutStore.carbonModifiers(from: event.modifierFlags),
                keyEquivalent: keyEquivalent
            )
            pendingShortcut = shortcut
            onChange?(ShortcutStore.displayStringForKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers))
        }

        override func flagsChanged(with event: NSEvent) {
            guard recordingAction != nil else { return }
            let modifiers = ShortcutStore.carbonModifiers(from: event.modifierFlags)
            if let shortcut = pendingShortcut {
                onChange?(ShortcutStore.displayStringForKey(keyCode: shortcut.keyCode, modifiers: modifiers))
            } else {
                onChange?(ShortcutStore.displayStringForModifiers(modifiers))
            }
        }

        override func keyUp(with event: NSEvent) {
            guard let action = recordingAction, let shortcut = pendingShortcut,
                  shortcut.keyCode == UInt32(event.keyCode) else { return }
            pendingShortcut = nil
            recordingAction = nil
            onRecord?(action, shortcut)
        }
    }
}

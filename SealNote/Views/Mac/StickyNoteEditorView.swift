import Foundation
import SwiftUI
import AppKit
import Combine
import Carbon
import UniformTypeIdentifiers

#if os(macOS)

enum MacNoteModeConversionNotice: Equatable {
    case encrypted
    case plain

    var title: String {
        switch self {
        case .encrypted: return "已转为加密笔记"
        case .plain: return "已转为明文笔记"
        }
    }

    var message: String {
        switch self {
        case .encrypted: return "正文已加密并上锁"
        case .plain: return "正文现在以明文保存"
        }
    }

    var systemImage: String {
        switch self {
        case .encrypted: return "lock.fill"
        case .plain: return "lock.open.fill"
        }
    }
}

private struct MacNoteModeConversionToast: View {
    let notice: MacNoteModeConversionNotice

    var body: some View {
        HStack(spacing: DS.s3) {
            Image(systemName: notice.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.primaryDeep)

            VStack(alignment: .leading, spacing: DS.s1) {
                Text(notice.title)
                    .font(DS.title())
                    .foregroundStyle(DS.textStrong)
                Text(notice.message)
                    .font(DS.caption())
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, DS.s3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.rLg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.rLg, style: .continuous)
                .stroke(DS.line, lineWidth: 0.5)
        }
        .shadow(
            color: DS.popoverShadow.color,
            radius: DS.popoverShadow.radius,
            x: DS.popoverShadow.x,
            y: DS.popoverShadow.y
        )
        .accessibilityElement(children: .combine)
    }
}

struct StickyNoteEditorView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var syncStore = SyncStatusStore.shared
    @StateObject private var viewModel: StickyNoteEditorViewModel
    @State private var isToolbarHovering = false
    @State private var isFindBarVisible = false
    @State private var isCommandPressed = false
    @State private var isTextOverlappingAttachmentTray = false

    init(note: Note, isPreview: Bool = false, startsLocked: Bool = false, initialKeyIssue: Error? = nil) {
        _viewModel = StateObject(wrappedValue: StickyNoteEditorViewModel(
            note: note,
            isPreview: isPreview,
            startsLocked: startsLocked,
            initialKeyIssue: initialKeyIssue
        ))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            editorTextView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !viewModel.attachments.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MacAttachmentTray(
                        noteId: viewModel.note.id,
                        attachments: viewModel.attachments,
                        isCommandPressed: isCommandPressed,
                        showsObscuringOverlay: isTextOverlappingAttachmentTray,
                        onOpen: { viewModel.openAttachment($0) },
                        onCopy: { viewModel.copyAttachment($0) },
                        onRemove: { viewModel.removeAttachment($0) },
                        thumbnailContent: nil
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                MacToolbarHoverRegion { hovering in
                    setToolbarHovering(hovering)
                }
                .frame(height: MacStickyEditorLayout.toolbarHoverRegionHeight)

                Spacer(minLength: 0)
            }
            .allowsHitTesting(true)

            if viewModel.isContentLocked {
                lockedContentOverlay
            }

            if !syncStore.isNetworkAvailable {
                Text("无网络")
                    .font(DS.caption())
                    .foregroundColor(DS.destructive)
                    .padding(.trailing, DS.s3)
                    .padding(.bottom, DS.s2)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            if let notice = viewModel.modeConversionNotice {
                MacNoteModeConversionToast(notice: notice)
                    .padding(.top, MacStickyEditorLayout.toolbarHoverRegionHeight + DS.s3)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
        }
        .overlay(alignment: .bottom) { attachmentNoticeOverlay }
        .animation(.snappy, value: viewModel.modeConversionNotice)
        // 内容延伸到工具栏下方供系统玻璃采样；首行留白由 MacTextView 计算。
        .ignoresSafeArea(edges: .top)
        .dsMacStickyToolbarScrollEdge()
        .navigationTitle("")
        .onAppear {
            viewModel.presentInitialKeyIssueIfNeeded()
            viewModel.loadAttachments()
        }
        .onDisappear { viewModel.onDisappear() }
        .onModifierKeysChanged(mask: .command) { _, modifiers in
            isCommandPressed = modifiers.contains(.command)
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultAttachmentsDidChange)) { notification in
            if let noteId = notification.object as? String {
                guard noteId == viewModel.note.id else { return }
            }
            viewModel.loadAttachments()
        }
        .onChange(of: viewModel.attachments.isEmpty) { _, isEmpty in
            if isEmpty {
                isTextOverlappingAttachmentTray = false
            }
        }
        .onChange(of: viewModel.forceClose) { _, shouldClose in
            if shouldClose {
                StickyNoteWindowManager.shared.closeWindow(for: viewModel.note.id)
            }
        }
        .onChange(of: viewModel.isContentLocked) { _, locked in
            if locked {
                hideFindInterface()
            }
        }
        .toolbar {
            ToolbarSpacer()
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.note.isEncrypted {
                    Button(action: { toggleEncryptionLock() }) {
                        Label(
                            viewModel.isContentLocked ? "解锁" : "上锁",
                            systemImage: viewModel.isContentLocked ? "lock.fill" : "lock.open.fill"
                        )
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                    }
                    .disabled(viewModel.isEncryptionToggling)
                    .help(viewModel.isContentLocked ? "解锁" : "上锁")
                }

                Button(action: { viewModel.copyNoteText() }) {
                    Label(
                        viewModel.didCopy ? "已复制" : "复制",
                        systemImage: viewModel.didCopy ? "checkmark" : "square.on.square"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: DS.macToolbarIconWidth)
                }
                .disabled(viewModel.isContentLocked)
                .help(viewModel.didCopy ? "已复制正文" : "复制正文")

                Menu {
                    Button(action: { viewModel.beginRenaming() }) {
                        Label("重命名…", systemImage: "pencil")
                    }

                    Button(action: { viewModel.presentImagePanel() }) {
                        Label("添加图片…", systemImage: "photo.badge.plus")
                    }

                    Divider()

                    Button("适应内容", systemImage: "arrow.up.left.and.arrow.down.right") {
                        viewModel.fitWindowToContent()
                    }
                    .disabled(viewModel.isContentLocked)
                    
                    Button(action: { toggleFindInterface() }) {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(viewModel.isContentLocked)

                    if viewModel.note.isEncrypted {
                        Divider()

                        Button(action: { viewModel.decryptPermanently() }) {
                            Label("转为明文笔记", systemImage: "lock.open")
                        }
                        .disabled(viewModel.isContentLocked || viewModel.isEncryptionToggling)
                    } else {
                        Divider()

                        Button(action: { viewModel.encryptAndLock() }) {
                            Label("转为加密笔记", systemImage: "lock")
                        }
                        .disabled(viewModel.isContentLocked || viewModel.isEncryptionToggling)
                    }

                    Divider()

                    Button(role: .destructive, action: { viewModel.deleteNote() }) {
                        Label("移到回收站", systemImage: "trash")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .disabled(viewModel.isContentLocked)
                .menuIndicator(.hidden)
                .help("更多")
            }
            ToolbarSpacer()
            ToolbarItem {
                if viewModel.isPinned {
                    Button(action: { viewModel.togglePin() }) {
                        Label("取消置顶", systemImage: "pin.fill")
                            .labelStyle(.iconOnly)
                            .frame(width: DS.macToolbarIconWidth)
                    }
                    .help("取消置顶")
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(DS.primary)
                } else {
                    Button(action: { viewModel.togglePin() }) {
                        Label("置顶", systemImage: "pin.fill")
                            .labelStyle(.iconOnly)
                            .frame(width: DS.macToolbarIconWidth)
                    }
                    .help("置顶")
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
            }
        }
        .alert(isPresented: $viewModel.showingDeleteConfirmation) {
            Alert(
                title: Text("删除这条笔记？"),
                message: Text("笔记将移到回收站，可以恢复。"),
                primaryButton: .destructive(Text("删除")) {
                    viewModel.confirmDelete()
                },
                secondaryButton: .cancel()
            )
        }
        .alert("需要密钥", isPresented: $viewModel.showingKeyIssueAlert) {
            Button("打开密钥设置") {
                MacMenuBarController.shared.openSettingsWindow(selectedTab: .advanced)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(viewModel.keyIssueMessage)
        }
    }

    private var editorTextView: some View {
        MacTextView(
            text: $viewModel.text,
            placeholder: "随便写点什么吧",
            fontSize: CGFloat(settings.editorFontSize),
            lineHeightMultiple: CGFloat(settings.editorLineHeightMultiple),
            bottomInset: MacStickyEditorLayout.editorBottomInset + viewModel.attachmentTrayHeight,
            autoFocus: true,
            isEditable: !viewModel.isContentLocked,
            onChange: { viewModel.textDidChange($0) },
            onSaveShortcut: { viewModel.saveImmediately() },
            onApplyShortcut: { viewModel.saveImmediately() },
            onFitToContent: { viewModel.fitWindowToContent() },
            onCopyShortcut: { viewModel.copyNoteText() },
            onFindShortcut: { toggleFindInterface() },
            onIncreaseFontSize: { adjustFontSize(by: 1) },
            onDecreaseFontSize: { adjustFontSize(by: -1) },
            onImportImages: { urls in viewModel.importAttachments(from: urls) },
            onAttachmentOverlapChange: { isOverlapping in
                isTextOverlappingAttachmentTray = isOverlapping
            },
            onFindVisibilityChange: { isVisible in
                isFindBarVisible = isVisible
                updateSystemToolbarBackground(
                    isActive: isVisible || isToolbarHovering,
                    showsSeparator: isVisible
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var attachmentNoticeOverlay: some View {
        if let notice = viewModel.attachmentNotice {
            Text(notice)
                .font(DS.caption())
                .foregroundStyle(DS.textStrong)
                .padding(.horizontal, DS.s3)
                .padding(.vertical, DS.s2)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, viewModel.attachmentTrayHeight + DS.s3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private var lockedContentOverlay: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(DS.textSubtle)
                .accessibilityLabel("已上锁")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func adjustFontSize(by delta: Double) {
        settings.editorFontSize = SettingsStore.clampedFontSize(settings.editorFontSize + delta)
    }

    private func toggleEncryptionLock() {
        viewModel.toggleEncryptionLock()
    }

    private func setToolbarHovering(_ hovering: Bool) {
        guard isToolbarHovering != hovering else { return }
        isToolbarHovering = hovering
        updateSystemToolbarBackground(
            isActive: hovering || isFindBarVisible,
            showsSeparator: isFindBarVisible
        )
    }

    private func updateSystemToolbarBackground(isActive: Bool, showsSeparator: Bool) {
        guard let window = editorWindow() else { return }
        AutoFocusTextView.setFindToolbarActive(isActive, showsSeparator: showsSeparator, in: window)
    }

    private func toggleFindInterface() {
        guard !viewModel.isContentLocked else { return }
        guard let window = NSApp.keyWindow else { return }
        guard let textView = editorTextView(in: window) else {
            let sender = FindPanelActionSender(tag: NSTextFinder.Action.showFindInterface.rawValue)
            AutoFocusTextView.setFindToolbarActive(true, showsSeparator: true, in: window)
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
            return
        }

        let scrollView = textView.enclosingScrollView as? ToolbarInsetScrollView
        let action: NSTextFinder.Action = scrollView?.isFindBarVisible == true
            ? .hideFindInterface
            : .showFindInterface
        let sender = FindPanelActionSender(tag: action.rawValue)

        AutoFocusTextView.setFindToolbarActive(
            action == .showFindInterface,
            showsSeparator: action == .showFindInterface,
            in: window
        )
        textView.performFindPanelAction(sender)
        DispatchQueue.main.async {
            scrollView?.syncFindToolbarAppearance()
        }
    }

    private func hideFindInterface() {
        guard let window = editorWindow(),
              let textView = editorTextView(in: window) else { return }
        let sender = FindPanelActionSender(tag: NSTextFinder.Action.hideFindInterface.rawValue)
        AutoFocusTextView.setFindToolbarActive(false, showsSeparator: false, in: window)
        textView.performFindPanelAction(sender)
        (textView.enclosingScrollView as? ToolbarInsetScrollView)?.syncFindToolbarAppearance()
        isFindBarVisible = false
    }

    private func editorTextView(in window: NSWindow) -> AutoFocusTextView? {
        if let textView = window.firstResponder as? AutoFocusTextView {
            return textView
        }
        return window.contentView?.firstDescendant(of: AutoFocusTextView.self)
    }

    private func editorWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == viewModel.note.id } ?? NSApp.keyWindow
    }
}

private final class FindPanelActionSender: NSObject {
    @objc let tag: Int

    init(tag: Int) {
        self.tag = tag
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}

enum MacStickyEditorLayout {
    static let editorHorizontalInset = DS.s4
    static let editorBottomInset: CGFloat = 28
    static let widthMultiplier: CGFloat = 30
    static let glyphSafetyInset: CGFloat = 3
    static let toolbarHoverRegionHeight: CGFloat = 72

    static func horizontalPadding(textContainerInsetWidth: CGFloat) -> CGFloat {
        textContainerInsetWidth * 2 + 8
    }

    static func fittedWindowWidth(fontSize: CGFloat) -> CGFloat {
        let inset = textContainerInset(fontSize: fontSize)
        return fontSize * widthMultiplier + horizontalPadding(textContainerInsetWidth: inset.width)
    }

    static func minimumFittedWindowHeight(fontSize: CGFloat) -> CGFloat {
        fittedWindowWidth(fontSize: fontSize) * 0.75
    }

    static func textContainerInset(fontSize: CGFloat) -> NSSize {
        let baseInset = MarkdownHighlighter.textContainerInset(size: fontSize)
        return NSSize(
            width: baseInset.width + editorHorizontalInset,
            height: baseInset.height
        )
    }
}

struct MacToolbarHoverRegion: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ToolbarHoverTrackingView {
        let view = ToolbarHoverTrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: ToolbarHoverTrackingView, context: Context) {
        nsView.onHover = onHover
    }
}

final class ToolbarHoverTrackingView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var pendingHoverOn: DispatchWorkItem?
    private var pendingHoverOff: DispatchWorkItem?
    private var isHovering = false
    private var mouseMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaRef = area
        addTrackingArea(area)
        updateHoverForCurrentMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(withWindowPoint: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(withWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        scheduleHoverOff()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            pendingHoverOn?.cancel()
            pendingHoverOn = nil
            pendingHoverOff?.cancel()
            pendingHoverOff = nil
            removeMouseMonitor()
            setHovering(false)
        } else {
            installMouseMonitor()
            DispatchQueue.main.async { [weak self] in
                self?.updateHoverForCurrentMouseLocation()
            }
        }
    }

    deinit {
        removeMouseMonitor()
    }

    private func scheduleHoverOn() {
        pendingHoverOff?.cancel()
        pendingHoverOff = nil
        pendingHoverOn?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.containsCurrentMouseLocation() else { return }
            self.setHovering(true)
        }
        pendingHoverOn = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
    }

    private func showHoverImmediately() {
        pendingHoverOff?.cancel()
        pendingHoverOff = nil
        pendingHoverOn?.cancel()
        pendingHoverOn = nil
        setHovering(true)
    }

    private func scheduleHoverOff() {
        pendingHoverOn?.cancel()
        pendingHoverOn = nil
        pendingHoverOff?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.containsCurrentMouseLocation() else { return }
            self.setHovering(false)
        }
        pendingHoverOff = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func containsCurrentMouseLocation() -> Bool {
        guard let window else { return false }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        let pointInView = convert(pointInWindow, from: nil)
        return bounds.contains(pointInView)
    }

    private func installMouseMonitor() {
        removeMouseMonitor()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.updateHover(with: event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func updateHoverForCurrentMouseLocation() {
        guard let window else { return }
        updateHover(withWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    private func updateHover(with event: NSEvent) {
        guard let window, event.window == window else { return }
        updateHover(withWindowPoint: event.locationInWindow)
    }

    private func updateHover(withWindowPoint pointInWindow: NSPoint) {
        let pointInView = convert(pointInWindow, from: nil)
        if bounds.contains(pointInView) {
            showHoverImmediately()
        } else if isHovering {
            scheduleHoverOff()
        }
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        onHover?(hovering)
    }
}

@MainActor
final class StickyNoteEditorViewModel: ObservableObject {
    @Published var note: Note
    @Published var text: String
    @Published var isPinned: Bool
    @Published var showingDeleteConfirmation = false
    @Published var didCopy = false
    @Published var forceClose = false
    @Published var isContentLocked = false
    @Published var ciphertextPreview = ""
    @Published var isEncryptionToggling = false
    @Published var modeConversionNotice: MacNoteModeConversionNotice?
    @Published var showingKeyIssueAlert = false
    @Published var keyIssueMessage = "请前往密钥设置处理。"
    @Published private(set) var attachments: [NoteAttachment] = []
    @Published var attachmentNotice: String?

    private let vaultStore = VaultStore.shared
    private let windowStore = MacNoteWindowStore.shared
    private let settings = SettingsStore.shared
    private let syncStore = SyncStatusStore.shared
    private let isPreview: Bool
    private var saveTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?
    private var modeConversionNoticeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var initialKeyIssue: Error?
    private var didGenerateLocalTitle = false

    var isContentEmpty: Bool {
        let body = isContentLocked ? note.body : text
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    var attachmentTrayHeight: CGFloat {
        attachments.isEmpty ? 0 : MacAttachmentTrayLayout.occupiedHeight
    }

    init(note: Note, isPreview: Bool = false, startsLocked: Bool = false, initialKeyIssue: Error? = nil) {
        self.note = note
        self.text = note.body
        self.isPreview = isPreview
        self.isPinned = windowStore.windowState(for: note.id)?.isPinned ?? true
        self.isContentLocked = startsLocked
        self.initialKeyIssue = initialKeyIssue

        $isPinned
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.windowStore.setPinned(newValue, for: self.note.id)
                StickyNoteWindowManager.shared.updateWindowLevel(for: self.note.id, isPinned: newValue)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sealNoteLockEncryptedNote)
            .sink { [weak self] notification in
                guard let self else { return }
                if let noteId = notification.object as? String, noteId != self.note.id { return }
                self.temporarilyLockContent()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sealNotePresentKeyIssue)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let noteId = notification.object as? String, noteId == self.note.id else { return }
                let error = notification.userInfo?["error"] as? Error ?? CryptoError.keyNotFound
                self.presentKeyIssue(error)
            }
            .store(in: &cancellables)
    }

    func presentInitialKeyIssueIfNeeded() {
        guard let error = initialKeyIssue else { return }
        initialKeyIssue = nil
        presentKeyIssue(error)
    }

    func onDisappear() {
        guard !forceClose else { return }
        handleWindowWillClose()
    }

    func textDidChange(_ newText: String) {
        guard !isContentLocked else { return }
        text = newText
        debouncedSave()
    }

    func loadAttachments() {
        let noteId = note.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.attachments = await self.vaultStore.loadAttachments(for: noteId)
            StickyNoteWindowManager.shared.updateAttachmentTray(for: noteId, height: self.attachmentTrayHeight)
        }
    }

    func presentImagePanel() {
        guard !isContentLocked, !isPreview else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls
            Task { @MainActor in
                self.importAttachments(from: urls)
            }
        }
    }

    func importAttachments(from urls: [URL]) {
        guard !isContentLocked, !isPreview, !urls.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { Self.cleanupClipboardImportURLs(urls) }
            syncStore.setSyncing()
            guard await flushPendingBodySave() else { return }
            let noteToUpdate = note
            let bodySnapshot = text
            do {
                let result = try await vaultStore.importImageAttachments(
                    from: urls,
                    for: noteToUpdate,
                    currentBody: bodySnapshot
                )
                note = result.note
                attachments = result.attachments
                StickyNoteWindowManager.shared.updateAttachmentTray(for: note.id, height: attachmentTrayHeight)
                syncStore.setSaved()
                if !result.skippedReasons.isEmpty {
                    showAttachmentNotice(result.skippedReasons.joined(separator: "、"))
                }
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
                showAttachmentNotice(error.localizedDescription)
            }
        }
    }

    private static func cleanupClipboardImportURLs(_ urls: [URL]) {
        let prefix = "SealNote-Clipboard-"
        for url in urls where url.deletingLastPathComponent() == FileManager.default.temporaryDirectory
            && url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func openAttachment(_ attachment: NoteAttachment) {
        guard !isContentLocked else { return }
        MacAttachmentQuickLookController.present(
            noteId: note.id,
            attachments: attachments,
            selected: attachment
        )
    }

    func copyAttachment(_ attachment: NoteAttachment) {
        guard !isContentLocked else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await vaultStore.attachmentURL(for: attachment, noteId: note.id)
                let data = try Data(contentsOf: url)
                let item = NSPasteboardItem()
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: attachment.contentType))
                if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                    item.setData(tiff, forType: .tiff)
                }
                item.setString(url.absoluteString, forType: .fileURL)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([item])
                showAttachmentNotice("已复制图片")
            } catch {
                showAttachmentNotice(error.localizedDescription)
            }
        }
    }

    func removeAttachment(_ attachment: NoteAttachment) {
        guard !isContentLocked, !isPreview else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            syncStore.setSyncing()
            guard await flushPendingBodySave() else { return }
            let noteToUpdate = note
            let bodySnapshot = text
            do {
                let result = try await vaultStore.removeAttachment(
                    id: attachment.id,
                    from: noteToUpdate,
                    currentBody: bodySnapshot
                )
                note = result.note
                attachments = result.attachments
                StickyNoteWindowManager.shared.updateAttachmentTray(for: note.id, height: attachmentTrayHeight)
                syncStore.setSaved()
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
                showAttachmentNotice(error.localizedDescription)
            }
        }
    }

    private func flushPendingBodySave() async -> Bool {
        let pendingSave = saveTask
        pendingSave?.cancel()
        saveTask = nil
        _ = await pendingSave?.value

        guard !isContentLocked else { return false }
        let bodySnapshot = text
        let noteToUpdate = note
        guard bodySnapshot != noteToUpdate.body else { return true }
        return await saveSnapshot(bodySnapshot, note: noteToUpdate)
    }

    private func showAttachmentNotice(_ message: String) {
        attachmentNotice = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if self?.attachmentNotice == message {
                self?.attachmentNotice = nil
            }
        }
    }

    func copyNoteText() {
        guard !isContentLocked else { return }
        let copiedText = settings.copyAddsParagraphSpacing
            ? MarkdownFormatter.stringByAddingMarkdownParagraphSpacing(to: text)
            : text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)

        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                self?.didCopy = false
            }
        }
    }

    func togglePin() {
        isPinned.toggle()
    }

    func beginRenaming() {
        guard !isPreview else { return }

        let alert = NSAlert()
        alert.messageText = "重命名笔记"
        alert.informativeText = "标题只影响列表、菜单和文件名，不会改写正文。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let titleField = NSTextField(
            string: vaultStore.displayTitle(for: note, emptyTitle: "")
        )
        titleField.placeholderString = "标题"
        titleField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        titleField.selectText(nil)
        alert.accessoryView = titleField

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            guard let cleanedTitle = NoteTitleFormatter.sanitizedGeneratedTitle(titleField.stringValue) else {
                self.syncStore.setFailed(message: "请输入有效标题。")
                return
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.vaultStore.renameNote(self.note, title: cleanedTitle)
                    self.syncStore.setSaved()
                } catch {
                    self.syncStore.setFailed(message: "重命名失败：\(error.localizedDescription)")
                }
            }
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    func toggleEncryptionLock() {
        guard !isEncryptionToggling else { return }
        if isContentLocked {
            unlockEncryptedContent()
        } else {
            temporarilyLockContent()
        }
    }

    func deleteNote() {
        if isContentEmpty {
            discardEmptyNoteAndClose(body: text)
            return
        }
        showingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard !isPreview else {
            text = ""
            note.body = ""
            return
        }

        Task {
            do {
                try await vaultStore.deleteNote(note)
                forceClose = true
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func saveImmediately() {
        guard !isContentLocked else {
            syncStore.setSaved()
            return
        }
        saveTask?.cancel()
        save()
    }

    func fitWindowToContent() {
        guard !isContentLocked else { return }
        StickyNoteWindowManager.shared.fitWindowToContent(
            noteId: note.id,
            text: text,
            fontSize: CGFloat(SettingsStore.shared.editorFontSize)
        )
    }

    func decryptPermanently() {
        guard note.isEncrypted, !isContentLocked else { return }
        saveTask?.cancel()
        isEncryptionToggling = true
        syncStore.setSyncing()
        let noteToDecrypt = note

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isEncryptionToggling = false }
            do {
                let updatedNote = try await self.vaultStore.decryptNotePermanently(noteToDecrypt)
                self.note = updatedNote
                self.text = updatedNote.body
                self.isContentLocked = false
                self.syncStore.setSaved()
                self.showModeConversionNotice(.plain)
            } catch {
                if self.isKeyIssue(error) {
                    self.presentKeyIssue(error)
                    return
                }
                self.syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    func encryptAndLock() {
        lockContent()
    }

    private func debouncedSave() {
        guard !isContentLocked else { return }
        saveTask?.cancel()

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            _ = await self?.saveSnapshot(bodyToSave, note: noteToUpdate)
        }
    }

    private func save() {
        guard !isContentLocked else {
            syncStore.setSaved()
            return
        }
        guard !isPreview else {
            note.body = text
            syncStore.setSaved()
            return
        }

        guard text != note.body else {
            syncStore.setSaved()
            return
        }

        syncStore.setSyncing()
        let bodyToSave = text
        let noteToUpdate = note

        Task {
            _ = await saveSnapshot(bodyToSave, note: noteToUpdate)
        }
    }

    private func saveSnapshot(_ snapshot: String, note noteToUpdate: Note) async -> Bool {
        do {
            try await vaultStore.updateNote(noteToUpdate, body: snapshot, renameIfUntitled: false)
            if let updatedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) {
                note = updatedNote
                await generateLocalTitleIfNeeded(
                    for: updatedNote,
                    body: snapshot,
                    requiresCompletedFirstLine: true
                )
            }
            syncStore.setSaved()
            return true
        } catch {
            if isKeyIssue(error) {
                presentKeyIssue(error)
                return false
            }
            syncStore.setFailed(message: error.localizedDescription)
            return false
        }
    }

    private func lockContent() {
        guard !isPreview else { return }
        guard vaultStore.isKeyLoaded else {
            presentKeyIssue(CryptoError.keyNotFound)
            return
        }

        guard !note.isEncrypted else {
            temporarilyLockContent()
            return
        }

        saveTask?.cancel()
        isEncryptionToggling = true
        syncStore.setSyncing()

        let bodyToEncrypt = text
        let noteToEncrypt = note
        let start = Date()
        recordCryptoEvent("note_encryption_started", noteId: noteToEncrypt.id, start: start, fields: [
            "body_bytes": bodyToEncrypt.utf8.count
        ])

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isEncryptionToggling = false }
            do {
                let result = try await self.vaultStore.encryptNoteForEditing(noteToEncrypt, body: bodyToEncrypt)
                self.recordCryptoEvent("note_encryption_finished", noteId: noteToEncrypt.id, start: start)
                self.note = result.note
                self.ciphertextPreview = result.ciphertext
                self.text = bodyToEncrypt
                self.isContentLocked = true
                self.syncStore.setSaved()
                self.showModeConversionNotice(.encrypted)
            } catch {
                self.recordCryptoEvent("note_encryption_failed", noteId: noteToEncrypt.id, start: start, fields: [
                    "error": error.localizedDescription
                ])
                if self.isKeyIssue(error) {
                    self.presentKeyIssue(error)
                    return
                }
                self.syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func temporarilyLockContent() {
        guard note.isEncrypted, !isContentLocked else { return }
        saveTask?.cancel()
        ciphertextPreview = ""
        isContentLocked = true
        syncStore.setSaved()
    }

    private func unlockEncryptedContent() {
        let noteToDecrypt = note
        let start = Date()
        isEncryptionToggling = true
        recordCryptoEvent("note_decryption_started", noteId: noteToDecrypt.id, start: start)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isEncryptionToggling = false }
            do {
                let decrypted = try await self.vaultStore.decryptEncryptedNoteBody(noteToDecrypt)
                self.recordCryptoEvent("note_decryption_finished", noteId: noteToDecrypt.id, start: start)
                self.note = Note(
                    id: noteToDecrypt.id,
                    body: decrypted,
                    createdAt: noteToDecrypt.createdAt,
                    updatedAt: noteToDecrypt.updatedAt,
                    isEncrypted: true
                )
                self.ciphertextPreview = ""
                self.text = decrypted
                self.isContentLocked = false
                self.syncStore.setSaved()
            } catch {
                self.recordCryptoEvent("note_decryption_failed", noteId: noteToDecrypt.id, start: start, fields: [
                    "error": error.localizedDescription
                ])
                if self.isKeyIssue(error) {
                    self.presentKeyIssue(error)
                    return
                }
                self.syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func presentKeyIssue(_ error: Error) {
        keyIssueMessage = keyIssueMessage(for: error)
        showingKeyIssueAlert = true
        syncStore.setFailed(message: keyIssueMessage)
    }

    private func showModeConversionNotice(_ notice: MacNoteModeConversionNotice) {
        modeConversionNoticeTask?.cancel()
        modeConversionNotice = notice
        modeConversionNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.modeConversionNotice = nil
        }
    }

    private func isKeyIssue(_ error: Error) -> Bool {
        if error is VaultKeyFileError { return true }
        if let cryptoError = error as? CryptoError {
            switch cryptoError {
            case .keyNotFound: return true
            default: return false
            }
        }
        return false
    }

    private func keyIssueMessage(for error: Error) -> String {
        if let keyError = error as? VaultKeyFileError {
            switch keyError {
            case .fileMissing:
                return "找不到密钥。请前往密钥设置处理。"
            case .fileMoved:
                return "密钥已不在原位置。请前往密钥设置处理。"
            case .permissionDenied:
                return "无法读取密钥。请前往密钥设置处理。"
            case .invalidFile:
                return "密钥格式无效。请前往密钥设置处理。"
            case .unsupportedFileExtension:
                return "请选择有效的 Seal Note 密钥。"
            case .keyReplaced:
                return "密钥已被替换或内容被修改。请前往密钥设置处理。"
            case .keyMismatch:
                return "密钥不匹配，无法解锁当前加密笔记。请前往密钥设置处理。"
            case .keyAlreadyConfigured:
                return "已经配置了密钥引用。"
            case .encryptedNotesExist:
                return "仍有加密笔记，请先在密钥设置中处理。"
            case .keyDownloadPending:
                return "密钥仍在从 iCloud 下载。下载完成后请再试一次。"
            }
        }

        return "请先前往密钥设置处理。"
    }

    private func recordCryptoEvent(
        _ event: String,
        noteId: String,
        start: Date,
        fields: [String: CustomStringConvertible?] = [:]
    ) {
        var payload = fields
        payload["note_id"] = noteId
        payload["elapsed_ms"] = String(format: "%.2f", Date().timeIntervalSince(start) * 1000)
        MaintenanceLogStore.shared.record(event, fields: payload)
    }

    private func handleWindowWillClose() {
        saveTask?.cancel()
        guard !isContentLocked else {
            syncStore.setSaved()
            return
        }
        let snapshot = text
        guard !isPreview else {
            note.body = snapshot
            syncStore.setSaved()
            return
        }

        guard settings.autoDeleteEmptyNotes,
              snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              attachments.isEmpty else {
            saveAndGenerateLocalTitleOnClose(snapshot: snapshot)
            return
        }

        discardEmptyNote(body: snapshot)
    }

    private func saveAndGenerateLocalTitleOnClose(snapshot: String) {
        let noteToUpdate = note
        syncStore.setSyncing()

        Task {
            let didSave: Bool
            if snapshot == noteToUpdate.body {
                syncStore.setSaved()
                didSave = true
            } else {
                didSave = await saveSnapshot(snapshot, note: noteToUpdate)
            }

            guard didSave,
                  let savedNote = vaultStore.readableNotes.first(where: { $0.id == noteToUpdate.id }) else {
                return
            }
            await generateLocalTitleIfNeeded(
                for: savedNote,
                body: snapshot,
                requiresCompletedFirstLine: false
            )
        }
    }

    private func generateLocalTitleIfNeeded(
        for savedNote: Note,
        body: String,
        requiresCompletedFirstLine: Bool
    ) async {
        guard !didGenerateLocalTitle else { return }
        guard !vaultStore.hasStableTitle(for: savedNote) else {
            didGenerateLocalTitle = true
            return
        }
        guard let candidate = Self.localTitleCandidate(
            in: body,
            requiresCompletedFirstLine: requiresCompletedFirstLine
        ) else {
            return
        }

        do {
            try await vaultStore.renameNote(
                savedNote,
                title: candidate.title,
                limitsLength: candidate.limitsLength
            )
            didGenerateLocalTitle = true
        } catch {
            // Local title generation is opportunistic; saving remains the source of truth.
        }
    }

    private static func localTitleCandidate(
        in body: String,
        requiresCompletedFirstLine: Bool
    ) -> (title: String, limitsLength: Bool)? {
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !requiresCompletedFirstLine || index < lines.count - 1 else { return nil }
            guard NoteTitleFormatter.sanitizedGeneratedTitle(
                trimmed,
                limitsLength: !NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: trimmed)
            ) != nil else {
                return nil
            }
            return (
                title: trimmed,
                limitsLength: !NoteTitleFormatter.firstNonEmptyLineIsMarkdownHeading(in: trimmed)
            )
        }

        return nil
    }

    private func discardEmptyNoteAndClose(body: String) {
        guard !isPreview else {
            text = ""
            note.body = ""
            return
        }

        saveTask?.cancel()
        Task {
            do {
                try await vaultStore.discardEmptyNote(note, body: body)
                syncStore.setSaved()
                forceClose = true
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }

    private func discardEmptyNote(body: String) {
        Task {
            do {
                try await vaultStore.discardEmptyNote(note, body: body)
                syncStore.setSaved()
            } catch {
                syncStore.setFailed(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - MacTextView

/// 正文延伸到工具栏下方，同时按窗口实测标题栏高度补齐首行留白。
private final class ToolbarInsetScrollView: NSScrollView {
    var baseInsets = NSEdgeInsets() {
        didSet { applyToolbarTopInset() }
    }
    var bottomInset: CGFloat = MacStickyEditorLayout.editorBottomInset {
        didSet {
            applyToolbarTopInset()
            scheduleAttachmentOverlapUpdate()
        }
    }
    var attachmentTrayHeight: CGFloat = 0 {
        didSet { scheduleAttachmentOverlapUpdate() }
    }
    var onAttachmentOverlapChange: ((Bool) -> Void)?
    var onFindVisibilityChange: ((Bool) -> Void)?
    private var lastFindBarVisibility: Bool?
    private weak var observedAttachmentClipView: NSClipView?
    private var attachmentBoundsObserver: NSObjectProtocol?
    private var attachmentOverlapUpdateScheduled = false
    private var lastAttachmentOverlap = false

    override var isFindBarVisible: Bool {
        didSet {
            syncFindToolbarAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyToolbarTopInset()
        syncFindToolbarAppearance()
        if window == nil {
            stopObservingAttachmentBounds()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.observeAttachmentBoundsIfNeeded()
                self?.scheduleAttachmentOverlapUpdate()
            }
        }
    }

    deinit {
        stopObservingAttachmentBounds()
    }

    override func layout() {
        super.layout()
        if let textView = documentView as? NSTextView {
            syncDocumentSize(textView)
        }
        applyToolbarTopInset()
        syncFindToolbarAppearance()
        observeAttachmentBoundsIfNeeded()
        scheduleAttachmentOverlapUpdate()
    }

    func syncDocumentSize(_ textView: NSTextView? = nil) {
        guard let textView = textView ?? documentView as? NSTextView else { return }
        guard let textContainer = textView.textContainer else { return }
        let width = max(1, contentView.bounds.width)
        let textWidth = max(
            1,
            width - textView.textContainerInset.width * 2 - MacStickyEditorLayout.glyphSafetyInset
        )
        textContainer.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textContainer)

        let usedHeight = textView.layoutManager?.usedRect(for: textContainer).height ?? 0
        let height = max(
            contentView.bounds.height,
            ceil(usedHeight + textView.textContainerInset.height * 2)
        )
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        if textView.frame != frame {
            textView.frame = frame
        }
        scheduleAttachmentOverlapUpdate()
    }

    func preservingVisibleOrigin(_ changes: () -> Void) {
        let origin = contentView.bounds.origin
        changes()
        let maxY = max(0, documentView?.bounds.height ?? 0 - contentView.bounds.height)
        let maxX = max(0, documentView?.bounds.width ?? 0 - contentView.bounds.width)
        let boundedOrigin = NSPoint(
            x: min(max(0, origin.x), maxX),
            y: min(max(0, origin.y), maxY)
        )
        contentView.scroll(to: boundedOrigin)
        reflectScrolledClipView(contentView)
        scheduleAttachmentOverlapUpdate()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        scheduleAttachmentOverlapUpdate()
    }

    func syncFindToolbarAppearance() {
        guard window != nil else { return }
        guard lastFindBarVisibility != isFindBarVisible else { return }
        lastFindBarVisibility = isFindBarVisible
        if let onFindVisibilityChange {
            onFindVisibilityChange(isFindBarVisible)
        } else {
            AutoFocusTextView.setFindToolbarActive(
                isFindBarVisible,
                showsSeparator: isFindBarVisible,
                in: window
            )
        }
    }

    private func applyToolbarTopInset() {
        let top: CGFloat
        if let window = window {
            top = max(0, window.frame.height - window.contentLayoutRect.height)
        } else {
            top = baseInsets.top
        }
        let target = NSEdgeInsets(
            top: top,
            left: baseInsets.left,
            bottom: bottomInset,
            right: baseInsets.right
        )
        guard !insetsEqual(contentInsets, target) else { return }
        contentInsets = target
        scrollerInsets = target
    }

    private func observeAttachmentBoundsIfNeeded() {
        guard window != nil else { return }
        if observedAttachmentClipView === contentView, attachmentBoundsObserver != nil {
            return
        }

        stopObservingAttachmentBounds()
        let clipView = contentView
        clipView.postsBoundsChangedNotifications = true
        observedAttachmentClipView = clipView
        attachmentBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleAttachmentOverlapUpdate()
        }
    }

    private func stopObservingAttachmentBounds() {
        if let attachmentBoundsObserver {
            NotificationCenter.default.removeObserver(attachmentBoundsObserver)
            self.attachmentBoundsObserver = nil
        }
        observedAttachmentClipView = nil
        attachmentOverlapUpdateScheduled = false
    }

    private func scheduleAttachmentOverlapUpdate() {
        guard !attachmentOverlapUpdateScheduled else { return }
        attachmentOverlapUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachmentOverlapUpdateScheduled = false
            self.updateAttachmentOverlap()
        }
    }

    private func updateAttachmentOverlap() {
        guard attachmentTrayHeight > 0,
              let textView = documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              window != nil,
              !textView.string.isEmpty,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0 else {
            publishAttachmentOverlap(false)
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else {
            publishAttachmentOverlap(false)
            return
        }

        let visibleFrameInWindow = contentView.convert(contentView.bounds, to: nil)
        let trayHeight = min(attachmentTrayHeight, visibleFrameInWindow.height)
        let trayBand = NSRect(
            x: visibleFrameInWindow.minX,
            y: visibleFrameInWindow.minY,
            width: visibleFrameInWindow.width,
            height: trayHeight
        )

        let sourceText = textView.string as NSString
        var overlaps = false
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, stop in
            guard lineGlyphRange.length > 0 else { return }
            let boundedRange = NSIntersectionRange(
                lineGlyphRange,
                NSRange(location: 0, length: sourceText.length)
            )
            guard boundedRange.length > 0 else { return }
            let lineText = sourceText.substring(with: boundedRange)
            guard lineText.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else {
                return
            }

            let lineInWindow = textView.convert(lineRect, to: nil)
            if lineInWindow.intersects(trayBand) {
                overlaps = true
                stop.pointee = true
            }
        }

        publishAttachmentOverlap(overlaps)
    }

    private func publishAttachmentOverlap(_ overlaps: Bool) {
        guard lastAttachmentOverlap != overlaps else { return }
        lastAttachmentOverlap = overlaps
        onAttachmentOverlapChange?(overlaps)
    }

    private func insetsEqual(_ a: NSEdgeInsets, _ b: NSEdgeInsets) -> Bool {
        a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right
    }
}

struct MacTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let bottomInset: CGFloat
    let autoFocus: Bool
    let isEditable: Bool
    let onChange: (String) -> Void
    let onSaveShortcut: () -> Void
    let onApplyShortcut: () -> Void
    let onFitToContent: () -> Void
    let onCopyShortcut: () -> Void
    let onFindShortcut: () -> Void
    let onIncreaseFontSize: () -> Void
    let onDecreaseFontSize: () -> Void
    let onImportImages: ([URL]) -> Void
    let onAttachmentOverlapChange: (Bool) -> Void
    let onFindVisibilityChange: (Bool) -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat,
        bottomInset: CGFloat = MacStickyEditorLayout.editorBottomInset,
        autoFocus: Bool = true,
        isEditable: Bool = true,
        onChange: @escaping (String) -> Void,
        onSaveShortcut: @escaping () -> Void,
        onApplyShortcut: @escaping () -> Void,
        onFitToContent: @escaping () -> Void,
        onCopyShortcut: @escaping () -> Void,
        onFindShortcut: @escaping () -> Void,
        onIncreaseFontSize: @escaping () -> Void,
        onDecreaseFontSize: @escaping () -> Void,
        onImportImages: @escaping ([URL]) -> Void = { _ in },
        onAttachmentOverlapChange: @escaping (Bool) -> Void = { _ in },
        onFindVisibilityChange: @escaping (Bool) -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        self.bottomInset = bottomInset
        self.autoFocus = autoFocus
        self.isEditable = isEditable
        self.onChange = onChange
        self.onSaveShortcut = onSaveShortcut
        self.onApplyShortcut = onApplyShortcut
        self.onFitToContent = onFitToContent
        self.onCopyShortcut = onCopyShortcut
        self.onFindShortcut = onFindShortcut
        self.onIncreaseFontSize = onIncreaseFontSize
        self.onDecreaseFontSize = onDecreaseFontSize
        self.onImportImages = onImportImages
        self.onAttachmentOverlapChange = onAttachmentOverlapChange
        self.onFindVisibilityChange = onFindVisibilityChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let scrollView = ToolbarInsetScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.autoresizesSubviews = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.bottomInset = bottomInset
        scrollView.attachmentTrayHeight = max(0, bottomInset - MacStickyEditorLayout.editorBottomInset)
        scrollView.onAttachmentOverlapChange = onAttachmentOverlapChange
        scrollView.onFindVisibilityChange = onFindVisibilityChange

        let textView = AutoFocusTextView()
        textView.coordinator = context.coordinator
        textView.isAutoFocusEnabled = autoFocus
        textView.registerForDraggedTypes([
            .fileURL,
            .png,
            .tiff
        ])

        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.layoutManager?.usesFontLeading = false

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
        }

        context.coordinator.configureTextView(textView, text: text, fontSize: fontSize)
        textView.delegate = context.coordinator

        if autoFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView as? ToolbarInsetScrollView,
              let textView = scrollView.documentView as? AutoFocusTextView else { return }

        context.coordinator.parent = self
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.attachmentTrayHeight = max(0, bottomInset - MacStickyEditorLayout.editorBottomInset)
        scrollView.onAttachmentOverlapChange = onAttachmentOverlapChange
        if scrollView.bottomInset != bottomInset {
            let previousBottomInset = scrollView.bottomInset
            let textLength = (textView.string as NSString).length
            let selection = textView.selectedRange()
            let caretIsAtEnd = selection.location >= textLength
            scrollView.preservingVisibleOrigin {
                scrollView.bottomInset = bottomInset
                scrollView.syncDocumentSize(textView)
            }
            if bottomInset > previousBottomInset, caretIsAtEnd,
               textView.window?.firstResponder === textView {
                textView.scrollRangeToVisible(NSRange(location: textLength, length: 0))
            }
        } else {
            scrollView.bottomInset = bottomInset
        }
        scrollView.onFindVisibilityChange = onFindVisibilityChange
        textView.isEditable = isEditable
        textView.isSelectable = isEditable

        // IME composition uses marked text; rewriting textStorage here cancels Chinese candidates.
        if textView.hasMarkedText() {
            textView.textContainerInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
            scrollView.syncDocumentSize(textView)
            if textView.placeholderLabel.string != placeholder {
                textView.placeholderLabel.string = placeholder
            }
            updatePlaceholderVisibility(textView)
            updatePlaceholderStyle(textView, fontSize: fontSize)
            return
        }

        if textView.isUpdating { return }
        textView.isUpdating = true
        defer { textView.isUpdating = false }

        let targetInset = MacStickyEditorLayout.textContainerInset(fontSize: fontSize)
        let needsExternalTextReplace = textView.string != text
        let needsStyleRefresh = context.coordinator.needsStyleRefresh(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        let needsInsetRefresh = !NSEqualSizes(textView.textContainerInset, targetInset)

        if needsExternalTextReplace {
            let selectedRanges = textView.selectedRanges
            let attributed = MarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
            scrollView.preservingVisibleOrigin {
                textView.textStorage?.setAttributedString(attributed)
                textView.selectedRanges = selectedRanges
            }
            context.coordinator.markStyleRendered(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        } else if needsStyleRefresh {
            let paraStyle = MarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
            let bodyFont = MarkdownHighlighter.bodyFont(size: fontSize)
            let baselineOff = MarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if fullRange.length > 0 {
                scrollView.preservingVisibleOrigin {
                    textView.textStorage?.addAttributes([
                        .font: bodyFont,
                        .paragraphStyle: paraStyle,
                        .baselineOffset: baselineOff
                    ], range: fullRange)
                    MarkdownHighlighter.applyMarkdownHighlighting(to: textView, lineHeightMultiple: lineHeightMultiple)
                }
            }
            context.coordinator.markStyleRendered(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        }

        if needsInsetRefresh {
            textView.textContainerInset = targetInset
        }
        if needsExternalTextReplace || needsStyleRefresh || needsInsetRefresh {
            scrollView.preservingVisibleOrigin {
                scrollView.syncDocumentSize(textView)
            }
        }

        if textView.placeholderLabel.string != placeholder {
            textView.placeholderLabel.string = placeholder
        }
        updatePlaceholderVisibility(textView)
        updatePlaceholderStyle(textView, fontSize: fontSize)

        if autoFocus, textView.window != nil, !textView.didInitialFocus {
            textView.didInitialFocus = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func updatePlaceholderStyle(_ textView: AutoFocusTextView, fontSize: CGFloat) {
        let bodyFont = MarkdownHighlighter.bodyFont(size: fontSize)
        let paraStyle = MarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
        let baselineOff = MarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
        textView.placeholderLabel.font = bodyFont
        textView.placeholderLabel.paragraphStyle = paraStyle
        textView.placeholderLabel.textColor = NSColor.placeholderTextColor
        textView.placeholderLabel.baselineOffset = baselineOff
    }

    private func updatePlaceholderVisibility(_ textView: AutoFocusTextView) {
        textView.placeholderLabel.isHidden = !textView.string.isEmpty
    }
}

// MARK: - Coordinator

extension MacTextView {
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextView
        private var lastText: String = ""
        private var lastRenderedFontSize: CGFloat = 0
        private var lastRenderedLineHeightMultiple: CGFloat = 0

        init(_ parent: MacTextView) {
            self.parent = parent
            super.init()
        }

        func configureTextView(_ textView: AutoFocusTextView, text: String, fontSize: CGFloat) {
            let attributed = MarkdownHighlighter.makeHighlightedAttributedString(text: text, fontSize: fontSize, lineHeightMultiple: fontSize == parent.fontSize ? parent.lineHeightMultiple : CGFloat(SettingsStore.defaultEditorLineHeightMultiple))
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = Self.typingAttributes(fontSize: fontSize, lineHeightMultiple: parent.lineHeightMultiple)
            lastText = text
            lastRenderedFontSize = fontSize
            lastRenderedLineHeightMultiple = parent.lineHeightMultiple
        }

        func needsStyleRefresh(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> Bool {
            lastRenderedFontSize != fontSize || lastRenderedLineHeightMultiple != lineHeightMultiple
        }

        func markStyleRendered(fontSize: CGFloat, lineHeightMultiple: CGFloat) {
            lastRenderedFontSize = fontSize
            lastRenderedLineHeightMultiple = lineHeightMultiple
        }

        static func typingAttributes(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> [NSAttributedString.Key: Any] {
            let bodyFont = MarkdownHighlighter.bodyFont(size: fontSize)
            return [
                .font: bodyFont,
                .foregroundColor: NSColor(DS.textBody),
                .paragraphStyle: MarkdownHighlighter.paragraphStyle(size: fontSize, multiple: lineHeightMultiple),
                .baselineOffset: MarkdownHighlighter.baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AutoFocusTextView, !textView.isUpdating else { return }
            // Defer binding writes and highlighting until the IME commits marked text.
            if textView.hasMarkedText() {
                parent.updatePlaceholderVisibility(textView)
                (textView.enclosingScrollView as? ToolbarInsetScrollView)?.syncDocumentSize(textView)
                return
            }

            textView.isUpdating = true
            defer { textView.isUpdating = false }
            let newText = textView.string
            parent.onChange(newText)
            lastText = newText
            let scrollView = textView.enclosingScrollView as? ToolbarInsetScrollView
            let refreshEditorState = {
                MarkdownHighlighter.applyMarkdownHighlighting(
                    to: textView,
                    lineHeightMultiple: self.parent.lineHeightMultiple,
                    limitedTo: textView.selectedRange()
                )
                self.markStyleRendered(fontSize: self.parent.fontSize, lineHeightMultiple: self.parent.lineHeightMultiple)
                textView.typingAttributes = Self.typingAttributes(fontSize: self.parent.fontSize, lineHeightMultiple: self.parent.lineHeightMultiple)
                self.parent.updatePlaceholderVisibility(textView)
                scrollView?.syncDocumentSize(textView)
            }
            if let scrollView {
                scrollView.preservingVisibleOrigin(refreshEditorState)
            } else {
                refreshEditorState()
            }
        }

        func textDidBeginEditing(_ notification: Notification) {}
        func textDidEndEditing(_ notification: Notification) {}
    }
}

// MARK: - AutoFocusTextView

    final class AutoFocusTextView: NSTextView {
        var isAutoFocusEnabled = true
        var isUpdating = false
        var didInitialFocus = false
        weak var coordinator: MacTextView.Coordinator?

        let placeholderLabel = PlaceholderLabel()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, isAutoFocusEnabled, !didInitialFocus {
            didInitialFocus = true
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }
    }

    override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if placeholderLabel.superview == nil {
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(placeholderLabel)
            let containerInset = textContainerInset
            let linePadding = textContainer?.lineFragmentPadding ?? 0
            NSLayoutConstraint.activate([
                placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: containerInset.width + linePadding),
                placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: containerInset.height)
            ])
            }
        }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            super.paste(sender)
            return
        }

        if let urls = imageURLs(from: pasteboard), !urls.isEmpty {
            coordinator?.parent.onImportImages(urls)
            return
        }

        if let temporaryURL = clipboardImageURL(from: pasteboard) {
            coordinator?.parent.onImportImages([temporaryURL])
            return
        }

        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEditable,
              let urls = imageURLs(from: sender.draggingPasteboard),
              !urls.isEmpty else {
            return []
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable else { return false }
        let pasteboard = sender.draggingPasteboard
        if let urls = imageURLs(from: pasteboard), !urls.isEmpty {
            coordinator?.parent.onImportImages(urls)
            return true
        }
        if let temporaryURL = clipboardImageURL(from: pasteboard) {
            coordinator?.parent.onImportImages([temporaryURL])
            return true
        }
        return false
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] else {
            return nil
        }
        let urls = objects.compactMap(\.filePathURL).filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        return urls
    }

    private func clipboardImageURL(from pasteboard: NSPasteboard) -> URL? {
        let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
        guard let imageData,
              let bitmap = NSBitmapImageRep(data: imageData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SealNote-Clipboard-\(UUID().uuidString).png")
        do {
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

        override func becomeFirstResponder() -> Bool {
            super.becomeFirstResponder()
            return true
        }

    override func performFindPanelAction(_ sender: Any?) {
        if !isEditable, findActionTag(from: sender) != NSTextFinder.Action.hideFindInterface.rawValue {
            return
        }
        updateToolbarAppearanceForFindAction(sender)
        super.performFindPanelAction(sender)
        DispatchQueue.main.async { [weak self] in
            (self?.enclosingScrollView as? ToolbarInsetScrollView)?.syncFindToolbarAppearance()
        }
    }

        override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            super.keyDown(with: event)
            return
        }

        let cmd = event.modifierFlags.contains(.command)
        let ctrl = event.modifierFlags.contains(.control)
        let opt = event.modifierFlags.contains(.option)
        let shift = event.modifierFlags.contains(.shift)

        let cmdOnly = cmd && !ctrl && !opt && !shift
        let cmdShiftOnly = cmd && shift && !ctrl && !opt
        let cmdOptOnly = cmd && opt && !ctrl && !shift

        if !isEditable {
            if (cmdOnly && ["c", "f", "s"].contains(chars.lowercased()))
                || (cmdShiftOnly && ["c", "s"].contains(chars.lowercased()))
                || (cmdOptOnly && chars.lowercased() == "f") {
                return
            }
            super.keyDown(with: event)
            return
        }

        if !cmd && !ctrl && !opt && !shift && event.keyCode == 36 {
            if completeMarkdownCodeFence() { return }
            if continueMarkdownList() { return }
        }

        if let action = ShortcutStore.shared.markdownAction(matching: event) {
            applyFormat(action.command); return
        }

        if let action = ShortcutStore.shared.editorAction(matching: event) {
            switch action {
            case .quickLineComment:
                toggleCurrentLineComment(); return
            }
        }

        if cmdShiftOnly && chars.lowercased() == "c" {
            coordinator?.parent.onCopyShortcut(); return
        }
        if cmdOnly && chars.lowercased() == "f" {
            coordinator?.parent.onFindShortcut(); return
        }
        if cmd && !ctrl && !opt && (chars == "+" || chars == "=") {
            coordinator?.parent.onIncreaseFontSize(); return
        }
        if cmdOnly && chars == "-" {
            coordinator?.parent.onDecreaseFontSize(); return
        }
        if cmdOnly && chars == "s" {
            coordinator?.parent.onSaveShortcut(); return
        }
        if cmdShiftOnly && chars == "s" {
            coordinator?.parent.onApplyShortcut(); return
        }
        if cmdOptOnly && chars == "f" {
            coordinator?.parent.onFitToContent(); return
        }

        super.keyDown(with: event)
    }

    static func setFindToolbarActive(_ isActive: Bool, showsSeparator: Bool, in window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = !isActive
        window.backgroundColor = isActive ? .white : .textBackgroundColor
        window.titlebarSeparatorStyle = showsSeparator ? .line : .automatic
    }

    private func updateToolbarAppearanceForFindAction(_ sender: Any?) {
        guard let tag = findActionTag(from: sender) else { return }
        if tag == NSTextFinder.Action.showFindInterface.rawValue {
            Self.setFindToolbarActive(true, showsSeparator: true, in: window)
        } else if tag == NSTextFinder.Action.hideFindInterface.rawValue {
            Self.setFindToolbarActive(false, showsSeparator: false, in: window)
        }
    }

    private func findActionTag(from sender: Any?) -> Int? {
        if let sender = sender as? NSMenuItem {
            return sender.tag
        }
        if let sender = sender as? NSControl {
            return sender.tag
        }
        if let sender = sender as? NSObject,
           sender.responds(to: #selector(getter: FindPanelActionSender.tag)) {
            return sender.value(forKey: "tag") as? Int
        }
        return nil
    }

        private func completeMarkdownCodeFence() -> Bool {
        guard isEditable else { return false }
        guard !hasMarkedText() else { return false }
        guard let result = MarkdownFormatter.completeCodeFenceIfNeeded(in: string, selection: selectedRange()) else {
            return false
        }
        applyTextResult(result.text, selection: result.selection)
        return true
    }

        private func continueMarkdownList() -> Bool {
        guard isEditable else { return false }
        guard !hasMarkedText() else { return false }
        guard let result = MarkdownFormatter.continueListIfNeeded(in: string, selection: selectedRange()) else {
            return false
        }
        applyTextResult(result.text, selection: result.selection)
        return true
    }

    private func applyFormat(_ command: MacMarkdownFormatCommand) {
        guard isEditable else { return }
        guard !hasMarkedText() else { return }

        let currentText = self.string
        let selection = self.selectedRange()
        let linkURL: String?
        if case .link = command {
            let pasteboard = NSPasteboard.general
            let clipboardString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)
            linkURL = MarkdownFormatter.webURL(fromClipboardString: clipboardString)
        } else {
            linkURL = nil
        }
        let result = MarkdownFormatter.apply(
            command: command,
            to: currentText,
            selection: selection,
            linkURL: linkURL
        )

        applyTextResult(result.text, selection: result.selection)
    }

    private func toggleCurrentLineComment() {
        guard isEditable, !hasMarkedText() else { return }
        let result = MarkdownFormatter.toggleLineComment(in: string, selection: selectedRange())
        applyTextResult(result.text, selection: result.selection)
    }

    private func applyTextResult(_ text: String, selection: NSRange) {
        isUpdating = true
        let fontSize = (coordinator?.parent.fontSize) ?? 14
        let lineHeightMultiple = (coordinator?.parent.lineHeightMultiple) ?? CGFloat(SettingsStore.defaultEditorLineHeightMultiple)
        let oldText = string
        let change = replacementChange(from: oldText, to: text)
        let scrollView = enclosingScrollView as? ToolbarInsetScrollView
        guard shouldChangeText(in: change.range, replacementString: change.replacement) else {
            isUpdating = false
            return
        }

        textStorage?.replaceCharacters(in: change.range, with: change.replacement)
        setSelectedRange(selection)
        didChangeText()
        coordinator?.parent.onChange(text)
        if let scrollView {
            scrollView.preservingVisibleOrigin {
                MarkdownHighlighter.applyMarkdownHighlighting(to: self, lineHeightMultiple: lineHeightMultiple)
                scrollView.syncDocumentSize(self)
            }
        } else {
            MarkdownHighlighter.applyMarkdownHighlighting(to: self, lineHeightMultiple: lineHeightMultiple)
        }
        typingAttributes = MacTextView.Coordinator.typingAttributes(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        coordinator?.markStyleRendered(fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
        if let placeholder = self.subviews.first(where: { $0 is PlaceholderLabel }) as? PlaceholderLabel {
            placeholder.isHidden = !text.isEmpty
        }
        isUpdating = false
    }

    private func replacementChange(from oldText: String, to newText: String) -> (range: NSRange, replacement: String) {
        let old = oldText as NSString
        let new = newText as NSString
        var prefix = 0
        while prefix < old.length,
              prefix < new.length,
              old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < old.length - prefix,
              suffix < new.length - prefix,
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) {
            suffix += 1
        }

        let oldLength = old.length - prefix - suffix
        let newLength = new.length - prefix - suffix
        let replacement = new.substring(with: NSRange(location: prefix, length: newLength))
        return (NSRange(location: prefix, length: oldLength), replacement)
    }

    @objc func markdownBold(_ sender: Any?) { applyFormat(.bold) }
    @objc func markdownItalic(_ sender: Any?) { applyFormat(.italic) }
    @objc func markdownUnderline(_ sender: Any?) { applyFormat(.underline) }
    @objc func markdownInlineCode(_ sender: Any?) { applyFormat(.inlineCode) }
    @objc func markdownInlineMath(_ sender: Any?) { applyFormat(.inlineMath) }
    @objc func markdownStrike(_ sender: Any?) { applyFormat(.strike) }
    @objc func markdownHTMLComment(_ sender: Any?) { applyFormat(.htmlComment) }
    @objc func markdownLink(_ sender: Any?) { applyFormat(.link) }
    @objc func markdownSave(_ sender: Any?) { coordinator?.parent.onSaveShortcut() }
    @objc func markdownApply(_ sender: Any?) { coordinator?.parent.onApplyShortcut() }
    @objc func markdownFitToContent(_ sender: Any?) { coordinator?.parent.onFitToContent() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard isEditable, window?.firstResponder == self else {
            return false
        }
        if let action = item.action {
            let markdownActions: [Selector] = [
                #selector(markdownBold(_:)),
                #selector(markdownItalic(_:)),
                #selector(markdownUnderline(_:)),
                #selector(markdownInlineCode(_:)),
                #selector(markdownInlineMath(_:)),
                #selector(markdownStrike(_:)),
                #selector(markdownHTMLComment(_:)),
                #selector(markdownLink(_:)),
                #selector(markdownSave(_:)),
                #selector(markdownApply(_:)),
                #selector(markdownFitToContent(_:))
            ]
            if markdownActions.contains(action) {
                return true
            }
        }
        return super.validateUserInterfaceItem(item)
    }
}

final class PlaceholderLabel: NSTextField {
    var paragraphStyle: NSParagraphStyle = .default
    var baselineOffset: CGFloat = 0

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        stringValue = ""
        font = .systemFont(ofSize: 14)
        textColor = .placeholderTextColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    var string: String {
        get { stringValue }
        set {
            stringValue = newValue
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? .systemFont(ofSize: 14),
                .foregroundColor: textColor ?? .placeholderTextColor,
                .paragraphStyle: paragraphStyle,
                .baselineOffset: baselineOffset
            ]
            attributedStringValue = NSAttributedString(string: newValue, attributes: attributes)
        }
    }
}

extension MarkdownHighlighter {
    static func applyMarkdownHighlighting(
        to textView: NSTextView,
        lineHeightMultiple: CGFloat,
        limitedTo changedRange: NSRange? = nil
    ) {
        guard let textStorage = textView.textStorage else { return }
        guard !textView.hasMarkedText() else { return }

        let selectedRanges = textView.selectedRanges

        let text = textView.string
        let fontSize = textView.font?.pointSize ?? CGFloat(SettingsStore.shared.editorFontSize)

        let bodyFont = bodyFont(size: fontSize)
        let paraStyle = paragraphStyle(size: fontSize, multiple: lineHeightMultiple)
        let baselineOff = baselineOffset(size: fontSize, font: bodyFont, multiple: lineHeightMultiple)

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let targetRange = highlightTargetRange(
            changedRange,
            in: nsText,
            fullRange: fullRange
        )
        let undoManager = textView.undoManager
        let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled ?? false
        if wasUndoRegistrationEnabled {
            undoManager?.disableUndoRegistration()
        }
        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: bodyFont,
            .foregroundColor: NSColor(DS.textBody),
            .paragraphStyle: paraStyle,
            .baselineOffset: baselineOff
        ], range: targetRange)

        let targetText = nsText.substring(with: targetRange)
        let spans = highlight(targetText)
        for span in spans {
            let attrs = attributes(for: span.role, fontSize: fontSize)
            var merged = attrs
            if merged[.paragraphStyle] == nil {
                merged[.paragraphStyle] = paraStyle
            }
            if merged[.baselineOffset] == nil {
                merged[.baselineOffset] = baselineOff
            }
            textStorage.addAttributes(
                merged,
                range: NSRange(location: targetRange.location + span.range.location, length: span.range.length)
            )
        }

        textStorage.endEditing()
        if wasUndoRegistrationEnabled {
            undoManager?.enableUndoRegistration()
        }
        textView.selectedRanges = selectedRanges
        textView.typingAttributes = [
            .font: bodyFont,
            .foregroundColor: NSColor(DS.textBody),
            .paragraphStyle: paraStyle,
            .baselineOffset: baselineOff
        ]
    }

    private static func highlightTargetRange(
        _ changedRange: NSRange?,
        in nsText: NSString,
        fullRange: NSRange
    ) -> NSRange {
        guard nsText.length > 4_000,
              let changedRange,
              nsText.range(of: "```").location == NSNotFound,
              nsText.range(of: "~~~").location == NSNotFound else {
            return fullRange
        }

        let safeLocation = min(max(changedRange.location, 0), nsText.length)
        let safeLength = min(changedRange.length, max(0, nsText.length - safeLocation))
        var range = nsText.lineRange(for: NSRange(location: safeLocation, length: safeLength))

        if range.location > 0 {
            let previousLocation = max(0, range.location - 1)
            let previousLine = nsText.lineRange(for: NSRange(location: previousLocation, length: 0))
            range = NSUnionRange(previousLine, range)
        }

        let rangeEnd = range.location + range.length
        if rangeEnd < nsText.length {
            let nextLine = nsText.lineRange(for: NSRange(location: rangeEnd, length: 0))
            range = NSUnionRange(range, nextLine)
        }

        return NSIntersectionRange(range, fullRange)
    }
}

#endif

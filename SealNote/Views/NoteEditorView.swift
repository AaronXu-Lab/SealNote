import SwiftUI

#if os(iOS)
import UIKit
#endif

enum NoteEditorMode {
    case create
    case edit(Note)
}

enum NoteEditorPresentation: Equatable {
    case sheet
    case window
}

struct NoteEditorView: View {
    let mode: NoteEditorMode
    let initialBody: String
    let presentation: NoteEditorPresentation
    let treatsNoteAsNewFlow: Bool
    let onSave: (String, Bool) async throws -> Note?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var session: EditorSession

    @State private var noteBody: String = ""
    @State private var isEncrypted: Bool = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var persistedNote: Note?
    @State private var lastSavedBody = ""
    @State private var lastSavedEncrypted = false
    @State private var didConfigureInitialState = false
    @State private var didDiscardEmptyNote = false
    @State private var shouldSkipDisappearPersistence = false
    @State private var isMarkdownPreviewing = false
    @State private var isTextEditing = false
    @State private var isFullScreen = false
    @State private var showDeleteConfirmation = false

    @State private var showFirstKeyPrompt = false
    @State private var showKeySettings = false
    @State private var showTrashFromKeySettings = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingNote: Note? {
        if case .edit(let note) = mode { return note }
        return nil
    }

    private var currentPersistedNote: Note? {
        persistedNote ?? editingNote
    }

    private var hasUnsavedChanges: Bool {
        session.hasUnsavedChanges
    }

    private var isNewFlow: Bool {
        if case .create = mode { return true }
        return treatsNoteAsNewFlow
    }

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #endif

    init(
        mode: NoteEditorMode,
        initialBody: String = "",
        presentation: NoteEditorPresentation = .sheet,
        treatsNoteAsNewFlow: Bool = false,
        onSave: @escaping (String, Bool) async throws -> Note?
    ) {
        self.mode = mode
        self.initialBody = initialBody
        self.presentation = presentation
        self.treatsNoteAsNewFlow = treatsNoteAsNewFlow
        self.onSave = onSave

        // Existing notes must be present before SwiftUI creates the underlying
        // UITextView. Injecting a full body from `onAppear` causes UIKit to
        // rebuild attributed text while SwiftUI is measuring the sheet, which
        // can lock the main thread in repeated text/layout updates.
        if case .edit(let note) = mode {
            _noteBody = State(initialValue: note.body)
            _isEncrypted = State(initialValue: note.isEncrypted)
            _persistedNote = State(initialValue: note)
            _lastSavedBody = State(initialValue: note.body)
            _lastSavedEncrypted = State(initialValue: note.isEncrypted)
            _didConfigureInitialState = State(initialValue: true)
        }

        let editingNote: Note? = { if case .edit(let note) = mode { return note } else { return nil } }()
        let shouldDiscardAsNewFlow: Bool = {
            if case .create = mode { return true }
            return treatsNoteAsNewFlow
        }()
        _session = StateObject(wrappedValue: EditorSession(
            initialNote: editingNote,
            initialBody: editingNote?.body ?? initialBody,
            initialEncrypted: editingNote?.isEncrypted ?? false,
            autoDiscardEmpty: { shouldDiscardAsNewFlow },
            create: onSave,
            update: { note, body in
                try await VaultStore.shared.updateNote(note, body: body, renameIfUntitled: false)
                return VaultStore.shared.readableNotes.first(where: { $0.id == note.id }) ?? note
            },
            convert: { note, body, mode in
                try await VaultStore.shared.updateNoteMode(note, body: body, mode: mode)
            },
            discardEmpty: { note, body in
                try await VaultStore.shared.discardEmptyNote(note, body: body)
            },
            generateTitle: { note, body, requiresCompletedFirstLine in
                let store = VaultStore.shared
                guard !store.hasStableTitle(for: note),
                      let candidate = NoteTitleFormatter.localTitleCandidate(
                        in: body,
                        requiresCompletedFirstLine: requiresCompletedFirstLine
                      ) else { return }
                try? await store.renameNote(note, title: candidate.title, limitsLength: candidate.limitsLength)
            }
        ))
    }

    var body: some View {
        editorPresentation
            .onAppear { configureInitialState() }
            .onChange(of: noteBody) { _, _ in
                guard didConfigureInitialState else { return }
                session.noteDidChange(body: noteBody, isEncrypted: isEncrypted)
            }
            .onChange(of: isEncrypted) { _, _ in
                guard didConfigureInitialState else { return }
                session.noteDidChange(body: noteBody, isEncrypted: isEncrypted)
            }
            .onChange(of: session.isSaving) { _, saving in isSaving = saving }
            .onChange(of: session.persistedNote) { _, note in persistedNote = note }
            .onChange(of: session.lastSaveError) { _, err in
                if let err { errorMessage = err; showError = true }
            }
            .onDisappear {
                persistBeforeViewDisappears()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active && !shouldSkipDisappearPersistence {
                    flushInBackground()
                }
            }
    }

    @ViewBuilder
    private var editorPresentation: some View {
        #if os(iOS)
        if presentation == .sheet && isPad {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(isFullScreen ? 0 : 0.28).ignoresSafeArea()
                    editorNavigation
                        .frame(
                            width: isFullScreen ? geometry.size.width : min(620, geometry.size.width - 32),
                            height: isFullScreen ? geometry.size.height : max(0, geometry.size.height - 48)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 28))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background((isFullScreen ? DS.surfaceRaised : Color.clear).ignoresSafeArea())
            }
            .presentationBackground(.clear)
        } else {
            editorNavigation
        }
        #else
        editorNavigation
        #endif
    }

    private var editorNavigation: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editorBody
            }
            #if os(iOS)
            .background(DS.surfaceRaised.ignoresSafeArea())
            #else
            .dsCanvasBackground()
            #endif
            .navigationBarTitleDisplayMode(.inline)
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #else
            .dsLiquidGlassToolbar()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { closeEditor() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(isSaving)
                }

                #if os(iOS)
                if presentation == .sheet && isPad {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                isFullScreen.toggle()
                            }
                        } label: {
                            Image(systemName: isFullScreen
                                  ? "arrow.down.right.and.arrow.up.left"
                                  : "arrow.up.left.and.arrow.down.right")
                        }
                        .accessibilityLabel(isFullScreen ? "退出全屏" : "全屏编辑")
                        .disabled(isSaving)
                    }
                }
                if presentation == .sheet && isPad && supportsMultipleWindows {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            moveEditorToWindow()
                        } label: {
                            Image(systemName: "rectangle.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel("在新窗口中打开")
                        .disabled(isSaving)
                    }

                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .confirmationAction)
                    }
                }
                #endif

                ToolbarItemGroup(placement: .confirmationAction) {
                    if MobileFeatureVisibility.markdownPreview {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isMarkdownPreviewing.toggle()
                            }
                        } label: {
                            Image(systemName: isMarkdownPreviewing ? "pencil" : "eye")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel(isMarkdownPreviewing ? "返回编辑" : "Markdown 预览")
                        .disabled(isSaving)
                    }

                    Button {
                        copyNoteText()
                    } label: {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("复制正文")
                    .disabled(noteBody.isEmpty)

                    Menu {
                        Button {
                            copyNoteText()
                        } label: {
                            Label("复制全部", systemImage: "square.on.square")
                        }
                        .disabled(noteBody.isEmpty)

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除笔记", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("更多")

                    if MobileFeatureVisibility.encryptionActions && !isEditing {
                        Button {
                            toggleEncryption()
                        } label: {
                            Image(systemName: isEncrypted ? "lock.fill" : "lock.open")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isEncrypted ? DS.primaryDeep : DS.textSecondary)
                        }
                        .disabled(isSaving)
                    }

                    if isSaving {
                        ProgressView()
                    }
                }
            }
            .alert("保存失败", isPresented: $showError) {
                Button("确定") {}
            } message: {
                Text(errorMessage)
            }
            .alert("删除笔记", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    deleteCurrentNote()
                }
            } message: {
                Text(currentPersistedNote == nil ? "这条未保存的笔记将被丢弃。" : "删除后笔记将进入回收站。")
            }
            .alert(keyPromptTitle, isPresented: Binding(
                get: { MobileFeatureVisibility.encryptionActions && showFirstKeyPrompt },
                set: { showFirstKeyPrompt = $0 }
            )) {
                Button("打开密钥设置") { showKeySettings = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text(keyPromptMessage)
            }
            .iPadSettingsSheet(isPresented: $showKeySettings) {
                SettingsView(
                    isPresented: $showKeySettings,
                    showTrash: $showTrashFromKeySettings,
                    initialRoute: .key
                )
            }
        }
        .interactiveDismissDisabled(
            isSaving
                || hasUnsavedChanges
                || shouldCreateInitialNote
                || shouldDiscardEmptyExistingNote
                || (presentation == .sheet && isTextEditing)
        )
        .sheet(isPresented: $showTrashFromKeySettings) {
            TrashView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        #if os(iOS)
        NoteEditorContentView(
            text: $noteBody,
            selectedRange: $editorSelection,
            isEditing: $isTextEditing,
            isPreviewing: MobileFeatureVisibility.markdownPreview && isMarkdownPreviewing,
            fontSize: CGFloat(settings.editorFontSize),
            lineHeightMultiple: CGFloat(settings.editorLineHeightMultiple),
            autofocus: isNewFlow || isTextEditing,
            noteID: currentPersistedNote?.id
        )
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if noteBody.isEmpty {
                        Text("随便写点什么吧")
                            .font(DS.bodyLg())
                            .foregroundColor(DS.textSubtle)
                            .padding(DS.cardPadding)
                    }

                    TextEditor(text: $noteBody)
                        .font(DS.bodyLg())
                        .foregroundColor(DS.textBody)
                        .scrollContentBackground(.hidden)
                        .padding(DS.cardPadding)
                }
                .frame(minHeight: 360)
            }
            .padding(DS.cardPadding)
            .frame(maxWidth: DS.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        #endif
    }

    private func closeEditor() {
        persistCurrentSnapshot(dismissAfterSave: true, discardEmptyIfNeeded: true)
    }

    #if os(iOS)
    private func moveEditorToWindow() {
        guard presentation == .sheet, isPad, supportsMultipleWindows else { return }
        Task {
            do {
                let note = try await session.prepareForWindowTransfer()
                persistedNote = note
                let registry = IPadNoteWindowRegistry.shared
                registry.markOpening(note.id)
                openWindow(id: IPadNoteWindowScene.id, value: note.id)
                for _ in 0..<30 {
                    if registry.isRegistered(note.id) {
                        shouldSkipDisappearPersistence = true
                        dismiss()
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                registry.cancelOpening(note.id)
                throw EditorSessionError.windowCreationFailed
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    #endif

    private func deleteCurrentNote() {
        Task {
            await session.flush(reason: .delete)
            let note = session.persistedNote ?? currentPersistedNote
            do {
                if let note {
                    if isNewFlow && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try await vaultStore.discardEmptyNote(note, body: noteBody)
                    } else {
                        try await vaultStore.deleteNote(note)
                    }
                    #if os(iOS)
                    IPadTemporaryNoteRegistry.shared.finish(note.id)
                    #endif
                }
                shouldSkipDisappearPersistence = true
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    /// Flush pending edits when leaving the foreground, protected by a background task so
    /// the write survives the iOS suspension window (P0-5).
    private func flushInBackground() {
        #if os(iOS)
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        Task {
            await session.flush(reason: .background)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        #endif
    }

    private func persistBeforeViewDisappears() {
        guard didConfigureInitialState else { return }
        guard !shouldSkipDisappearPersistence else { return }
        if showKeySettings {
            if hasUnsavedChanges || shouldCreateInitialNote {
                persistCurrentSnapshot()
            }
            return
        }
        persistCurrentSnapshot(discardEmptyIfNeeded: true)
    }

    private func persistCurrentSnapshot(
        dismissAfterSave: Bool = false,
        discardEmptyIfNeeded: Bool = false
    ) {
        Task {
            await saveCurrentSnapshot(
                dismissAfterSave: dismissAfterSave,
                discardEmptyIfNeeded: discardEmptyIfNeeded
            )
        }
    }

    @MainActor
    private func saveCurrentSnapshot(
        dismissAfterSave: Bool = false,
        discardEmptyIfNeeded: Bool = false
    ) async {
        guard didConfigureInitialState else {
            if dismissAfterSave { dismiss() }
            return
        }
        // The EditorSession is the sole writer (debounced, one-in-flight, newest wins).
        if discardEmptyIfNeeded {
            await session.close()   // flush pending edits + apply the auto-discard-empty rule
        } else {
            await session.flush(reason: .background)
        }
        if let error = session.lastSaveError {
            errorMessage = error
            showError = true
            return
        }
        persistedNote = session.persistedNote
        #if os(iOS)
        if isNewFlow, let createdNoteID = session.createdNoteID {
            IPadTemporaryNoteRegistry.shared.finish(createdNoteID)
        }
        #endif
        lastSavedBody = noteBody
        lastSavedEncrypted = isEncrypted
        if dismissAfterSave { dismiss() }
    }

    private func copyNoteText() {
        #if os(iOS)
        UIPasteboard.general.string = noteBody
        #endif
    }

    private func convertCurrentNote(to mode: NoteMode) {
        guard currentPersistedNote != nil else { return }
        if mode == .encrypted && !vaultStore.isKeyLoaded {
            showFirstKeyPrompt = true
            return
        }
        // Flush + convert in place; the editor stays open (P0-5 — no dismiss).
        Task {
            do {
                try await session.convertMode(to: mode)
                if let converted = session.persistedNote {
                    persistedNote = converted
                    isEncrypted = converted.isEncrypted
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func toggleEncryption() {
        if isEncrypted {
            isEncrypted = false
            settings.preferredNoteMode = .plain
        } else {
            if !vaultStore.isKeyLoaded {
                showFirstKeyPrompt = true
            } else {
                isEncrypted = true
                settings.preferredNoteMode = .encrypted
            }
        }
    }

    private func configureInitialState() {
        guard !didConfigureInitialState else { return }

        if case .edit(let note) = mode {
            noteBody = note.body
            isEncrypted = note.isEncrypted
            persistedNote = note
        } else {
            noteBody = initialBody
            isEncrypted = false

        }
        lastSavedBody = noteBody
        lastSavedEncrypted = isEncrypted
        didConfigureInitialState = true
    }

    private var shouldCreateInitialNote: Bool {
        currentPersistedNote == nil && !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldDiscardEmptyExistingNote: Bool {
        isNewFlow
            && !didDiscardEmptyNote
            && currentPersistedNote != nil
            && noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var keyPromptTitle: String {
        #if os(iOS)
        if case .invalid = vaultStore.iosKeyStatus {
            return "密钥失效"
        }
        #endif
        return "需要密钥"
    }

    private var keyPromptMessage: String {
        #if os(iOS)
        if case .invalid = vaultStore.iosKeyStatus {
            return "当前本机密钥不可用，需要前往设置页重新导入密钥或处理加密笔记。"
        }
        #endif
        return "需要先前往设置页创建或加载密钥。"
    }

}

import Foundation
import Combine

/// Owns the editor's debounced autosave lifecycle and serializes concurrent
/// persistence requests into one drain loop.
@MainActor
final class EditorSession: ObservableObject {
    enum FlushReason {
        case debounce
        case background
        case close
        case convert
        case delete
    }

    @Published private(set) var persistedNote: Note?
    @Published private(set) var isSaving = false
    @Published var lastSaveError: String?
    @Published private(set) var createdNoteID: String?

    private let debounceInterval: TimeInterval
    private let autoDiscardEmpty: () -> Bool
    private let create: (String, Bool) async throws -> Note?
    private let update: (Note, String) async throws -> Note
    private let convert: (Note, String, NoteMode) async throws -> Note
    private let discardEmpty: (Note, String) async throws -> Void

    private let generateTitle: (Note, String, Bool) async -> Void

    private var currentBody: String
    private var currentEncrypted: Bool
    private var revision = 0
    private var savedRevision = 0
    private var debounceTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var closeRequested = false

    init(
        initialNote: Note?,
        initialBody: String = "",
        initialEncrypted: Bool = false,
        debounceInterval: TimeInterval = 0.5,
        autoDiscardEmpty: @escaping () -> Bool = { false },
        create: @escaping (String, Bool) async throws -> Note?,
        update: @escaping (Note, String) async throws -> Note,
        convert: @escaping (Note, String, NoteMode) async throws -> Note,
        discardEmpty: @escaping (Note, String) async throws -> Void,
        generateTitle: @escaping (Note, String, Bool) async -> Void = { _, _, _ in }
    ) {
        self.persistedNote = initialNote
        self.currentBody = initialBody
        self.currentEncrypted = initialEncrypted
        self.debounceInterval = debounceInterval
        self.autoDiscardEmpty = autoDiscardEmpty
        self.create = create
        self.update = update
        self.convert = convert
        self.discardEmpty = discardEmpty
        self.generateTitle = generateTitle
    }

    var hasUnsavedChanges: Bool {
        revision != savedRevision
    }

    func noteDidChange(body: String, isEncrypted: Bool) {
        currentBody = body
        currentEncrypted = isEncrypted
        revision += 1
        debounceTask?.cancel()

        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.flush(reason: .debounce)
        }
    }

    func flush(reason: FlushReason) async {
        debounceTask?.cancel()
        guard savedRevision != revision else { return }

        let task: Task<Void, Never>
        if let drainTask {
            task = drainTask
        } else {
            let createdTask = Task { [weak self] in
                guard let self else { return }
                await self.drainLoop()
            }
            drainTask = createdTask
            task = createdTask
        }
        await task.value
    }

    func close() async {
        guard !closeRequested else { return }
        closeRequested = true
        debounceTask?.cancel()
        await flush(reason: .close)
        guard lastSaveError == nil else {
            closeRequested = false
            return
        }

        if let note = persistedNote {
            await generateTitle(note, currentBody, false)
        }

        if autoDiscardEmpty(),
           let note = persistedNote,
           currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await discardEmpty(note, currentBody)
            persistedNote = nil
        }
    }

    func prepareForWindowTransfer() async throws -> Note {
        debounceTask?.cancel()
        await flush(reason: .close)
        if let lastSaveError {
            throw EditorSessionError.saveFailed(lastSaveError)
        }
        if let persistedNote {
            return persistedNote
        }

        isSaving = true
        defer { isSaving = false }
        guard let note = try await create(currentBody, currentEncrypted) else {
            throw EditorSessionError.noteCreationFailed
        }
        persistedNote = note
        createdNoteID = note.id
        savedRevision = revision
        return note
    }

    func convertMode(to mode: NoteMode) async throws {
        await flush(reason: .convert)
        guard let note = persistedNote else { return }
        persistedNote = try await convert(note, currentBody, mode)
        savedRevision = revision
    }

    private func drainLoop() async {
        isSaving = true
        while savedRevision != revision {
            let targetRevision = revision
            let body = currentBody
            let encrypted = currentEncrypted

            do {
                if let note = persistedNote {
                    if note.isEncrypted != encrypted {
                        persistedNote = try await convert(
                            note,
                            body,
                            encrypted ? .encrypted : .plain
                        )
                    } else {
                        persistedNote = try await update(note, body)
                    }
                } else if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    persistedNote = try await create(body, encrypted)
                    createdNoteID = persistedNote?.id
                }
                if let note = persistedNote {
                    await generateTitle(note, body, true)
                }
                savedRevision = max(savedRevision, targetRevision)
                lastSaveError = nil
            } catch {
                lastSaveError = error.localizedDescription
                break
            }
        }
        isSaving = false
        drainTask = nil
    }
}

nonisolated enum EditorSessionError: Error, LocalizedError {
    case noteCreationFailed
    case saveFailed(String)
    case windowCreationFailed

    var errorDescription: String? {
        switch self {
        case .noteCreationFailed:
            return "无法创建笔记窗口。"
        case .saveFailed(let message):
            return message
        case .windowCreationFailed:
            return "无法创建独立窗口，当前编辑内容仍保留在这里。"
        }
    }
}

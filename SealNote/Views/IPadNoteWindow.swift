#if os(iOS)
import SwiftUI
import Combine
import UIKit

enum IPadNoteWindowScene {
    static let id = "note-editor"
}

@MainActor
final class IPadNoteWindowRegistry: ObservableObject {
    static let shared = IPadNoteWindowRegistry()

    @Published private(set) var noteIDs: Set<String> = []
    private var registeredNoteIDs: Set<String> = []

    private init() {}

    func contains(_ noteID: String) -> Bool {
        noteIDs.contains(noteID)
    }

    func markOpening(_ noteID: String) {
        noteIDs.insert(noteID)
    }

    func isRegistered(_ noteID: String) -> Bool {
        registeredNoteIDs.contains(noteID)
    }

    func cancelOpening(_ noteID: String) {
        guard !registeredNoteIDs.contains(noteID) else { return }
        noteIDs.remove(noteID)
    }

    func register(_ noteID: String) {
        noteIDs.insert(noteID)
        registeredNoteIDs.insert(noteID)
    }

    func unregister(_ noteID: String) {
        registeredNoteIDs.remove(noteID)
        noteIDs.remove(noteID)
    }
}

@MainActor
final class IPadTemporaryNoteRegistry {
    static let shared = IPadTemporaryNoteRegistry()

    private let defaults: UserDefaults
    private let defaultsKey = "SNIPadTemporaryNewNoteIDs"
    private var didBeginLaunchCleanup = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var noteIDs: Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    func register(_ noteID: String) {
        var ids = noteIDs
        ids.insert(noteID)
        defaults.set(Array(ids).sorted(), forKey: defaultsKey)
    }

    func finish(_ noteID: String) {
        var ids = noteIDs
        ids.remove(noteID)
        if ids.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(Array(ids).sorted(), forKey: defaultsKey)
        }
    }

    func takeNoteIDsForLaunchCleanup() -> Set<String>? {
        guard !didBeginLaunchCleanup else { return nil }
        didBeginLaunchCleanup = true
        return noteIDs
    }
}

private enum IPadNoteWindowLoadState {
    case loading
    case loaded(Note)
    case failed(String)
}

struct IPadNoteWindow: View {
    let noteID: String

    @StateObject private var vaultStore = VaultStore.shared
    @StateObject private var registry = IPadNoteWindowRegistry.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadState: IPadNoteWindowLoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("正在载入笔记…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.surfaceRaised.ignoresSafeArea())

            case .loaded(let note):
                NoteEditorView(
                    mode: .edit(note),
                    presentation: .window,
                    treatsNoteAsNewFlow: IPadTemporaryNoteRegistry.shared.noteIDs.contains(note.id)
                ) { body, _ in
                    try await vaultStore.updateNote(note, body: body)
                    return vaultStore.readableNotes.first(where: { $0.id == note.id }) ?? note
                }

            case .failed(let message):
                ContentUnavailableView {
                    Label("无法打开笔记", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        loadState = .loading
                        Task { await loadNote() }
                    }
                    Button("关闭窗口", role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            registry.register(noteID)
        }
        .onDisappear {
            registry.unregister(noteID)
        }
        .task(id: noteID) {
            await loadNote()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vaultStore.resumeAutomaticCloudDownloads()
            } else if phase == .background, UIApplication.shared.applicationState == .background {
                vaultStore.pauseAutomaticCloudDownloads()
            }
        }
    }

    private func loadNote() async {
        if case .loading = vaultStore.state {
            await vaultStore.initialize()
        }

        await vaultStore.cleanupAbandonedIPadDrafts()

        do {
            let note = try await vaultStore.noteForEditing(noteID: noteID)
            guard !Task.isCancelled else { return }
            loadState = .loaded(note)
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }
}
#endif

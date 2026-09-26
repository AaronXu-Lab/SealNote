#if os(iOS)
import AppIntents
import Foundation

struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "创建笔记"
    static let description = IntentDescription("在 Seal Note 中创建一篇新笔记，无需打开 App。")

    @Parameter(
        title: "内容",
        description: "新笔记的 Markdown 正文",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$content) 创建笔记")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw CreateNoteIntentError.emptyContent
        }

        let vaultStore = VaultStore.shared
        if case .loading = vaultStore.state {
            await vaultStore.initialize()
        }
        guard case .ready = vaultStore.state else {
            throw CreateNoteIntentError.vaultUnavailable
        }

        _ = try await vaultStore.createNote(body: content, isEncrypted: false)
        return .result(dialog: "笔记已创建。")
    }
}

struct SealNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "用 \(.applicationName) 创建笔记",
                "在 \(.applicationName) 中新建笔记",
            ],
            shortTitle: "创建笔记",
            systemImageName: "square.and.pencil"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .navy
}

private enum CreateNoteIntentError: LocalizedError {
    case emptyContent
    case vaultUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "请输入笔记内容。"
        case .vaultUnavailable:
            return "Seal Note 的笔记库暂时不可用，请打开 App 后重试。"
        }
    }
}
#endif

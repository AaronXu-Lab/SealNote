import SwiftUI

#if os(iOS)
import AppIntents
#endif

@main
struct SealNoteApp: App {
    init() {
        #if os(iOS)
        SealNoteShortcuts.updateAppShortcutParameters()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        #if os(iOS)
        WindowGroup("笔记", id: IPadNoteWindowScene.id, for: String.self) { $noteID in
            if let noteID {
                IPadNoteWindow(noteID: noteID)
            } else {
                ContentUnavailableView("未选择笔记", systemImage: "note.text")
            }
        }
        #endif
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import Seal_Note

@MainActor
final class ShortcutConflictTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ShortcutStore!

    override func setUp() {
        super.setUp()
        suiteName = "ShortcutConflictTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = ShortcutStore(defaults: defaults, integratesWithSystem: false)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testConflictingRecordingDoesNotChangeAnySettingOrPersistence() {
        let oldNewNote = store.newNoteShortcut
        let oldMarkdown = store.markdownShortcuts
        let oldEditor = store.editorShortcuts
        let persisted = defaults.dictionaryRepresentation() as NSDictionary

        XCTAssertEqual(store.applyRecordedShortcut(oldNewNote, for: .markdown(.bold)), "新建笔记")
        XCTAssertEqual(store.newNoteShortcut, oldNewNote)
        XCTAssertEqual(store.markdownShortcuts, oldMarkdown)
        XCTAssertEqual(store.editorShortcuts, oldEditor)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, persisted)
    }

    func testConflictsIncludeBothEditorAndMarkdownActions() {
        XCTAssertEqual(store.conflict(for: store.shortcut(for: EditorShortcutAction.quickLineComment), excluding: .newNote), "快速注释当前行")
        XCTAssertEqual(store.conflict(for: store.shortcut(for: MarkdownShortcutAction.italic), excluding: .editor(.normalizeFormatting)), "斜体")
    }

    func testOwnShortcutDoesNotConflictAndUnsetActionsAreIgnored() {
        let shortcut = store.shortcut(for: MarkdownShortcutAction.bold)
        XCTAssertNil(store.conflict(for: shortcut, excluding: .markdown(.bold), menu: NSMenu()))
        XCTAssertNil(store.conflict(for: .unset, excluding: .newNote))
    }

    func testFixedGlobalAndNativeMenuShortcutsAreReserved() {
        let recent = MarkdownShortcut(keyCode: 18, modifiers: ShortcutStore.carbonModifiers(from: [.control, .command]), keyEquivalent: "1")
        XCTAssertEqual(store.conflict(for: recent, excluding: .newNote), "打开最近笔记 1")
        let menu = NSMenu()
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        let candidate = MarkdownShortcut(keyCode: 12, modifiers: ShortcutStore.carbonModifiers(from: .command), keyEquivalent: "q")
        XCTAssertEqual(store.conflict(for: candidate, excluding: .newNote, menu: menu), "退出")
    }

    func testNativeMenuConflictRejectsCommitAndKeepsPersistedShortcut() {
        let app = NSApplication.shared
        let originalMenu = app.mainMenu
        defer { app.mainMenu = originalMenu }
        let root = NSMenu()
        let parent = NSMenuItem()
        let child = NSMenu(title: "测试")
        let item = NSMenuItem(title: "保存", action: Selector(("markdownSave:")), keyEquivalent: "s")
        item.keyEquivalentModifierMask = [.command]
        child.addItem(item)
        parent.submenu = child
        root.addItem(parent)
        app.mainMenu = root
        let old = store.shortcut(for: MarkdownShortcutAction.bold)
        let candidate = MarkdownShortcut(keyCode: 1, modifiers: ShortcutStore.carbonModifiers(from: .command), keyEquivalent: "s")
        XCTAssertEqual(store.applyRecordedShortcut(candidate, for: .markdown(.bold)), "保存")
        XCTAssertEqual(store.shortcut(for: MarkdownShortcutAction.bold), old)
        XCTAssertNil(defaults.data(forKey: "mac.shortcut.markdownFormatting"))
    }

    func testValidRecordingPersistsAndIsRestoredByAnotherStore() {
        let candidate = MarkdownShortcut(keyCode: 35, modifiers: ShortcutStore.carbonModifiers(from: [.control, .option]), keyEquivalent: "p")
        XCTAssertNil(store.applyRecordedShortcut(candidate, for: .markdown(.bold)))
        let reloaded = ShortcutStore(defaults: defaults, integratesWithSystem: false)
        XCTAssertEqual(reloaded.shortcut(for: MarkdownShortcutAction.bold), candidate)
    }

    func testRecordingSuspendsMatchingUntilEverySessionEnds() throws {
        let first = store.beginShortcutRecording()
        let second = store.beginShortcutRecording()
        defer { store.endShortcutRecording(first); store.endShortcutRecording(second) }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
        let editorEvent = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "/", charactersIgnoringModifiers: "/", isARepeat: false, keyCode: 44))
        XCTAssertTrue(store.isRecordingShortcuts)
        XCTAssertNil(store.markdownAction(matching: event))
        XCTAssertNil(store.editorAction(matching: editorEvent))
        store.registerHotKeys() // Re-registration requests must not end suspension.
        store.endShortcutRecording(first)
        store.endShortcutRecording(first) // Repeated cleanup must not release another session.
        XCTAssertTrue(store.isRecordingShortcuts)
        XCTAssertNil(store.markdownAction(matching: event))
        store.endShortcutRecording(second)
        XCTAssertFalse(store.isRecordingShortcuts)
        XCTAssertEqual(store.markdownAction(matching: event), .bold)
        XCTAssertEqual(store.editorAction(matching: editorEvent), .quickLineComment)
    }

    func testRecorderWindowCleanupRestoresShortcutHandlingOnEveryExit() {
        for exit in ["close", "delegate", "deactivate"] {
            let coordinator = ShortcutRecordingWindowHost.Coordinator()
            coordinator.shortcutStore = store
            var action: MacShortcutRecordingAction? = .newNote
            coordinator.recordingAction = Binding(get: { action }, set: { action = $0 })
            coordinator.beginRecording()
            XCTAssertTrue(store.isRecordingShortcuts)
            let notification = Notification(name: NSWindow.willCloseNotification)
            switch exit {
            case "delegate": coordinator.windowWillClose(notification)
            case "deactivate": coordinator.windowDidResignKey(notification)
            default: coordinator.close()
            }
            XCTAssertFalse(store.isRecordingShortcuts)
            XCTAssertNil(action)
            coordinator.close()
            XCTAssertFalse(store.isRecordingShortcuts)
        }
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import Seal_Note

@MainActor
final class ShortcutRecordingWindowTests: XCTestCase {
    func testEscapeCancelsWithoutRecording() throws {
        let recorder = ShortcutRecorderView.RecorderView()
        recorder.recordingAction = .newNote
        var cancelled = false
        recorder.onCancel = { cancelled = true }
        recorder.onRecord = { _, _ in XCTFail("Escape must not save a shortcut") }

        recorder.keyDown(with: try keyEvent(code: 53, characters: "\u{1b}"))

        XCTAssertTrue(cancelled)
    }

    func testCommandShortcutIsCapturedBeforeMenuCommands() throws {
        let recorder = ShortcutRecorderView.RecorderView()
        recorder.recordingAction = .markdown(.bold)
        var recorded: MarkdownShortcut?
        recorder.onRecord = { action, shortcut in
            XCTAssertEqual(action, .markdown(.bold))
            recorded = shortcut
        }

        XCTAssertTrue(recorder.performKeyEquivalent(with: try keyEvent(code: 11, characters: "b", modifiers: .command)))
        XCTAssertNil(recorded, "Pressing must only preview the shortcut")
        recorder.keyUp(with: try keyEvent(code: 11, characters: "b", modifiers: .command, type: .keyUp))
        XCTAssertEqual(recorded?.keyCode, 11)
        XCTAssertEqual(recorded?.modifiers, ShortcutStore.carbonModifiers(from: .command))
    }

    func testModifierChangesAndKeyDownUpdatePreviewBeforeRelease() throws {
        let recorder = ShortcutRecorderView.RecorderView()
        recorder.recordingAction = .newNote
        var preview = ""
        var saved: MarkdownShortcut?
        recorder.onChange = { preview = $0 }
        recorder.onRecord = { _, shortcut in saved = shortcut }

        recorder.flagsChanged(with: try keyEvent(code: 55, characters: "", modifiers: .command, type: .flagsChanged))
        XCTAssertEqual(preview, "⌘")
        recorder.flagsChanged(with: try keyEvent(code: 56, characters: "", modifiers: [.command, .shift], type: .flagsChanged))
        XCTAssertEqual(preview, "⇧⌘")
        recorder.keyDown(with: try keyEvent(code: 11, characters: "b", modifiers: [.command, .shift]))
        XCTAssertEqual(preview, "⇧⌘B")
        XCTAssertNil(saved)

        // Releasing a modifier updates the live display but preserves the captured chord.
        recorder.flagsChanged(with: try keyEvent(code: 56, characters: "", modifiers: .command, type: .flagsChanged))
        XCTAssertEqual(preview, "⌘B")
        XCTAssertNil(saved)
        recorder.keyUp(with: try keyEvent(code: 11, characters: "b", modifiers: .command, type: .keyUp))
        XCTAssertEqual(saved?.modifiers, ShortcutStore.carbonModifiers(from: [.command, .shift]))
    }

    func testModifierOnlyReleaseDoesNotRecord() throws {
        let recorder = ShortcutRecorderView.RecorderView()
        recorder.recordingAction = .newNote
        var preview = ""
        recorder.onChange = { preview = $0 }
        recorder.onRecord = { _, _ in XCTFail("Modifiers alone must not record") }
        recorder.flagsChanged(with: try keyEvent(code: 55, characters: "", modifiers: .command, type: .flagsChanged))
        recorder.flagsChanged(with: try keyEvent(code: 55, characters: "", type: .flagsChanged))
        XCTAssertEqual(preview, "")
    }

    func testEscapeClearsPendingChordAndKeyUpDoesNotSave() throws {
        let recorder = ShortcutRecorderView.RecorderView()
        recorder.recordingAction = .newNote
        recorder.onRecord = { _, _ in XCTFail("Cancelled chord must not save on release") }
        recorder.keyDown(with: try keyEvent(code: 11, characters: "b", modifiers: .command))
        recorder.keyDown(with: try keyEvent(code: 53, characters: "\u{1b}"))
        recorder.keyUp(with: try keyEvent(code: 11, characters: "b", type: .keyUp))
        XCTAssertNil(recorder.recordingAction)
    }

    func testReleaseCommitsOnceAndIgnoresUnrelatedKeyUp() throws {
        let recorder = ShortcutRecorderView.RecorderView()
        recorder.recordingAction = .newNote
        var saves = 0
        recorder.onRecord = { _, _ in saves += 1 }
        recorder.keyDown(with: try keyEvent(code: 11, characters: "b", modifiers: .command))
        recorder.keyUp(with: try keyEvent(code: 0, characters: "a", type: .keyUp))
        XCTAssertEqual(saves, 0)
        recorder.keyUp(with: try keyEvent(code: 11, characters: "b", type: .keyUp))
        recorder.keyUp(with: try keyEvent(code: 11, characters: "b", type: .keyUp))
        XCTAssertEqual(saves, 1)
    }

    func testClosingWindowClearsRecordingAndAllowsAnotherSession() {
        let coordinator = ShortcutRecordingWindowHost.Coordinator()
        var action: MacShortcutRecordingAction? = .newNote
        coordinator.recordingAction = Binding(get: { action }, set: { action = $0 })
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = coordinator
        coordinator.window = window

        coordinator.close()

        XCTAssertNil(action)
        XCTAssertNil(coordinator.window)
        action = .editor(.normalizeFormatting)
        XCTAssertEqual(coordinator.recordingAction?.wrappedValue, .editor(.normalizeFormatting))
    }

    func testWindowCaptureConsumesCommandKeysBeforeMenusAndStopsAfterCancel() throws {
        let window = RecordingTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let recorder = ShortcutRecorderView.RecorderView()
        window.contentView = recorder
        recorder.recordingAction = .newNote
        defer { recorder.recordingAction = nil; window.close() }
        recorder.onRecord = { _, _ in XCTFail("A pressed or cancelled chord must not commit") }
        func event(_ code: UInt16, _ characters: String) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        XCTAssertTrue(recorder.consumeRecordingEvent(try event(12, "q")), "Consume Cmd-Q rather than forwarding it to application menus")
        XCTAssertTrue(recorder.consumeRecordingEvent(try event(53, "\u{1b}")))
        XCTAssertFalse(recorder.consumeRecordingEvent(try event(12, "q")), "Normal event dispatch resumes when recording ends")
    }

    private final class RecordingTestWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private func keyEvent(code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: code))
    }
}

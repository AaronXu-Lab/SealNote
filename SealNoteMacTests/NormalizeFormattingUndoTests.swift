import AppKit
import XCTest
@testable import Seal_Note

@MainActor
final class NormalizeFormattingUndoTests: XCTestCase {
    func testNormalizeFormattingIsOneUndoableEdit() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = AutoFocusTextView(frame: window.contentView?.bounds ?? .zero)
        textView.isEditable = true
        textView.allowsUndo = true
        window.contentView = textView
        window.makeFirstResponder(textView)

        let original = "第一段\n第二段"
        textView.string = original
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.undoManager?.removeAllActions()

        textView.markdownNormalizeFormatting(nil)

        XCTAssertEqual(textView.string, "第一段\n\n第二段\n")
        XCTAssertTrue(textView.undoManager?.canUndo == true)

        textView.undoManager?.undo()

        XCTAssertEqual(textView.string, original)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }
}

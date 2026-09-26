import AppKit
import SwiftUI
import XCTest
@testable import Seal_Note

@MainActor
final class EditorShiftSelectionTests: XCTestCase {
    func testShiftClickFromEndAfterTyping() throws {
        try checkSelection { view in
            view.moveToEndOfDocument(nil)
            view.insertText("，请调整", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    func testShiftClickAfterTypingEntireLine() throws {
        try checkSelection { view in
            view.selectAll(nil)
            view.insertText("design-canvas\n\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            for character in "* 生成的流程图依然会存在很多杂乱的线不方便查看，请调整" {
                view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    func testShiftClickAfterCommittingMarkedText() throws {
        try checkSelection { view in
            view.selectAll(nil)
            view.insertText("design-canvas\n\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            for word in ["* ", "生成的", "流程图", "依然会存在", "很多杂乱的线", "不方便查看", "，请调整"] {
                view.setMarkedText(word, selectedRange: NSRange(location: (word as NSString).length, length: 0),
                                   replacementRange: NSRange(location: NSNotFound, length: 0))
                view.insertText(word, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    func testShiftClickFromEndAfterKeyboardMovement() throws {
        try checkSelection { view in
            view.moveToBeginningOfDocument(nil)
            view.moveToEndOfDocument(nil)
        }
    }

    func testShiftClickFromEndAfterMouseClick() throws {
        try checkSelection { view in
            let length = (view.string as NSString).length
            let point = try self.point(at: length - 1, in: view, afterCharacter: true)
            try self.click(point, in: view, shift: false)
        }
    }

    func testShiftClickAfterClickingBelowLastLine() throws {
        try checkSelection { view in
            let point = view.convert(NSPoint(x: view.bounds.maxX - 30, y: view.bounds.maxY - 30), to: nil)
            try self.click(point, in: view, shift: false)
        }
    }

    func testShiftClickAfterClickingBelowWrappedLastLine() throws {
        try checkSelection { view in
            view.setFrameSize(NSSize(width: 220, height: 500))
            view.textContainer?.containerSize = NSSize(width: 220, height: CGFloat.greatestFiniteMagnitude)
            let point = view.convert(NSPoint(x: 190, y: 470), to: nil)
            try self.click(point, in: view, shift: false)
        }
    }

    func testShiftClickAfterClickingBelowTrailingNewline() throws {
        try checkSelection { view in
            view.moveToEndOfDocument(nil)
            view.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            let point = view.convert(NSPoint(x: view.bounds.maxX - 30, y: view.bounds.maxY - 30), to: nil)
            try self.click(point, in: view, shift: false)
        }
    }

    private func checkSelection(positionCaret: (AutoFocusTextView) throws -> Void) throws {
        let text = "design-canvas\n* 路由使用子路由 /design-canvas\n\n* 生成的流程图依然会存在很多杂乱的线不方便查看"
        let parent = MacTextView(
            text: .constant(text), placeholder: "", fontSize: 18, lineHeightMultiple: 1.5,
            autoFocus: false, onChange: { _ in }, onSaveShortcut: {}, onApplyShortcut: {},
            onFitToContent: {}, onCopyShortcut: {}, onFindShortcut: {},
            onIncreaseFontSize: {}, onDecreaseFontSize: {}, onFindVisibilityChange: { _ in }
        )
        let coordinator = parent.makeCoordinator()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = AutoFocusTextView(frame: window.contentView!.bounds)
        view.isAutoFocusEnabled = false
        view.isRichText = false
        view.coordinator = coordinator
        coordinator.configureTextView(view, text: text, fontSize: 18)
        view.delegate = coordinator
        window.contentView = view
        window.makeFirstResponder(view)
        defer { view.delegate = nil; window.orderOut(nil) }

        try positionCaret(view)
        let end = (view.string as NSString).length
        XCTAssertEqual(view.selectedRange(), NSRange(location: end, length: 0))
        let target = (view.string as NSString).range(of: "流程图").location
        try click(point(at: target, in: view), in: view, shift: true)
        XCTAssertEqual(view.selectedRange(), NSRange(location: target, length: end - target))

        MarkdownHighlighter.applyMarkdownHighlighting(to: view, lineHeightMultiple: 1.5)
        try click(point(at: target + 3, in: view), in: view, shift: true)
        XCTAssertEqual(view.selectedRange(), NSRange(location: target + 3, length: end - target - 3))
    }

    private func point(at index: Int, in view: NSTextView, afterCharacter: Bool = false) throws -> NSPoint {
        let layout = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        return view.convert(NSPoint(x: (afterCharacter ? rect.maxX + 2 : rect.minX + 1) + view.textContainerOrigin.x,
                                    y: rect.midY + view.textContainerOrigin.y), to: nil)
    }

    private func click(_ point: NSPoint, in view: NSTextView, shift: Bool) throws {
        let window = try XCTUnwrap(view.window)
        let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: flags, timestamp: down.timestamp + 0.01,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        NSApp.postEvent(up, atStart: true)
        view.mouseDown(with: down)
    }
}

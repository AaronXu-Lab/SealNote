import AppKit
import XCTest
@testable import Seal_Note

@MainActor
final class MacImagePasteboardReaderTests: XCTestCase {
    func testImageOnlyClipboardEnablesPasteCommand() throws {
        let pasteboard = NSPasteboard(name: .init("MacImagePasteboardReaderTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(try makePNG(color: .systemGreen), forType: .png)
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = AutoFocusTextView(frame: window.contentView?.bounds ?? .zero)
        textView.isEditable = true
        textView.pasteboardProvider = { pasteboard }
        window.contentView = textView
        window.makeFirstResponder(textView)

        let menuItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        XCTAssertTrue(textView.validateUserInterfaceItem(menuItem))
    }

    func testReadsEveryDirectImageItemInOrderWhenClipboardAlsoContainsText() throws {
        let pasteboard = NSPasteboard(name: .init("MacImagePasteboardReaderTests-\(UUID().uuidString)"))
        pasteboard.clearContents()

        let first = NSPasteboardItem()
        first.setData(try makePNG(color: .systemRed), forType: .png)
        first.setString("first image", forType: .string)

        let second = NSPasteboardItem()
        second.setData(try makePNG(color: .systemBlue), forType: .png)
        second.setString("second image", forType: .string)

        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        XCTAssertTrue(MacImagePasteboardReader.containsImages(in: pasteboard))

        let urls = MacImagePasteboardReader.imageURLs(from: pasteboard)
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls.allSatisfy { $0.lastPathComponent.hasPrefix("SealNote-Clipboard-") })
        XCTAssertTrue(urls.allSatisfy { NSImage(contentsOf: $0)?.isValid == true })
    }

    func testReadsMultipleImageFileURLsWithoutCreatingCopies() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacImagePasteboardReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = directory.appendingPathComponent("first.png")
        let secondURL = directory.appendingPathComponent("second.png")
        try makePNG(color: .systemRed).write(to: firstURL)
        try makePNG(color: .systemBlue).write(to: secondURL)

        let pasteboard = NSPasteboard(name: .init("MacImagePasteboardReaderTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([firstURL as NSURL, secondURL as NSURL]))

        XCTAssertEqual(MacImagePasteboardReader.imageURLs(from: pasteboard), [firstURL, secondURL])
    }

    private func makePNG(color: NSColor) throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

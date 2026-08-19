import Foundation
import XCTest
@testable import Seal_Note

final class MarkdownLineCommentTests: XCTestCase {
    func testWrapsCurrentLineAndKeepsCaretPosition() {
        let result = MarkdownFormatter.toggleLineComment(
            in: "first\nsecond\nthird",
            selection: NSRange(location: 8, length: 0)
        )

        XCTAssertEqual(result.text, "first\n<!-- second -->\nthird")
        XCTAssertEqual(result.selection, NSRange(location: 13, length: 0))
    }

    func testTogglesExistingCommentOff() {
        let result = MarkdownFormatter.toggleLineComment(
            in: "first\n<!-- second -->\nthird",
            selection: NSRange(location: 13, length: 0)
        )

        XCTAssertEqual(result.text, "first\nsecond\nthird")
        XCTAssertEqual(result.selection, NSRange(location: 8, length: 0))
    }

    func testPreservesIndentation() {
        let result = MarkdownFormatter.toggleLineComment(
            in: "  nested",
            selection: NSRange(location: 4, length: 0)
        )

        XCTAssertEqual(result.text, "  <!-- nested -->")
        XCTAssertEqual(result.selection, NSRange(location: 9, length: 0))
    }

    func testEmptyLinePlacesCaretInsideComment() {
        let result = MarkdownFormatter.toggleLineComment(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(result.text, "<!--  -->")
        XCTAssertEqual(result.selection, NSRange(location: 5, length: 0))
    }
}

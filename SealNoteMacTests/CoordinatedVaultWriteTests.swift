import XCTest
@testable import Seal_Note

final class CoordinatedVaultWriteTests: XCTestCase {
    func testReplacementAndUnchangedWriteLeaveOnlyDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        try coordinatedVaultWrite(data: Data("old".utf8), to: url)
        let replacement = Data("new".utf8)
        try coordinatedVaultWrite(data: replacement, to: url)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        try coordinatedVaultWrite(data: replacement, to: url)
        XCTAssertEqual(try Data(contentsOf: url), replacement)
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["notes.json"])
    }

    func testFailedWriteDoesNotCreateTemporaryDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("missing/notes.json")
        XCTAssertThrowsError(try coordinatedVaultWrite(data: Data("new".utf8), to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("tmp").path))
    }
}

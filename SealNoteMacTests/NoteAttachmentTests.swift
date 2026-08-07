import Foundation
import XCTest
@testable import Seal_Note

final class NoteAttachmentTests: XCTestCase {
    private var rootURL: URL!
    private var storage: AttachmentTestStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sealnote-attachment-tests-\(UUID().uuidString)", isDirectory: true)
        storage = try AttachmentTestStorage(rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        storage = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    func testManifestMissingIsBackwardCompatibleAndRoundTrips() throws {
        XCTAssertEqual(
            try storage.loadAttachmentManifest(for: "legacy-note"),
            .empty(for: "legacy-note")
        )

        let attachment = NoteAttachment(
            fileName: "attachment-id.png",
            originalFileName: "截图.png",
            contentType: "public.png",
            createdAt: Date(timeIntervalSince1970: 1_000),
            order: 0,
            byteCount: 12,
            pixelWidth: 100,
            pixelHeight: 80,
            sha256: "abc123"
        )
        let manifest = NoteAttachmentManifest(
            noteId: "legacy-note",
            attachments: [attachment],
            tombstones: [NoteAttachmentTombstone(id: "old-id")]
        )

        try storage.saveAttachmentManifest(manifest, for: "legacy-note")
        let decoded = try storage.loadAttachmentManifest(for: "legacy-note")
        XCTAssertEqual(decoded.noteId, "legacy-note")
        XCTAssertEqual(decoded.attachments, [attachment])
        XCTAssertEqual(decoded.tombstones.map(\.id), ["old-id"])
    }

    func testAttachmentDirectoryMovesAndDeletesWithNoteLocation() throws {
        let noteId = "note-with-attachment"
        let attachment = NoteAttachment(
            fileName: "id.jpg",
            originalFileName: "photo.jpg",
            contentType: "public.jpeg",
            order: 0,
            byteCount: 4,
            sha256: "hash"
        )
        try storage.saveAttachmentManifest(
            NoteAttachmentManifest(noteId: noteId, attachments: [attachment]),
            for: noteId
        )
        let fileURL = try XCTUnwrap(storage.attachmentFileURL(for: noteId, fileName: attachment.fileName))
        try Data([1, 2, 3, 4]).write(to: fileURL)

        try storage.moveAttachmentDirectory(for: noteId, from: .notes, to: .trash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let trashFileURL = try XCTUnwrap(
            storage.attachmentFileURL(for: noteId, fileName: attachment.fileName, location: .trash)
        )
        XCTAssertEqual(try Data(contentsOf: trashFileURL), Data([1, 2, 3, 4]))

        try storage.moveAttachmentDirectory(for: noteId, from: .trash, to: .notes)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([1, 2, 3, 4]))
        try storage.permanentlyDeleteAttachmentDirectory(for: noteId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testTombstonesPruneAfterThirtyDays() {
        let old = NoteAttachmentTombstone(
            id: "old",
            deletedAt: Date(timeIntervalSince1970: 100)
        )
        let recent = NoteAttachmentTombstone(id: "recent", deletedAt: Date())
        let manifest = NoteAttachmentManifest(
            noteId: "note",
            tombstones: [old, recent]
        )

        let pruned = manifest.pruningTombstones(
            olderThan: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(pruned.tombstones.map(\.id), ["recent"])
    }

    func testOlderManifestWithoutEncryptionFieldsDefaultsToPlain() throws {
        let attachment = NoteAttachment(
            fileName: "id.png",
            originalFileName: "image.png",
            contentType: "public.png",
            createdAt: Date(timeIntervalSince1970: 1_000),
            order: 0,
            byteCount: 1,
            sha256: "hash"
        )
        let manifest = NoteAttachmentManifest(noteId: "note", attachments: [attachment])
        let encoded = try JSONEncoder.default.encode(manifest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var entries = try XCTUnwrap(object["attachments"] as? [[String: Any]])
        entries[0].removeValue(forKey: "encryptionMode")
        entries[0].removeValue(forKey: "encryptionVersion")
        object["attachments"] = entries
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.default.decode(NoteAttachmentManifest.self, from: legacyData)
        XCTAssertEqual(decoded.attachments.first?.encryptionMode, "plain")
        XCTAssertNil(decoded.attachments.first?.encryptionVersion)
    }

    @MainActor
    func testVaultStoreImportsImageAsIndependentAttachment() async throws {
        let store = VaultStore(storage: storage)
        store.configureForTesting(vaultId: "attachment-test-vault")
        let note = try await store.createNote(body: "正文不变", isEncrypted: false)
        let sourceURL = rootURL.appendingPathComponent("source.png")
        let pngData = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        try pngData.write(to: sourceURL)

        let result = try await store.importImageAttachments(
            from: [sourceURL],
            for: note,
            currentBody: note.body
        )

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.attachments.count, 1)
        XCTAssertEqual(result.note.body, note.body)
        let attachment = try XCTUnwrap(result.attachments.first)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(storage.attachmentFileURL(
            for: note.id,
            fileName: attachment.fileName
        ))), pngData)
        let persistedAttachment = try XCTUnwrap(
            storage.loadAttachmentManifest(for: note.id).attachments.first
        )
        XCTAssertEqual(persistedAttachment.id, attachment.id)
        XCTAssertEqual(persistedAttachment.fileName, attachment.fileName)
        XCTAssertEqual(persistedAttachment.sha256, attachment.sha256)
        XCTAssertEqual(persistedAttachment.byteCount, attachment.byteCount)
        XCTAssertNotEqual(result.note.updatedAt, note.updatedAt)
    }
}

private final class AttachmentTestStorage: VaultStorage, @unchecked Sendable {
    let rootURL: URL
    var containerURL: URL? { rootURL }
    var isAvailable: Bool { true }
    private var index = NoteIndex()

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeDirectories()
    }

    func initializeVault() async throws {
        try initializeDirectories()
    }

    func loadIndex() throws -> NoteIndex? { index }
    func saveIndex(_ index: NoteIndex) throws { self.index = index }

    func listMarkdownFiles(in location: NoteFileLocation) throws -> [URL] {
        let directory = location == .notes
            ? rootURL
            : rootURL.appendingPathComponent(location.rawValue)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "md" }
    }

    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        try MarkdownNoteFile.parse(from: Data(contentsOf: url))
    }

    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try file.render().write(to: url, options: .atomic)
    }

    func moveFile(from srcURL: URL, to dstURL: URL) throws {
        try FileManager.default.createDirectory(
            at: dstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
    }

    func permanentlyDeleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func createConflictCopy(for url: URL) throws -> URL {
        let destination = rootURL.appendingPathComponent("conflict-\(UUID().uuidString).md")
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    func emptyTrash() throws {
        let trashURL = rootURL.appendingPathComponent("trash")
        if FileManager.default.fileExists(atPath: trashURL.path) {
            try FileManager.default.removeItem(at: trashURL)
            try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
        }
    }

    private func initializeDirectories() throws {
        for path in [
            rootURL,
            rootURL.appendingPathComponent("trash"),
            rootURL.appendingPathComponent("attachments"),
            rootURL.appendingPathComponent("trash/attachments")
        ] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
    }
}

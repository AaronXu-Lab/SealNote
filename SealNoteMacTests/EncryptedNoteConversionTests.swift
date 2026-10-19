import CryptoKit
import Foundation
import XCTest
@testable import Seal_Note

@MainActor
final class EncryptedNoteConversionTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var storage: ConversionTestStorage!
    private var settings: SettingsStore!
    private var store: VaultStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "EncryptedNoteConversionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults)
        storage = try ConversionTestStorage(root: root)
        store = VaultStore(storage: storage, settings: settings)
        store.configureForTesting(vaultId: "conversion-tests")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
        store = nil
        storage = nil
        settings = nil
        defaults = nil
    }

    func testMissingFileConvertsAvailableNotesKeepsKeyAndCanRetry() async throws {
        try await store.createKeyFile(at: root.appendingPathComponent("test.snkey"))
        let available = try await store.createNote(body: "Available secret", isEncrypted: true)
        let missing = try await store.createNote(body: "Missing secret", isEncrypted: true)
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: missing.id))
        let missingURL = root.appendingPathComponent(entry.fileName)
        let savedData = try Data(contentsOf: missingURL)
        try FileManager.default.removeItem(at: missingURL)

        do {
            _ = try await store.decryptAllEncryptedNotesAndRemoveKey()
            XCTFail("Must retain the key for an unavailable note")
        } catch {
            XCTAssertEqual(error as? EncryptedNoteConversionError, .filesUnavailable(remaining: 1, converted: 1))
        }
        XCTAssertNotNil(settings.vaultKeyFileReference)
        XCTAssertEqual(store.encryptedEntryCount, 1)
        XCTAssertEqual(try storage.loadIndex()?.entry(for: available.id)?.mode, .plain)
        XCTAssertEqual(try storage.loadIndex()?.entry(for: missing.id), entry)
        XCTAssertTrue(store.plainNotes.contains { $0.id == available.id && $0.body == "Available secret" })

        try savedData.write(to: missingURL)
        let converted = try await store.decryptAllEncryptedNotesAndRemoveKey()
        XCTAssertEqual(converted, 1)
        XCTAssertNil(settings.vaultKeyFileReference)
        XCTAssertEqual(store.encryptedEntryCount, 0)
        XCTAssertEqual(store.plainNotes.count, 2)
    }

    func testRenamedEncryptedFileIsLocatedByNoteID() async throws {
        try await store.createKeyFile(at: root.appendingPathComponent("test.snkey"))
        let note = try await store.createNote(body: "Renamed secret", isEncrypted: true)
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: note.id))
        let renamedURL = root.appendingPathComponent("renamed-on-another-device.md")
        try FileManager.default.moveItem(at: root.appendingPathComponent(entry.fileName), to: renamedURL)

        let count = try await store.decryptAllEncryptedNotesAndRemoveKey()
        XCTAssertEqual(count, 1)
        XCTAssertNil(settings.vaultKeyFileReference)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(store.plainNotes.first?.body, "Renamed secret")
    }

    func testTrashNotesAreConvertedAndRemainInTrash() async throws {
        try await store.createKeyFile(at: root.appendingPathComponent("test.snkey"))
        let note = try await store.createNote(body: "Trash secret", isEncrypted: true)
        try await store.deleteNote(note)
        let original = try XCTUnwrap(storage.loadIndex()?.entry(for: note.id))

        let count = try await store.decryptAllEncryptedNotesAndRemoveKey()
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: note.id))
        XCTAssertEqual(count, 1)
        XCTAssertEqual(entry.location, .trash)
        XCTAssertEqual(entry.deletedAt, original.deletedAt)
        XCTAssertEqual(entry.purgeAfter, original.purgeAfter)
        XCTAssertEqual(entry.mode, .plain)
        let file = try storage.loadMarkdownFile(at: root.appendingPathComponent("trash").appendingPathComponent(entry.fileName))
        XCTAssertEqual(file.body, "Trash secret")
        XCTAssertNil(settings.vaultKeyFileReference)
    }

    func testDownloadPendingKeepsKeyAndEncryptedIndex() async throws {
        try await store.createKeyFile(at: root.appendingPathComponent("test.snkey"))
        let note = try await store.createNote(body: "Cloud secret", isEncrypted: true)
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: note.id))
        storage.pendingURL = root.appendingPathComponent(entry.fileName)
        do {
            _ = try await store.decryptAllEncryptedNotesAndRemoveKey()
            XCTFail("A download must finish before removing the key")
        } catch {
            XCTAssertEqual(error as? EncryptedNoteConversionError, .filesUnavailable(remaining: 1, converted: 0))
        }
        XCTAssertNotNil(settings.vaultKeyFileReference)
        XCTAssertEqual(try storage.loadIndex()?.entry(for: note.id), entry)
    }

    func testWrongKeyFailsBeforeConvertingAnyFiles() async throws {
        try await store.createKeyFile(at: root.appendingPathComponent("test.snkey"))
        let first = try await store.createNote(body: "First secret", isEncrypted: true)
        let second = try await store.createNote(body: "Second secret", isEncrypted: true)
        let entry = try XCTUnwrap(storage.loadIndex()?.entry(for: second.id))
        let url = root.appendingPathComponent(entry.fileName)
        let file = try storage.loadMarkdownFile(at: url)
        let wrongCiphertext = try CryptoService.shared.encryptMarkdownBody("Other key", using: SymmetricKey(size: .bits256))
        try storage.saveMarkdownFile(MarkdownNoteFile(noteId: file.noteId, createdAt: file.createdAt,
                                                    updatedAt: file.updatedAt, title: file.title, body: wrongCiphertext), at: url)
        do {
            _ = try await store.decryptAllEncryptedNotesAndRemoveKey()
            XCTFail("Wrong key must stop conversion")
        } catch {
            XCTAssertEqual(error as? VaultKeyFileError, .keyMismatch)
        }
        XCTAssertEqual(try storage.loadIndex()?.entry(for: first.id)?.mode, .encrypted)
        XCTAssertEqual(store.encryptedEntryCount, 2)
        XCTAssertNotNil(settings.vaultKeyFileReference)
    }
}

nonisolated private final class ConversionTestStorage: VaultStorage, @unchecked Sendable {
    let containerURL: URL?
    var pendingURL: URL?
    var isAvailable: Bool { true }
    init(root: URL) throws {
        containerURL = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("trash"), withIntermediateDirectories: true)
    }
    func initializeVault() async throws {}
    func loadIndex() throws -> NoteIndex? {
        let url = containerURL!.appendingPathComponent("notes.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: url))
    }
    func saveIndex(_ index: NoteIndex) throws {
        try JSONEncoder().encode(index).write(to: containerURL!.appendingPathComponent("notes.json"), options: .atomic)
    }
    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        if url == pendingURL { throw StorageError.iCloudDownloadPending }
        guard FileManager.default.fileExists(atPath: url.path) else { throw StorageError.fileNotFound }
        return try MarkdownNoteFile.parse(from: Data(contentsOf: url))
    }
    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        try file.render().write(to: url, options: .atomic)
    }
}

import Foundation

/// Coordinate with iCloud before replacing a document. Foundation owns the
/// atomic staging file; a shared `<document>.tmp` races with other writers and
/// exposes an extra document to the sync engine.
nonisolated func coordinatedVaultWrite(data: Data, to url: URL) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
        do {
            // Rebuilding an unchanged index should not trigger another upload.
            if let existing = try? Data(contentsOf: target), existing == data { return }
            try data.write(to: target, options: .atomic)
        } catch {
            writeError = error
        }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
}

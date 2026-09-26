import Foundation

/// Coordinate with iCloud before replacing a document. Foundation owns the
/// atomic staging file; a shared `<document>.tmp` races with other writers and
/// exposes an extra document to the sync engine.
nonisolated func coordinatedVaultWrite(data: Data, to url: URL) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    #if os(macOS)
    // File coordination can wait indefinitely when the iCloud service is stuck.
    // Cancel the claim rather than bypassing coordination and risking a conflict.
    let timeout = DispatchWorkItem { coordinator.cancel() }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: timeout)
    defer { timeout.cancel() }
    #endif
    var coordinationError: NSError?
    var writeError: Error?
    var didAccess = false
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
        didAccess = true
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
    guard didAccess else {
        throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: [
            NSLocalizedDescriptionKey: "等待 iCloud 文件协调超时，请稍后重试。"
        ])
    }
}

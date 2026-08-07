import Foundation

extension Notification.Name {
    nonisolated static let vaultAttachmentsDidChange = Notification.Name("SealNoteVaultAttachmentsDidChange")
}

nonisolated struct NoteAttachment: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let fileName: String
    let originalFileName: String
    let contentType: String
    let createdAt: Date
    let order: Int
    let byteCount: Int64
    let pixelWidth: Int?
    let pixelHeight: Int?
    let sha256: String
    let encryptionMode: String
    let encryptionVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case id, fileName, originalFileName, contentType, createdAt, order
        case byteCount, pixelWidth, pixelHeight, sha256, encryptionMode, encryptionVersion
    }

    init(
        id: String = UUID().uuidString,
        fileName: String,
        originalFileName: String,
        contentType: String,
        createdAt: Date = Date(),
        order: Int,
        byteCount: Int64,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sha256: String,
        encryptionMode: String = "plain",
        encryptionVersion: Int? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.contentType = contentType
        self.createdAt = createdAt
        self.order = order
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sha256 = sha256
        self.encryptionMode = encryptionMode
        self.encryptionVersion = encryptionVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            fileName: try container.decode(String.self, forKey: .fileName),
            originalFileName: try container.decode(String.self, forKey: .originalFileName),
            contentType: try container.decode(String.self, forKey: .contentType),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            order: try container.decode(Int.self, forKey: .order),
            byteCount: try container.decode(Int64.self, forKey: .byteCount),
            pixelWidth: try container.decodeIfPresent(Int.self, forKey: .pixelWidth),
            pixelHeight: try container.decodeIfPresent(Int.self, forKey: .pixelHeight),
            sha256: try container.decode(String.self, forKey: .sha256),
            encryptionMode: try container.decodeIfPresent(String.self, forKey: .encryptionMode) ?? "plain",
            encryptionVersion: try container.decodeIfPresent(Int.self, forKey: .encryptionVersion)
        )
    }
}

nonisolated struct NoteAttachmentTombstone: Codable, Equatable, Sendable {
    let id: String
    let deletedAt: Date

    init(id: String, deletedAt: Date = Date()) {
        self.id = id
        self.deletedAt = deletedAt
    }
}

nonisolated struct NoteAttachmentManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let noteId: String
    var attachments: [NoteAttachment]
    var tombstones: [NoteAttachmentTombstone]

    private enum CodingKeys: String, CodingKey {
        case version, noteId, attachments, tombstones
    }

    init(
        noteId: String,
        attachments: [NoteAttachment] = [],
        tombstones: [NoteAttachmentTombstone] = [],
        version: Int = Self.currentVersion
    ) {
        self.version = version
        self.noteId = noteId
        self.attachments = attachments.sorted { $0.order < $1.order }
        self.tombstones = tombstones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            noteId: try container.decode(String.self, forKey: .noteId),
            attachments: try container.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? [],
            tombstones: try container.decodeIfPresent([NoteAttachmentTombstone].self, forKey: .tombstones) ?? [],
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        )
    }

    static func empty(for noteId: String) -> NoteAttachmentManifest {
        NoteAttachmentManifest(noteId: noteId)
    }

    func pruningTombstones(olderThan date: Date = Date().addingTimeInterval(-30 * 86400)) -> NoteAttachmentManifest {
        var copy = self
        copy.tombstones.removeAll { $0.deletedAt < date }
        return copy
    }
}

nonisolated struct AttachmentMutationResult: Sendable {
    let note: Note
    let attachments: [NoteAttachment]
    let importedCount: Int
    let skippedCount: Int
    let skippedReasons: [String]
}

nonisolated enum AttachmentError: Error, LocalizedError, Equatable {
    case invalidImage
    case tooLarge(maxBytes: Int64)
    case limitReached(maxCount: Int)
    case manifestMissing
    case attachmentMissing
    case unsupportedContentType

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "图片无法读取"
        case .tooLarge(let maxBytes):
            return "图片超过 \(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file))"
        case .limitReached(let maxCount):
            return "每篇笔记最多添加 \(maxCount) 张图片"
        case .manifestMissing:
            return "附件清单不存在"
        case .attachmentMissing:
            return "附件文件不存在"
        case .unsupportedContentType:
            return "不支持的图片格式"
        }
    }
}

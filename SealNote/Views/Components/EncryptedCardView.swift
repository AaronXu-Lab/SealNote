import SwiftUI

struct EncryptedCardView: View {
    private let info: EncryptedNoteInfo?
    private let updatedAt: Date
    var isKeyLoaded: Bool = false
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelect: (() -> Void)?

    init(
        info: EncryptedNoteInfo,
        isKeyLoaded: Bool = false,
        isSelected: Bool = false,
        isSelecting: Bool = false,
        onOpen: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onToggleSelect: (() -> Void)? = nil
    ) {
        self.info = info
        self.updatedAt = info.updatedAt
        self.isKeyLoaded = isKeyLoaded
        self.isSelected = isSelected
        self.isSelecting = isSelecting
        self.onOpen = onOpen
        self.onDelete = onDelete
        self.onToggleSelect = onToggleSelect
    }

    init(note: Note, onOpen: (() -> Void)? = nil) {
        self.info = nil
        self.updatedAt = note.updatedAt
        self.onOpen = onOpen
    }

    var body: some View {
        #if os(iOS)
        compactLockedCard
        #else
        if let info {
            detailedCard(info)
        } else {
            compactLockedCard
        }
        #endif
    }

    private var compactLockedCard: some View {
        HStack(alignment: .top, spacing: DS.s3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.textSubtle)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: DS.s2) {
                Text("加密笔记")
                    .font(DS.body().weight(.semibold))
                    .foregroundColor(DS.textBody)

                Text("当前版本暂不支持在 iPhone 或 iPad 上查看和编辑")
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(2)

                Text(timestampText)
                    .font(DS.caption())
                    .foregroundColor(DS.textSubtle)
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface(shadow: false)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen?()
        }
        #if os(iOS)
        .contextMenu {
            compactCardActions
        }
        #endif
    }

    @ViewBuilder
    private var compactCardActions: some View {
        if let onOpen {
            Button { onOpen() } label: {
                Label(openActionTitle, systemImage: openActionIcon)
            }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func detailedCard(_ info: EncryptedNoteInfo) -> some View {
        HStack(alignment: .top, spacing: DS.s3) {
            if isSelecting {
                selectionCircle
                    .padding(.top, DS.s1)
            }

            VStack(alignment: .leading, spacing: DS.memoGap) {
                HStack(spacing: DS.s2) {
                    Text(timestampText)
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                        .lineLimit(1)

                    Spacer()

                    if !isSelecting {
                        Menu {
                            if let onOpen {
                                Button { onOpen() } label: {
                                    Label(openActionTitle, systemImage: openActionIcon)
                                }
                            }
                            if onOpen != nil && onDelete != nil {
                                Divider()
                            }
                            if let onDelete {
                                Button(role: .destructive) { onDelete() } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DS.textSubtle)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                }

                Text(info.title)
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                    .lineLimit(1)

                Text(info.ciphertextPreview)
                    .font(DS.mono())
                    .foregroundColor(DS.textSubtle)
                    .lineLimit(3)
                    .opacity(0.7)

                HStack(spacing: DS.s1) {
                    Text(isKeyLoaded ? "点击解锁查看" : "前往密钥设置")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)

                    Text("·")
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)

                    Text(formatFileSize(info.fileSize))
                        .font(DS.caption())
                        .foregroundColor(DS.textSubtle)
                }
            }
        }
        .padding(DS.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface(shadow: false)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            } else {
                onOpen?()
            }
        }
    }

    private var timestampText: String {
        DateFormatters.formatDisplayDateTime(updatedAt)
            .replacingOccurrences(of: ".", with: "-")
    }

    private var openActionTitle: String {
        isKeyLoaded ? "解锁查看" : "打开密钥设置"
    }

    private var openActionIcon: String {
        isKeyLoaded ? "lock.open" : "key"
    }

    private var selectionCircle: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor(isSelected ? DS.primary : DS.textSubtle.opacity(0.5))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { onToggleSelect?() }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

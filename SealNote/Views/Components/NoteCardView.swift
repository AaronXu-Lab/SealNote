import SwiftUI
#if os(iOS)
import UIKit
#endif

struct NoteCardView: View {
    let note: Note
    var displayTitle: String? = nil
    var excludesHexColorsFromTags: Bool = false
    var isCloudOnly: Bool = false
    var cloudDownloadState: CloudNoteDownloadState? = nil
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onTap: (() -> Void)?
    var onRename: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelect: (() -> Void)?
    var onRetryDownload: (() -> Void)?
    var onBecomeVisible: (() -> Void)?

    var body: some View {
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
                            cardActions
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DS.textSubtle)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                }

                if isCloudOnly {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        Text(displayTitle ?? NoteTitleFormatter.emptyTitle)
                            .font(DS.body().weight(.semibold))
                            .foregroundColor(DS.textBody)
                            .lineLimit(2)

                        cloudLoadingStatus
                    }
                } else if note.isEncrypted {
                    VStack(alignment: .leading, spacing: DS.s2) {
                        Text(displayTitle ?? NoteTitleFormatter.displayTitle(from: note.body))
                            .font(DS.body().weight(.semibold))
                            .foregroundColor(DS.textBody)
                            .lineLimit(2)

                        Label("加密笔记，打开后查看正文", systemImage: "lock.fill")
                            .font(DS.caption())
                            .foregroundColor(DS.textSubtle)
                    }
                } else {
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        VStack(alignment: .leading, spacing: DS.s2) {
                            Text(displayTitle ?? NoteTitleFormatter.displayTitle(from: note.body))
                                .font(DS.body().weight(.semibold))
                                .foregroundColor(DS.textBody)
                                .lineLimit(2)

                            if !summaryText.isEmpty {
                                Text(summaryText)
                                    .font(DS.body())
                                    .foregroundColor(DS.textSecondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text(note.body)
                            .font(DS.body())
                            .foregroundColor(DS.textBody)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    #else
                    tagAwareText(note.body)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                    #endif
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.cardPadding)
        .padding(.vertical, DS.cardPadding)
        .dsCardSurface(shadow: false)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelect?()
            } else {
                onTap?()
            }
        }
        .onAppear {
            onBecomeVisible?()
        }
        #if os(iOS)
        .contextMenu {
            if !isSelecting {
                cardActions
            }
        }
        #endif
    }

    @ViewBuilder
    private var cloudLoadingStatus: some View {
        switch cloudDownloadState {
        case .downloading:
            HStack(spacing: DS.s2) {
                ProgressView()
                    .controlSize(.small)
                Text("正在载入正文…")
            }
            .font(DS.caption())
            .foregroundColor(DS.textSubtle)

        case .failed:
            HStack(spacing: DS.s2) {
                Label("正文暂时无法载入", systemImage: "exclamationmark.icloud")
                if let onRetryDownload {
                    Button("重试", action: onRetryDownload)
                        .buttonStyle(.borderless)
                }
            }
            .font(DS.caption())
            .foregroundColor(DS.textSubtle)

        case .queued, .none:
            Label("正文正在同步", systemImage: "icloud")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
        }
    }

    private var summaryText: String {
        let lines = note.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().joined(separator: "\n")
    }

    @ViewBuilder
    private var cardActions: some View {
        if let onRename {
            Button { onRename() } label: {
                Label("重命名", systemImage: "pencil.line")
            }
        }
        if let onEdit {
            Button { onEdit() } label: {
                Label("编辑", systemImage: "pencil")
            }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var timestampText: String {
        let timestamp = DateFormatters.formatDisplayDateTime(note.updatedAt)
            .replacingOccurrences(of: ".", with: "-")
        #if os(iOS)
        return timestamp
        #else
        return note.isEncrypted ? "\(timestamp) · 加密" : timestamp
        #endif
    }

    private var selectionCircle: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .regular))
            .foregroundColor(isSelected ? DS.primary : DS.textSubtle.opacity(0.5))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture { onToggleSelect?() }
    }

    private func tagAwareText(_ source: String) -> Text {
        let ns = source as NSString
        let matches = TagParser.matches(
            in: source,
            excludingHexColors: excludesHexColorsFromTags
        )

        if matches.isEmpty {
            return Text(source)
                .font(DS.body())
                .foregroundColor(DS.textBody)
        }

        var result = Text("")
        var cursor = 0
        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
                let beforeText = Text(before)
                    .font(DS.body())
                    .foregroundColor(DS.textBody)
                result = Text("\(result)\(beforeText)")
            }
            let tag = ns.substring(with: matchRange)
            let tagText = Text(tag)
                .font(DS.body())
                .foregroundColor(DS.primary)
            result = Text("\(result)\(tagText)")
            cursor = matchRange.location + matchRange.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            let tailText = Text(tail)
                .font(DS.body())
                .foregroundColor(DS.textBody)
            result = Text("\(result)\(tailText)")
        }
        return result
    }
}

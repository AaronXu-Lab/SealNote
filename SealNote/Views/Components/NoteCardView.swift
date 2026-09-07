import SwiftUI
#if os(iOS)
import UIKit
#endif

struct NoteCardView: View {
    let note: Note
    var displayTitle: String? = nil
    var excludesHexColorsFromTags: Bool = false
    var isCloudOnly: Bool = false
    var usesIPadGridLayout: Bool = false
    var isSelected: Bool = false
    var isSelecting: Bool = false
    var onTap: (() -> Void)?
    var onRename: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleSelect: (() -> Void)?
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
                    Text(displayTitle ?? NoteTitleFormatter.emptyTitle)
                        .font(DS.body().weight(.semibold))
                        .foregroundColor(DS.textBody)
                        .lineLimit(2)
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
                    if usesIPadGridLayout {
                        VStack(alignment: .leading, spacing: DS.s2) {
                            Text(displayTitle ?? NoteTitleFormatter.displayTitle(from: note.body))
                                .font(DS.body().weight(.semibold))
                                .foregroundColor(DS.textBody)
                                .lineLimit(2)

                            if !summaryText.isEmpty {
                                Text(summaryText)
                                    .font(DS.body())
                                    .foregroundColor(DS.textSecondary)
                                    .lineLimit(usesIPadGridLayout ? 4 : 3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        MarkdownCardBody(source: note.body, theme: SettingsStore.shared.appTheme).equatable()
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
        .frame(
            minHeight: usesIPadGridLayout ? DS.iPadGridCardHeight : nil,
            maxHeight: usesIPadGridLayout ? DS.iPadGridCardHeight : nil,
            alignment: .topLeading
        )
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

    private var summaryText: String {
        let lines = note.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
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

#if os(iOS)
private struct MarkdownCardBody: View, Equatable {
    private static let collapsedLineLimit = 5

    let source: String
    let theme: AppTheme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.theme == rhs.theme
    }

    private var highlightedText: NSAttributedString {
        MarkdownHighlighter.makeIOSHighlightedAttributedString(text: source, fontSize: 15, lineHeightMultiple: 1.3)
    }

    @State private var isExpanded = false
    @State private var renderedLineCount = 0

    private var remainingLineCount: Int {
        max(0, renderedLineCount - Self.collapsedLineLimit)
    }

    var body: some View {
        let rendered = highlightedText
        VStack(alignment: .leading, spacing: DS.s2) {
            Text(AttributedString(rendered))
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                updateRenderedLineCount(for: proxy.size.width, text: rendered)
                            }
                            .onChange(of: source) { _, _ in
                                updateRenderedLineCount(for: proxy.size.width, text: rendered)
                            }
                            .onChange(of: proxy.size.width) { _, width in
                                updateRenderedLineCount(for: width, text: rendered)
                            }
                    }
                }

            if !isExpanded, remainingLineCount > 0 {
                Button("展开剩余 \(remainingLineCount) 行") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
                .buttonStyle(.plain)
                .font(DS.caption().weight(.semibold))
                .foregroundColor(DS.primaryDeep)
                .accessibilityHint("显示卡片中隐藏的 Markdown 内容")
            }
        }
        .onChange(of: source) { _, _ in
            isExpanded = false
        }
    }

    private func updateRenderedLineCount(for width: CGFloat, text: NSAttributedString) {
        guard width > 0 else { return }

        let textStorage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var count = 0
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            count += 1
        }
        renderedLineCount = count
    }
}
#endif

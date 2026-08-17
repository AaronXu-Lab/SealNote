#if os(iOS)
import SwiftUI
import UIKit
import MarkdownView

/// The iOS note canvas. It owns rendering only; persistence and toolbar actions
/// remain in `NoteEditorView`.
struct NoteEditorContentView: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isEditing: Bool

    let isPreviewing: Bool
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let autofocus: Bool

    var body: some View {
        if isPreviewing {
            NoteMarkdownPreview(
                text: text,
                fontSize: fontSize,
                lineHeightMultiple: lineHeightMultiple
            )
        } else {
            GeometryReader { geometry in
                NoteTextView(
                    text: $text,
                    selectedRange: $selectedRange,
                    isEditing: $isEditing,
                    placeholder: "写下想法，支持 Markdown",
                    fontSize: fontSize,
                    lineHeightMultiple: lineHeightMultiple,
                    autofocus: autofocus
                )
                .frame(
                    width: min(geometry.size.width, DS.contentMax),
                    height: geometry.size.height
                )
                .frame(maxWidth: .infinity, alignment: .top)
                .noteEditorScrollEdgeEffect()
            }
            .layoutPriority(1)
        }
    }
}

private struct NoteMarkdownPreview: View {
    let text: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat

    var body: some View {
        ScrollView {
            Group {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("随便写点什么吧")
                        .font(.system(size: fontSize))
                        .foregroundColor(DS.textSubtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownView(text)
                        .font(.system(size: fontSize), for: .body)
                        .font(
                            .system(size: max(11, fontSize - 1), design: .monospaced),
                            for: .codeBlock
                        )
                        .markdownComponentSpacing(max(8, fontSize * (lineHeightMultiple - 0.7)))
                        .markdownMathRenderingEnabled()
                        .foregroundStyle(DS.textBody)
                        .headingStyle(DS.textEmphasize, for: .h1)
                        .headingStyle(DS.textEmphasize, for: .h2)
                        .headingStyle(DS.textEmphasize, for: .h3)
                        .headingStyle(DS.textEmphasize, for: .h4)
                        .headingStyle(DS.textEmphasize, for: .h5)
                        .headingStyle(DS.textEmphasize, for: .h6)
                        .tint(DS.primaryDeep)
                        .tint(DS.link, for: .link)
                        .tint(DS.link, for: .blockQuote)
                        .tint(DS.primaryDeep, for: .inlineCodeBlock)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DS.cardPadding * 2)
            .frame(maxWidth: DS.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .noteEditorScrollEdgeEffect()
    }
}

private extension View {
    @ViewBuilder
    func noteEditorScrollEdgeEffect() -> some View {
        if #available(iOS 27.0, *) {
            scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            self
        }
    }
}

private final class PlaceholderTextView: UITextView {
    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    private let placeholderLabel = UILabel()
    private(set) var editorFontSize: CGFloat = 15
    private(set) var editorLineHeightMultiple: CGFloat = 1.3
    private var isCorrectingContentSize = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        correctHighlightedContentSizeIfNeeded()
    }

    private func setup() {
        isEditable = true
        isSelectable = true
        backgroundColor = .clear
        isScrollEnabled = true
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        if #available(iOS 27.0, *) {
            topEdgeEffect.style = .soft
            bottomEdgeEffect.style = .soft
            bottomEdgeEffect.isHidden = true
        }
        isFindInteractionEnabled = true
        autocapitalizationType = .sentences
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        autocorrectionType = .default
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        let font = UIFont.systemFont(ofSize: editorFontSize)
        self.font = font
        typingAttributes = MarkdownHighlighter.iosTypingAttributes(
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.widthTracksTextView = true
        textContainerInset = UIEdgeInsets(
            top: DS.cardPadding,
            left: DS.cardPadding,
            bottom: DS.cardPadding,
            right: DS.cardPadding
        )

        placeholderLabel.textColor = UIColor(DS.textSubtle)
        placeholderLabel.font = font
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: DS.cardPadding),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.cardPadding),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.cardPadding)
        ])

        layer.cornerRadius = DS.rMd
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(DS.line).cgColor
        updatePlaceholderVisibility()
    }

    func applyMarkdownHighlighting(
        text newText: String,
        selectedRange range: NSRange,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat
    ) {
        editorFontSize = fontSize
        editorLineHeightMultiple = lineHeightMultiple
        placeholderLabel.font = UIFont.systemFont(ofSize: fontSize)

        let attributed = MarkdownHighlighter.makeIOSHighlightedAttributedString(
            text: newText,
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        let preservedContentOffset = contentOffset
        let undoManager = undoManager
        let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
        if shouldRestoreUndoRegistration {
            undoManager?.disableUndoRegistration()
        }
        textStorage.setAttributedString(attributed)
        if shouldRestoreUndoRegistration, undoManager?.isUndoRegistrationEnabled == false {
            undoManager?.enableUndoRegistration()
        }

        typingAttributes = MarkdownHighlighter.iosTypingAttributes(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        selectedRange = safeRange(range, in: newText)
        setContentOffset(preservedContentOffset, animated: false)
        updatePlaceholderVisibility()
    }

    func applyIncrementalHighlighting() {
        let nsText = text as NSString
        typingAttributes = MarkdownHighlighter.iosTypingAttributes(
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
        guard nsText.length > 0 else { return }

        let caret = min(max(0, selectedRange.location), nsText.length)
        let dirtyRange = nsText.paragraphRange(for: NSRange(location: caret, length: 0))
        MarkdownHighlighter.applyIOSHighlighting(
            to: textStorage,
            text: text,
            dirtyRange: dirtyRange,
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
    }

    func usesStyle(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> Bool {
        editorFontSize == fontSize && editorLineHeightMultiple == lineHeightMultiple
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func correctHighlightedContentSizeIfNeeded() {
        guard !isCorrectingContentSize, bounds.width > 0 else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let measuredHeight = ceil(usedRect.maxY + textContainerInset.top + textContainerInset.bottom)
        guard measuredHeight.isFinite else { return }

        let targetHeight = max(bounds.height, measuredHeight)
        guard abs(contentSize.height - targetHeight) > 1 else { return }

        let preservedOffset = contentOffset
        isCorrectingContentSize = true
        contentSize.height = targetHeight

        let minimumY = -adjustedContentInset.top
        let maximumY = max(minimumY, targetHeight - bounds.height + adjustedContentInset.bottom)
        let restoredY = min(max(preservedOffset.y, minimumY), maximumY)
        if abs(contentOffset.y - restoredY) > 0.5 {
            setContentOffset(CGPoint(x: preservedOffset.x, y: restoredY), animated: false)
        }
        isCorrectingContentSize = false
    }

    private func safeRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(range.length, maxLength))
    }
}

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isEditing: Bool

    let placeholder: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let autofocus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange, isEditing: $isEditing)
    }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder

        context.coordinator.isUpdating = true
        textView.applyMarkdownHighlighting(
            text: text,
            selectedRange: selectedRange,
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        textView.selectedRange = selectedRange
        context.coordinator.isUpdating = false
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.backgroundColor = .clear
        if autofocus {
            context.coordinator.requestFocusIfNeeded(for: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        uiView.placeholder = placeholder
        let styleChanged = !uiView.usesStyle(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        if (uiView.text != text || styleChanged) && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            uiView.applyMarkdownHighlighting(
                text: text,
                selectedRange: selectedRange,
                fontSize: fontSize,
                lineHeightMultiple: lineHeightMultiple
            )
            context.coordinator.isUpdating = false
        }

        if uiView.isFirstResponder, uiView.selectedRange != selectedRange {
            context.coordinator.isUpdating = true
            uiView.selectedRange = selectedRange
            context.coordinator.isUpdating = false
        }
        uiView.updatePlaceholderVisibility()
        if autofocus {
            context.coordinator.requestFocusIfNeeded(for: uiView)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PlaceholderTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var selectedRange: Binding<NSRange>
        var isEditing: Binding<Bool>
        weak var textView: PlaceholderTextView?
        var isUpdating = false

        private var didRequestFocus = false
        private var highlightWorkItem: DispatchWorkItem?
        private static let largeDocumentThreshold = 30_000

        init(text: Binding<String>, selectedRange: Binding<NSRange>, isEditing: Binding<Bool>) {
            self.text = text
            self.selectedRange = selectedRange
            self.isEditing = isEditing
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing.wrappedValue = false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true

            let newText = textView.text ?? ""
            text.wrappedValue = newText
            selectedRange.wrappedValue = textView.selectedRange
            if textView.markedTextRange != nil {
                (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
                isUpdating = false
                return
            }
            if let placeholderTextView = textView as? PlaceholderTextView {
                scheduleIncrementalHighlight(for: placeholderTextView)
                placeholderTextView.updatePlaceholderVisibility()
            }
            isUpdating = false
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n",
                  range.length == 0,
                  textView.markedTextRange == nil,
                  let textView = textView as? PlaceholderTextView else {
                return true
            }

            let currentText = textView.text ?? ""
            let currentSelection = NSRange(location: range.location, length: 0)
            let result: MacMarkdownFormatResult?
            if let completion = MarkdownFormatter.completeCodeFenceIfNeeded(
                in: currentText,
                selection: currentSelection
            ) {
                result = MacMarkdownFormatResult(
                    text: completion.text,
                    selection: completion.selection
                )
            } else if let continuation = MarkdownFormatter.continueListIfNeeded(
                in: currentText,
                selection: currentSelection
            ) {
                result = MacMarkdownFormatResult(
                    text: continuation.text,
                    selection: continuation.selection
                )
            } else {
                result = nil
            }

            guard let result else { return true }
            isUpdating = true
            text.wrappedValue = result.text
            selectedRange.wrappedValue = result.selection
            textView.applyMarkdownHighlighting(
                text: result.text,
                selectedRange: result.selection,
                fontSize: textView.editorFontSize,
                lineHeightMultiple: textView.editorLineHeightMultiple
            )
            isUpdating = false
            return false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating, textView.isFirstResponder else { return }
            selectedRange.wrappedValue = textView.selectedRange
        }

        func requestFocusIfNeeded(for textView: UITextView) {
            guard !didRequestFocus else { return }
            didRequestFocus = true
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        private func scheduleIncrementalHighlight(for textView: PlaceholderTextView) {
            highlightWorkItem?.cancel()
            if (textView.text as NSString).length <= Self.largeDocumentThreshold {
                textView.applyIncrementalHighlighting()
            } else {
                let work = DispatchWorkItem { [weak textView] in
                    textView?.applyIncrementalHighlighting()
                }
                highlightWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        }
    }
}

private enum NoteEditorPreviewFixture {
    static let markdown = """
    ### 目标
    简化 NoteEditorView，并让编辑与预览状态可以独立检查。

    ### 检查项
    1. Markdown 高亮
    2. 长内容滚动
    3. 编辑焦点和 Sheet 手势

    <!-- Preview 不依赖真实 Vault -->
    """
}

private struct NoteEditorContentPreview: View {
    let isPreviewing: Bool

    @State private var text = NoteEditorPreviewFixture.markdown
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var isEditing = false

    var body: some View {
        NoteEditorContentView(
            text: $text,
            selectedRange: $selectedRange,
            isEditing: $isEditing,
            isPreviewing: isPreviewing,
            fontSize: 16,
            lineHeightMultiple: 1.3,
            autofocus: false
        )
        .background(DS.surfaceRaised)
    }
}

#Preview("Note editor") {
    NoteEditorContentPreview(isPreviewing: false)
}

#Preview("Markdown preview") {
    NoteEditorContentPreview(isPreviewing: true)
}
#endif

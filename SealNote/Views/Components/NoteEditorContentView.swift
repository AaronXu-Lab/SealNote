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
    var noteID: String? = nil
    @State private var didShowPreview = false
    @State private var previewText = ""

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                NoteTextView(
                    text: $text,
                    selectedRange: $selectedRange,
                    isEditing: $isEditing,
                    placeholder: "写下想法，支持 Markdown",
                    fontSize: fontSize,
                    lineHeightMultiple: lineHeightMultiple,
                    autofocus: autofocus,
                    isPreviewing: isPreviewing,
                    noteID: noteID
                )
                .frame(width: min(geometry.size.width, DS.contentMax), height: geometry.size.height)
                .frame(maxWidth: .infinity, alignment: .top)
                .noteEditorScrollEdgeEffect()
            }
            .opacity(isPreviewing ? 0 : 1)
            .allowsHitTesting(!isPreviewing)
            .accessibilityHidden(isPreviewing)

            if isPreviewing || didShowPreview {
                NoteMarkdownPreview(text: isPreviewing ? text : previewText, fontSize: fontSize, lineHeightMultiple: lineHeightMultiple)
                    .opacity(isPreviewing ? 1 : 0)
                    .allowsHitTesting(isPreviewing)
                    .accessibilityHidden(!isPreviewing)
            }
        }
        .layoutPriority(1)
        .onChange(of: isPreviewing) { _, value in
            if value { didShowPreview = true }
            previewText = text
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
        didSet { if placeholder != oldValue { updatePlaceholderStyle() } }
    }

    private let placeholderLabel = UITextView()
    private(set) var editorFontSize: CGFloat = 15
    private(set) var editorLineHeightMultiple: CGFloat = 1.3
    private var isCorrectingContentSize = false
    private var placeholderWidth: CGFloat = -1
    private var measuredWidth: CGFloat = 0
    private var needsContentMeasurement = true
    private var requiresGlobalHighlighting = false
    private var needsGlobalAttributeRefresh = false

    func prepareHighlightingEdit(in range: NSRange, replacement: String) {
        let current = text as NSString
        let paragraph = current.substring(with: current.paragraphRange(for: range))
        if MarkdownHighlighter.requiresGlobalIOSHighlighting(paragraph)
            || MarkdownHighlighter.requiresGlobalIOSHighlighting(replacement)
            || (requiresGlobalHighlighting && (replacement.contains("\n") || current.substring(with: range).contains("\n"))) {
            needsGlobalAttributeRefresh = true
        }
    }

    func invalidateTextLayout() {
        needsContentMeasurement = true
        setNeedsLayout()
    }

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
        if !placeholderLabel.isHidden && placeholderWidth != bounds.width {
            placeholderWidth = bounds.width
            placeholderLabel.frame = CGRect(
                origin: .zero,
                size: CGSize(width: bounds.width, height: placeholderLabel.sizeThatFits(
                    CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
                ).height)
            )
        }
        correctHighlightedContentSizeIfNeeded()
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard !rect.isNull, rect.height > 0 else { return rect }
        let characterIndex = offset(from: beginningOfDocument, to: position)
        let caretFont: UIFont
        let baseline: CGFloat
        if textStorage.length > 0,
           !(characterIndex == textStorage.length && text.hasSuffix("\n")) {
            let index = min(max(0, characterIndex), textStorage.length - 1)
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            baseline = line.minY + layoutManager.location(forGlyphAt: glyph).y
            caretFont = textStorage.attribute(.font, at: index, effectiveRange: nil) as? UIFont
                ?? UIFont.systemFont(ofSize: editorFontSize)
        } else {
            // Empty paragraphs use the same baseline as the placeholder's first line.
            placeholderLabel.layoutManager.ensureLayout(for: placeholderLabel.textContainer)
            guard placeholderLabel.layoutManager.numberOfGlyphs > 0 else { return rect }
            baseline = layoutManager.extraLineFragmentRect.minY
                + placeholderLabel.layoutManager.location(forGlyphAt: 0).y
            caretFont = UIFont.systemFont(ofSize: editorFontSize)
        }
        rect.origin.y = textContainerInset.top + baseline - caretFont.ascender
        rect.size.height = caretFont.ascender - caretFont.descender
        return rect
    }

    private func setup() {
        isEditable = true
        isSelectable = true
        backgroundColor = .clear
        tintColor = UIColor(DS.primary)
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

        // Use the same TextKit layout, paragraph style and insets as the body.
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.accessibilityElementsHidden = true
        placeholderLabel.contentInsetAdjustmentBehavior = .never
        placeholderLabel.isScrollEnabled = false
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.textContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        placeholderLabel.textContainerInset = textContainerInset
        addSubview(placeholderLabel)
        updatePlaceholderStyle()
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
        updatePlaceholderStyle()

        requiresGlobalHighlighting = MarkdownHighlighter.requiresGlobalIOSHighlighting(newText)
        needsGlobalAttributeRefresh = false
        invalidateTextLayout()
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

    func applyIncrementalHighlighting(changedRange: NSRange? = nil) {
        let nsText = text as NSString
        typingAttributes = MarkdownHighlighter.iosTypingAttributes(
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
        guard nsText.length > 0 else { return }

        let caret = min(max(0, selectedRange.location), nsText.length)
        let safeChangedRange = changedRange.map { range in
            let location = min(max(0, range.location), nsText.length)
            let length = min(range.length, max(0, nsText.length - location))
            return NSRange(location: location, length: length)
        }
        let dirtyRange = nsText.paragraphRange(
            for: safeChangedRange ?? NSRange(location: caret, length: 0)
        )
        let paragraph = nsText.substring(with: dirtyRange)
        let hasBlockMarkers = MarkdownHighlighter.requiresGlobalIOSHighlighting(paragraph)
        if hasBlockMarkers && !requiresGlobalHighlighting { needsGlobalAttributeRefresh = true }
        requiresGlobalHighlighting = requiresGlobalHighlighting || hasBlockMarkers
        MarkdownHighlighter.applyIOSHighlighting(
            to: textStorage,
            text: text,
            dirtyRange: needsGlobalAttributeRefresh ? NSRange(location: 0, length: nsText.length) : dirtyRange,
            localParagraphOnly: !requiresGlobalHighlighting,
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
        needsGlobalAttributeRefresh = false
        invalidateTextLayout()
    }

    func usesStyle(fontSize: CGFloat, lineHeightMultiple: CGFloat) -> Bool {
        editorFontSize == fontSize && editorLineHeightMultiple == lineHeightMultiple
    }

    private func updatePlaceholderStyle() {
        placeholderWidth = -1
        var attributes = MarkdownHighlighter.iosTypingAttributes(
            fontSize: editorFontSize,
            lineHeightMultiple: editorLineHeightMultiple
        )
        attributes[.foregroundColor] = UIColor(DS.textSubtle)
        placeholderLabel.attributedText = NSAttributedString(string: placeholder, attributes: attributes)
        setNeedsLayout()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func correctHighlightedContentSizeIfNeeded() {
        guard !isCorrectingContentSize, bounds.width > 0,
              needsContentMeasurement || measuredWidth != bounds.width else { return }
        needsContentMeasurement = false
        measuredWidth = bounds.width

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

@MainActor
private enum EditorPositionCache {
    struct Position { let selection: NSRange; let offset: CGPoint }
    static var positions: [String: Position] = [:]
    static var order: [String] = []
    static func save(_ id: String, selection: NSRange, offset: CGPoint) {
        positions[id] = Position(selection: selection, offset: offset)
        order.removeAll { $0 == id }
        order.append(id)
        if order.count > 64 { positions.removeValue(forKey: order.removeFirst()) }
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
    let isPreviewing: Bool
    let noteID: String?

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
        if let noteID, let position = EditorPositionCache.positions[noteID] {
            let length = (text as NSString).length
            let location = min(position.selection.location, length)
            textView.selectedRange = NSRange(location: location, length: min(position.selection.length, length - location))
            context.coordinator.restoredOffset = position.offset
        } else {
            textView.selectedRange = selectedRange
        }
        context.coordinator.noteID = noteID
        context.coordinator.isUpdating = false
        if let offset = context.coordinator.restoredOffset {
            DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
                guard let textView, let coordinator else { return }
                textView.layoutIfNeeded()
                textView.setContentOffset(offset, animated: false)
                coordinator.selectedRange.wrappedValue = textView.selectedRange
                coordinator.restoredOffset = nil
            }
        }
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.backgroundColor = .clear
        if autofocus && !isPreviewing {
            context.coordinator.requestFocusIfNeeded(for: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        context.coordinator.noteID = noteID
        context.coordinator.setPreviewing(isPreviewing, in: uiView)
        uiView.tintColor = UIColor(DS.primary)
        uiView.placeholder = placeholder
        let styleChanged = !uiView.usesStyle(
            fontSize: fontSize,
            lineHeightMultiple: lineHeightMultiple
        )
        if (uiView.text != text || styleChanged) && !context.coordinator.isUpdating && uiView.markedTextRange == nil {
            context.coordinator.cancelHighlighting()
            context.coordinator.isUpdating = true
            uiView.applyMarkdownHighlighting(
                text: text,
                selectedRange: selectedRange,
                fontSize: fontSize,
                lineHeightMultiple: lineHeightMultiple
            )
            context.coordinator.isUpdating = false
        }

        if context.coordinator.restoredOffset == nil, uiView.isFirstResponder, uiView.selectedRange != selectedRange {
            context.coordinator.isUpdating = true
            uiView.selectedRange = selectedRange
            context.coordinator.isUpdating = false
        }
        uiView.updatePlaceholderVisibility()
        if autofocus && !isPreviewing {
            context.coordinator.requestFocusIfNeeded(for: uiView)
        }
    }

    static func dismantleUIView(_ uiView: PlaceholderTextView, coordinator: Coordinator) {
        coordinator.savePosition(uiView)
        coordinator.cancelHighlighting()
        uiView.delegate = nil
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

        var noteID: String?
        var restoredOffset: CGPoint?
        private var resumeFocus = false
        private var previewing = false

        func setPreviewing(_ value: Bool, in view: UITextView) {
            guard previewing != value else { return }
            previewing = value
            // Delegate focus callbacks publish bindings; defer until SwiftUI's
            // representable update has finished, and ignore superseded toggles.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.previewing == value else { return }
                if value {
                    self.resumeFocus = view.isFirstResponder
                    view.resignFirstResponder()
                } else if self.resumeFocus {
                    self.resumeFocus = false
                    view.becomeFirstResponder()
                }
            }
        }
        private var pendingEditRange: NSRange?
        private var pendingDirtyRange: NSRange?
        private var didRequestFocus = false

        func cancelHighlighting() {
            highlightWorkItem?.cancel()
            highlightWorkItem = nil
            pendingDirtyRange = nil
            pendingEditRange = nil
        }

        func savePosition(_ view: UITextView) {
            guard let noteID, restoredOffset == nil else { return }
            EditorPositionCache.save(noteID, selection: view.selectedRange, offset: view.contentOffset)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if let view = scrollView as? UITextView { savePosition(view) }
        }
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

            let oldText = text.wrappedValue
            let newText = textView.text ?? ""
            let changedRange = pendingEditRange ?? MarkdownHighlighter.changedRange(from: oldText, to: newText)
            pendingEditRange = nil
            // Expand from the earliest dirty location to the end. This remains valid
            // when subsequent edits shift earlier pending ranges, including IME edits.
            if let pending = pendingDirtyRange {
                let start = min(pending.location, changedRange.location)
                pendingDirtyRange = NSRange(location: start, length: max(0, (newText as NSString).length - start))
            } else {
                pendingDirtyRange = changedRange
            }
            (textView as? PlaceholderTextView)?.invalidateTextLayout()
            text.wrappedValue = newText
            selectedRange.wrappedValue = textView.selectedRange
            if textView.markedTextRange != nil {
                (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
                isUpdating = false
                return
            }
            if let placeholderTextView = textView as? PlaceholderTextView {
                scheduleIncrementalHighlight(for: placeholderTextView, changedRange: changedRange)
                placeholderTextView.updatePlaceholderVisibility()
            }
            isUpdating = false
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            (textView as? PlaceholderTextView)?.prepareHighlightingEdit(in: range, replacement: replacement)
            pendingEditRange = NSRange(location: range.location, length: (replacement as NSString).length)
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
            pendingEditRange = nil
            pendingDirtyRange = nil
            cancelHighlighting()
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
            savePosition(textView)
        }

        func requestFocusIfNeeded(for textView: UITextView) {
            guard !didRequestFocus else { return }
            didRequestFocus = true
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        private func scheduleIncrementalHighlight(for textView: PlaceholderTextView, changedRange: NSRange) {
            let wasPending = highlightWorkItem != nil
            highlightWorkItem?.cancel()
            if (textView.text as NSString).length <= Self.largeDocumentThreshold && !wasPending {
                textView.applyIncrementalHighlighting(changedRange: pendingDirtyRange ?? changedRange)
                pendingDirtyRange = nil
            } else {
                let work = DispatchWorkItem { [weak self, weak textView] in
                    guard let self, let textView, textView.markedTextRange == nil else { return }
                    textView.applyIncrementalHighlighting(changedRange: self.pendingDirtyRange)
                    self.pendingDirtyRange = nil
                    self.highlightWorkItem = nil
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

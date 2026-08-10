#if os(macOS)
import SwiftUI
import AppKit
import ImageIO
import QuickLookUI
import UniformTypeIdentifiers

enum MacAttachmentTrayLayout {
    static let thumbnailSize: CGFloat = 100
    static let thumbnailCornerRadius: CGFloat = DS.rMd
    static let verticalPadding: CGFloat = 16
    static let horizontalSpacing: CGFloat = 8

    static var occupiedHeight: CGFloat {
        thumbnailSize + verticalPadding * 2
    }
}

struct MacAttachmentTray: View {
    let noteId: String
    let attachments: [NoteAttachment]
    let isCommandPressed: Bool
    /// Only enabled while a visible text line is underneath the attachment tray.
    let showsObscuringOverlay: Bool
    let onOpen: (NoteAttachment) -> Void
    let onCopy: (NoteAttachment) -> Void
    let onRemove: (NoteAttachment) -> Void
    let thumbnailContent: ((NoteAttachment) -> AnyView)?

    var body: some View {
        if !attachments.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: MacAttachmentTrayLayout.horizontalSpacing) {
                        ForEach(attachments) { attachment in
                            MacAttachmentThumbnail(
                                noteId: noteId,
                                attachment: attachment,
                                isCommandPressed: isCommandPressed,
                                thumbnailContent: thumbnailContent?(attachment),
                                onOpen: { onOpen(attachment) },
                                onCopy: { onCopy(attachment) },
                                onRemove: { onRemove(attachment) }
                            )
                            .id(attachment.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, MacAttachmentTrayLayout.verticalPadding)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let lastId = attachments.last?.id {
                        proxy.scrollTo(lastId, anchor: .trailing)
                    }
                }
                .onChange(of: attachments.last?.id) { _, lastId in
                    guard let lastId else { return }
                    withAnimation(.snappy) {
                        proxy.scrollTo(lastId, anchor: .trailing)
                    }
                }
            }
            .frame(height: MacAttachmentTrayLayout.occupiedHeight)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.72), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .opacity(showsObscuringOverlay ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showsObscuringOverlay)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("图片附件")
        }
    }
}

private struct MacAttachmentThumbnail: View {
    let noteId: String
    let attachment: NoteAttachment
    let isCommandPressed: Bool
    let thumbnailContent: AnyView?
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var imageData: Data?
    @State private var isHovering = false
    @State private var didCopy = false
    @State private var isUnavailable = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: performPrimaryAction) {
                ZStack {
                    if let thumbnailContent {
                        thumbnailContent
                            .frame(width: MacAttachmentTrayLayout.thumbnailSize, height: MacAttachmentTrayLayout.thumbnailSize)
                    } else if let imageData, let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: MacAttachmentTrayLayout.thumbnailSize, height: MacAttachmentTrayLayout.thumbnailSize)
                            .clipped()
                    } else if isUnavailable {
                        ZStack {
                            Rectangle()
                                .fill(Color(nsColor: .quaternaryLabelColor))
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Rectangle()
                            .fill(Color(nsColor: .quaternaryLabelColor))
                        ProgressView()
                            .controlSize(.small)
                    }

                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                        .opacity(isHovering && isCommandPressed ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .frame(width: MacAttachmentTrayLayout.thumbnailSize, height: MacAttachmentTrayLayout.thumbnailSize)
                .clipShape(thumbnailShape)
                .contentShape(thumbnailShape)
            }
            .buttonStyle(.plain)
            .help(isCommandPressed ? "复制图片" : "使用 Quick Look 查看图片")
            .shadow(
                color: isHovering ? .black.opacity(0.12) : .clear,
                radius: isHovering ? 4 : 0,
                y: isHovering ? 1 : 0
            )
            .animation(.easeOut(duration: 0.16), value: isHovering)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("移除附件")
            .accessibilityLabel("移除附件")
            .accessibilityHidden(!showsRemoveButton)
            .opacity(showsRemoveButton ? 1 : 0)
            .allowsHitTesting(showsRemoveButton)
            .padding(6)
        }
        .frame(width: MacAttachmentTrayLayout.thumbnailSize, height: MacAttachmentTrayLayout.thumbnailSize)
        .contentShape(thumbnailShape)
        .contextMenu {
            Button(action: onCopy) {
                Label("复制图片", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("移除附件", systemImage: "trash")
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .task(id: attachment.id) {
            await loadThumbnail()
        }
        .accessibilityLabel(attachment.originalFileName)
        .accessibilityHint(isCommandPressed ? "按下以复制图片" : "按下以使用 Quick Look 查看图片")
    }

    private var thumbnailShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: MacAttachmentTrayLayout.thumbnailCornerRadius,
            style: .continuous
        )
    }

    private var showsRemoveButton: Bool {
        isHovering && !isCommandPressed
    }

    private func performPrimaryAction() {
        if isCommandPressed {
            onCopy()
            didCopy = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } else {
            onOpen()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        guard thumbnailContent == nil else { return }
        do {
            let url = try await VaultStore.shared.attachmentURL(for: attachment, noteId: noteId)
            let data = await Task.detached(priority: .utility) {
                Self.thumbnailData(at: url)
            }.value
            guard let data else {
                isUnavailable = true
                return
            }
            imageData = data
        } catch {
            isUnavailable = true
        }
    }

    nonisolated private static func thumbnailData(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

private final class MacAttachmentPreviewItem: NSObject, QLPreviewItem {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { title }
}

final class MacAttachmentQuickLookController: NSObject, QLPreviewPanelDataSource {
    static let shared = MacAttachmentQuickLookController()

    private var items: [MacAttachmentPreviewItem] = []

    func present(urls: [(URL, String)], selectedIndex: Int) {
        items = urls.map { MacAttachmentPreviewItem(url: $0.0, title: $0.1) }
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.currentPreviewItemIndex = min(max(0, selectedIndex), max(0, items.count - 1))
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem {
        items[index]
    }
}

extension MacAttachmentQuickLookController {
    static func present(
        noteId: String,
        attachments: [NoteAttachment],
        selected attachment: NoteAttachment
    ) {
        Task { @MainActor in
            var urls: [(URL, String)] = []
            for item in attachments {
                if let url = try? await VaultStore.shared.attachmentURL(for: item, noteId: noteId) {
                    urls.append((url, item.originalFileName))
                }
            }
            guard let selectedIndex = urls.firstIndex(where: { $0.0.lastPathComponent == attachment.fileName }) else {
                return
            }
            shared.present(urls: urls, selectedIndex: selectedIndex)
        }
    }
}
#endif

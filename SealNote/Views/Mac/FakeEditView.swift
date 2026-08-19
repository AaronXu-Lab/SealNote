import SwiftUI

#if os(macOS) && DEBUG
import AppKit

struct FakeEditView: View {
    @State private var text = ""
    @State private var isCommandPressed = false
    @State private var isTextOverlappingAttachmentTray = false
    
    var body: some View {
        ZStack{
            MacTextView(
                text: $text,
                placeholder: "随便写点什么吧",
                fontSize: CGFloat(SettingsStore.defaultEditorFontSize),
                lineHeightMultiple: CGFloat(SettingsStore.defaultEditorLineHeightMultiple),
                bottomInset: MacStickyEditorLayout.editorBottomInset + MacAttachmentTrayLayout.occupiedHeight,
                onChange: { newText in
                    text = newText
                    print("FakeEditView: 文本已改变")
                },
                onSaveShortcut: { print("FakeEditView: 保存") },
                onApplyShortcut: { print("FakeEditView: 应用") },
                onFitToContent: { print("FakeEditView: 适应内容") },
                onCopyShortcut: { print("FakeEditView: 复制") },
                onFindShortcut: { print("FakeEditView: 搜索") },
                onIncreaseFontSize: { print("FakeEditView: 增大字号") },
                onDecreaseFontSize: { print("FakeEditView: 减小字号") },
                onAttachmentOverlapChange: { isOverlapping in
                    isTextOverlappingAttachmentTray = isOverlapping
                },
                onFindVisibilityChange: { isVisible in
                    print("FakeEditView: 搜索栏 \(isVisible ? "显示" : "隐藏")")
                }
            )
            VStack {
                Spacer()
                MacAttachmentTray(
                    noteId: "fake-note",
                    attachments: fakeAttachments,
                    isCommandPressed: isCommandPressed,
                    showsObscuringOverlay: isTextOverlappingAttachmentTray,
                    onOpen: { _ in print("适用 QuickLook 查看图片") },
                    onCopy: { _ in print("复制图片") },
                    onRemove: { _ in print("移除附件") },
                    thumbnailContent: { _ in
                        AnyView(Rectangle().fill(Color(nsColor: .labelColor)))
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .ignoresSafeArea(edges: .top)
        .dsMacStickyToolbarScrollEdge()
        .navigationTitle("")
        .onModifierKeysChanged(mask: .command) { _, modifiers in
            isCommandPressed = modifiers.contains(.command)
        }
        .toolbar {
            ToolbarSpacer()
            
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    print("FakeEditView: 上锁")
                } label: {
                    Label("上锁", systemImage: "lock.open.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .help("上锁")
                .controlSize(.small)
                
                Button {
                    print("FakeEditView: 复制")
                } label: {
                    Label("复制", systemImage: "square.on.square")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .help("复制")
                .controlSize(.small)
                
                Menu {
                    Button("重命名…", systemImage: "pencil") {
                        print("FakeEditView: 重命名")
                    }
                    
                    Divider()
                    
                    Button("适应内容", systemImage: "arrow.up.left.and.arrow.down.right") {
                        print("FakeEditView: 适应内容")
                    }
                    
                    Button("搜索", systemImage: "magnifyingglass") {
                        print("FakeEditView: 搜索")
                    }
                    
                    Divider()
                    
                    Button("转为加密笔记", systemImage: "lock") {
                        print("FakeEditView: 转为加密笔记")
                    }
                    
                    Divider()
                    
                    Button("移到回收站", systemImage: "trash", role: .destructive) {
                        print("FakeEditView: 移到回收站")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .menuIndicator(.hidden)
                .help("更多")
                .controlSize(.small)
            }
            
            ToolbarSpacer()
            
            ToolbarItem {
                Button {
                    print("FakeEditView: 置顶")
                } label: {
                    Label("置顶", systemImage: "pin.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: DS.macToolbarIconWidth)
                }
                .help("置顶")
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }
        }
    }

    private var fakeAttachments: [NoteAttachment] {
        (0..<20).map { index in
            NoteAttachment(
                id: "fake-attachment-\(index)",
                fileName: "fake-attachment-\(index).png",
                originalFileName: "模拟图片 \(index + 1).png",
                contentType: "public.png",
                order: index,
                byteCount: 0,
                sha256: "fake"
            )
        }
    }
}

#Preview("Fake EditView") {
    FakeEditView()
        .frame(width: 600, height: 520)
}
#endif

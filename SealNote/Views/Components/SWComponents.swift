import SwiftUI
import AaronUI

#if os(iOS)
import UIKit
#endif

#if os(iOS)
enum SWStatusBadgeStyle {
    case success
    case warning
    case error
    case neutral
}

struct SWStatusBadge: View {
    let text: String
    let systemImage: String?
    let style: SWStatusBadgeStyle

    init(_ text: String, systemImage: String? = nil, style: SWStatusBadgeStyle = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        AUIBadge(text, systemImage: systemImage, size: .sm, variant: .light,
                 color: style == .error ? .red : (style == .success ? .green : .primary))
    }
}

struct SWSectionPanel<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        Group {
            if let title {
                AUIItemSectionGroup(title) { content() }
            } else {
                AUIItemSectionGroup { content() }
            }
            if let footer {
                Text(footer).auiText(.caption).foregroundStyle(AUIColor.onSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .auiListRowInsets()
            }
        }
    }
}

struct SWPanelStack<Content: View>: View {
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let viewportTopPadding: CGFloat
    let viewportBottomPadding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        topPadding: CGFloat = DS.s4,
        bottomPadding: CGFloat = DS.s8,
        viewportTopPadding: CGFloat = 0,
        viewportBottomPadding: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.viewportTopPadding = viewportTopPadding
        self.viewportBottomPadding = viewportBottomPadding
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewportTopPadding > 0 {
                DS.bg.frame(height: viewportTopPadding)
            }

            List {
                content()
            }
            .auiItemListStyle()
            .contentMargins(.top, topPadding, for: .scrollContent)
            .contentMargins(.bottom, bottomPadding, for: .scrollContent)
            .scrollContentBackground(.hidden)

            if viewportBottomPadding > 0 {
                DS.bg.frame(height: viewportBottomPadding)
            }
        }
        .background(DS.bg)
    }
}

struct SWSettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let trailingMinWidth: CGFloat
    let tallControl: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = DS.primaryDeep,
        trailingMinWidth: CGFloat = 150,
        tallControl: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.tallControl = tallControl
        self.trailingMinWidth = trailingMinWidth
        self.trailing = trailing
    }

    var body: some View {
        AUIItem(title, description: subtitle, leading: .icon(systemImage)) {
            trailing()
        }
    }
}

struct SWRowDivider: View {
    var body: some View {
        // The caller-owned List supplies native row separators.
        EmptyView()
    }
}

struct SWEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        AUIEmptyState(title, systemImage: systemImage, description: message)
    }
}

#endif

#if os(macOS)
struct SWFilterChipMenu: View {
    let title: String
    let items: [String]
    let onSelect: (String) -> Void

    @State private var presenter = SWFilterChipMenuPresenter()

    var body: some View {
        AUIButton(title, variant: .outline, size: .sm) {
            presenter.present(items: items, onSelect: onSelect)
        }
        .background(SWFilterChipMenuAnchor(presenter: presenter))
    }
}

@MainActor
private final class SWFilterChipMenuPresenter: NSObject {
    weak var anchorView: NSView?
    private var onSelect: ((String) -> Void)?

    func present(items: [String], onSelect: @escaping (String) -> Void) {
        guard let anchorView, !items.isEmpty else { return }
        self.onSelect = onSelect

        let menu = NSMenu()
        menu.autoenablesItems = false
        for title in items {
            let item = NSMenuItem(title: title, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = title
            menu.addItem(item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: anchorView.bounds.minY),
            in: anchorView
        )
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String else { return }
        onSelect?(title)
    }
}

private struct SWFilterChipMenuAnchor: NSViewRepresentable {
    let presenter: SWFilterChipMenuPresenter

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughMenuAnchorView()
        presenter.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        presenter.anchorView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // The presenter owns no AppKit view; its weak reference clears naturally.
    }
}

private final class PassthroughMenuAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

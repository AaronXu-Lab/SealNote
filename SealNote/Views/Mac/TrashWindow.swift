import Foundation
import SwiftUI
import AaronUI

struct TrashView: View {
    @ObservedObject private var vaultStore = VaultStore.shared
    @State private var showingEmptyTrashConfirmation = false
    @State private var searchText = ""
    @State private var isSearchBarVisible = false
    @State private var actionErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isSearchBarVisible {
                MacListSearchBar(
                    placeholder: "搜索回收站…",
                    text: $searchText,
                    onClose: { hideSearchBar() }
                )
            }

            if filteredTrashNotes.isEmpty {
                emptyRow
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        listSummary

                        ForEach(filteredTrashNotes) { trashNote in
                            trashRow(for: trashNote)
                                .padding(.horizontal, DS.s3)
                                .padding(.vertical, DS.s1)
                                .contextMenu {
                                    Button("恢复") {
                                        restore(trashNote)
                                    }
                                    Button("永久删除", role: .destructive) {
                                        permanentlyDelete(trashNote)
                                    }
                                }
                        }

                        Color.clear
                            .frame(height: DS.s3)
                            .accessibilityHidden(true)
                    }
                }
                .background(DS.bg)
            }
        }
        .background(DS.bg)
        .macAaronUITheme()
        .dsLiquidGlassToolbar()
        .navigationTitle("回收站")
        .toolbar { trashToolbar }
        .background(MacListSearchToolbarAppearance(isActive: isSearchBarVisible))
        .alert("确认清空回收站？", isPresented: $showingEmptyTrashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("回收站中的所有笔记将被永久删除，无法恢复。")
        }
        .alert("操作失败", isPresented: actionErrorBinding) {
            Button("好") {
                actionErrorMessage = nil
            }
        } message: {
            Text(actionErrorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var trashToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                toggleSearchBar()
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("搜索")
            .keyboardShortcut("f", modifiers: .command)

            Button(role: .destructive) {
                showingEmptyTrashConfirmation = true
            } label: {
                Label("清空", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .disabled(vaultStore.trashNotes.isEmpty)
            .help(vaultStore.trashNotes.isEmpty ? "回收站为空" : "永久删除回收站中的所有笔记")
        }
    }

    private func toggleSearchBar() {
        if isSearchBarVisible {
            hideSearchBar()
        } else {
            isSearchBarVisible = true
        }
    }

    private func hideSearchBar() {
        isSearchBarVisible = false
        searchText = ""
    }

    private var listSummary: some View {
        HStack(spacing: DS.s2) {
            Spacer(minLength: 0)
            Text("回收站 \(filteredTrashNotes.count) 条笔记")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            Text(vaultStore.trashNotes.isEmpty ? "没有已删除笔记" : "删除的笔记会保留 30 天")
                .font(DS.caption())
                .foregroundColor(DS.textSubtle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.top, DS.s3 - DS.s4)
        .padding(.bottom, DS.s2)
        .padding(.top, 8)
    }

    private var filteredTrashNotes: [TrashNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vaultStore.trashNotes }
        return vaultStore.trashNotes.filter { trashNote in
            trashTitle(for: trashNote).localizedCaseInsensitiveContains(query)
                || trashNote.body?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var emptyRow: some View {
        AUIEmptyState(vaultStore.trashNotes.isEmpty ? "回收站为空" : "没有匹配的笔记", systemImage: "trash", description: vaultStore.trashNotes.isEmpty ? "删除的笔记会在这里保留 30 天" : "换个关键词试试，或清空搜索内容。")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DS.s6)
    }

    @ViewBuilder
    private func trashRow(for trashNote: TrashNote) -> some View {
        TrashListRow(
            title: trashTitle(for: trashNote),
            subtitle: trashNote.isEncrypted ? "" : trashNote.body.map(notePreview) ?? ""
        ) {
            HStack(spacing: DS.s4) {
                HStack(spacing: DS.s2) {
                    if trashNote.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DS.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(DS.surfaceSunken)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DS.line, lineWidth: 0.5))
                    }
                    AUIBadge("\(trashNote.remainingDays) 天", systemImage: "clock", size: .sm, variant: .light, color: .primary)
                }

                Menu {
                    Button("恢复") {
                        restore(trashNote)
                    }
                    Divider()
                    Button("永久删除", role: .destructive) {
                        permanentlyDelete(trashNote)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(DS.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(AUIButtonStyle(variant: .ghost, size: .sm, contentType: .icon))
                .controlSize(.regular)
                .tint(DS.textSecondary)
                .menuIndicator(.hidden)
                .help("更多操作")
            }
        }
    }

    private func trashTitle(for trashNote: TrashNote) -> String {
        if let body = trashNote.body {
            return firstLine(of: body)
        } else if trashNote.isEncrypted {
            return trashNote.title
        } else {
            return "(无内容)"
        }
    }

    private func notePreview(_ body: String) -> String {
        NoteTitleFormatter.displayTitle(from: body, emptyTitle: "")
    }

    private func firstLine(of body: String) -> String {
        NoteTitleFormatter.displayTitle(from: body, emptyTitle: NoteTitleFormatter.emptyTitle)
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    actionErrorMessage = nil
                }
            }
        )
    }

    private func restore(_ trashNote: TrashNote) {
        Task {
            do {
                try await vaultStore.restoreTrashNote(trashNote)
            } catch {
                presentActionError(error)
            }
        }
    }

    private func permanentlyDelete(_ trashNote: TrashNote) {
        Task {
            do {
                try await vaultStore.permanentlyDeleteTrashNote(trashNote)
            } catch {
                presentActionError(error)
            }
        }
    }

    private func emptyTrash() {
        Task {
            do {
                try await vaultStore.emptyTrash()
            } catch {
                presentActionError(error)
            }
        }
    }

    private func presentActionError(_ error: Error) {
        actionErrorMessage = error.localizedDescription
        SyncStatusStore.shared.setFailed(message: error.localizedDescription)
    }
}

/// Product metadata/actions remain caller-owned; the row surface comes from AaronUI.
struct TrashListRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        AUIItemSurface(size: .sm) {
            AUIItem(title, description: subtitle.isEmpty ? nil : subtitle, size: .sm, trailing: trailing)
        }
    }
}

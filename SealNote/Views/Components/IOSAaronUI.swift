#if os(iOS)
import SwiftUI
import AaronUI
import Combine

/// App-owned bindings and presentation; the controls themselves come from AaronUI.
struct SNSearchField: View {
    let prompt: String
    @Binding var text: String

    init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        self._text = text
    }

    var body: some View {
        AUIInput(prompt, text: $text, size: .lg, variant: .filled, leadingIcon: "magnifyingglass") {
            if !text.isEmpty {
                AUIButton("清空搜索", systemImage: "xmark", iconOnly: true, variant: .ghost, size: .sm) {
                    text = ""
                }
            }
        }
        .accessibilityLabel(prompt)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
    }
}

extension View {
    /// Present the library dialog in its own modal surface so it covers navigation
    /// chrome and keeps keyboard/VoiceOver interaction out of the underlying screen.
    func snDialog<Body: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        primary: AUIDialogAction? = nil,
        secondary: AUIDialogAction? = nil,
        additional: AUIDialogAction? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        accessibilityHidden(isPresented.wrappedValue)
            .fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            Color.clear
                .auiDialog(isPresented: isPresented, title: title, showClose: false,
                           primary: primary, secondary: secondary, additional: additional,
                           content: {
                               VStack(alignment: .leading, spacing: AUISpacing.lg) {
                                   content()
                               }
                           })
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
        }
    }
}
#endif

#if os(iOS)
/// Tracks one user-requested operation; failures keep the invoking task open.
@MainActor
final class MobileTaskState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    func reset() {
        guard !isRunning else { return }
        errorMessage = nil
    }

    func run(_ operation: @MainActor () async throws -> Void) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

extension View {
    func snAsyncDialog<Body: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        actionTitle: String,
        destructive: Bool = false,
        disabled: Bool = false,
        operation: @escaping @MainActor () async throws -> Void,
        onSuccess: @escaping @MainActor () -> Void = {},
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        modifier(MobileAsyncDialog(title: title, isPresented: isPresented,
                                   actionTitle: actionTitle, destructive: destructive,
                                   disabled: disabled, operation: operation,
                                   onSuccess: onSuccess, dialogContent: content))
    }
}

private struct MobileAsyncDialog<DialogContent: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let actionTitle: String
    let destructive: Bool
    let disabled: Bool
    let operation: @MainActor () async throws -> Void
    let onSuccess: @MainActor () -> Void
    let dialogContent: () -> DialogContent
    @StateObject private var taskState = MobileTaskState()
    @State private var completed = false

    func body(content: Content) -> some View {
        content.snDialog(title, isPresented: Binding(
            get: { isPresented },
            set: { if !taskState.isRunning { isPresented = $0 } }
        ), primary: AUIDialogAction(actionTitle, destructive: destructive,
                                    disabled: disabled || taskState.isRunning,
                                    loading: taskState.isRunning) {
            Task { @MainActor in
                guard await taskState.run(operation) else { return }
                completed = true
                isPresented = false
            }
        }, secondary: AUIDialogAction("取消", disabled: taskState.isRunning, closes: true),
           onDismiss: {
               if completed {
                   completed = false
                   onSuccess()
               }
           }) {
            dialogContent().disabled(taskState.isRunning)
            if let error = taskState.errorMessage {
                Text(error)
                    .foregroundStyle(AUIColor.error)
                    .accessibilityLabel("操作失败：\(error)")
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented { taskState.reset() }
        }
    }
}

/// Failed content keeps its explanation visible while only the recovery action spins.
struct SNErrorState: View {
    let title: String
    let message: String
    let isRetrying: Bool
    let retry: () -> Void
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AUISpacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(AUIColor.onSurfaceMuted)
                .accessibilityHidden(true)
            Text(title).auiText(.bodyMd).accessibilityAddTraits(.isHeader)
            Text(message).auiText(.bodySm).foregroundStyle(AUIColor.onSurfaceMuted)
            HStack {
                AUIButton("重试", variant: .fill, state: isRetrying ? .loading : .normal, action: retry)
                    .disabled(isRetrying)
                if let close {
                    AUIButton("关闭窗口", role: .cancel, action: close).disabled(isRetrying)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(AUISpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bg.ignoresSafeArea())
    }
}
#endif

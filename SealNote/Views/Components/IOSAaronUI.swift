#if os(iOS)
import SwiftUI
import AaronUI

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
        primary: AUIDialogAction,
        secondary: AUIDialogAction? = nil,
        additional: AUIDialogAction? = nil,
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        accessibilityHidden(isPresented.wrappedValue)
            .fullScreenCover(isPresented: isPresented) {
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

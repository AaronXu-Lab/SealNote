#if os(macOS)
import SwiftUI
import AaronUI

/// Brand colors are independent of neutral text aliases, so changing the accent
/// never turns ordinary labels pink/green/cyan or reduces their contrast.
enum MacAaronUITheme {
    @MainActor static func apply(_ theme: AppTheme) {
        let light: UInt32
        let dark: UInt32
        switch theme {
        case .pink: (light, dark) = (0xB52B6B, 0xFF94C5)
        case .cyan: (light, dark) = (0x087C8B, 0x33D2E3)
        case .green: (light, dark) = (0x247A4C, 0x65D99A)
        }
        func palette(_ hex: UInt32, dark: Bool) -> [AUIColorRole: Color] {
            let accent = Color(hex: hex)
            return [
                .primary: accent, .primaryInk: accent,
                .primarySoft: accent.opacity(dark ? 0.18 : 0.08),
                .accent: accent, .accentSubtle: accent.opacity(dark ? 0.18 : 0.08),
                .onSolid: Color(hex: dark ? 0x14201B : 0xFFFFFF),
                .onSurface: Color(hex: dark ? 0xD4D4D4 : 0x2E2E2E),
                .onSurfaceStrong: Color(hex: dark ? 0xFFFFFF : 0x121212),
                .onSurfaceMuted: Color(hex: dark ? 0xABABAB : 0x686868),
                .onSurfaceFaint: Color(hex: dark ? 0x949494 : 0x787878),
                .canvasRecessed: Color(hex: dark ? 0x101010 : 0xF5F5F5),
                .surface: Color(hex: dark ? 0x202020 : 0xFFFFFF),
                .surfaceSubtle: Color(hex: dark ? 0x282828 : 0xF5F5F5),
                .surfaceField: Color(hex: dark ? 0x252525 : 0xF5F5F5),
                .lineSelected: accent
            ]
        }
        _ = AUIColorTheme(light: palette(light, dark: false), dark: palette(dark, dark: true)).apply()
    }
}

/// Rebuild library views after its application-wide configuration changes.
/// Apply only to presentation content, never to an EditorSession's view tree.
private struct MacAaronUIThemeRefresh: ViewModifier {
    @ObservedObject private var settings = SettingsStore.shared
    func body(content: Content) -> some View {
        content.id(settings.appTheme)
    }
}

extension View {
    func macAaronUITheme() -> some View { modifier(MacAaronUIThemeRefresh()) }
}
#endif

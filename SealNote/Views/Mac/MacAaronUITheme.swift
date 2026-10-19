#if os(macOS)
import AaronUI

/// Brand parameters follow the logo hues; AaronUI owns every semantic role.
enum MacAaronUITheme {
    @MainActor static func apply(_ theme: AppTheme) {
        let hue: Double
        let lightChroma: Double
        let darkChroma: Double
        switch theme {
        case .pink: (hue, lightChroma, darkChroma) = (3.7704, 0.125, 0.10)
        case .cyan: (hue, lightChroma, darkChroma) = (204.7971, 0.10, 0.075)
        case .green: (hue, lightChroma, darkChroma) = (155.5123, 0.12, 0.09)
        }
        // L values are design targets; AaronUI resolves the nearest text/control-safe fills
        // at the same hue and maps chroma only when needed to fit sRGB.
        _ = AUIColorTheme.brand(
            light: AUIBrandPalette(hue: hue, chroma: lightChroma, fillLightness: 0.76),
            dark: AUIBrandPalette(hue: hue, chroma: darkChroma, fillLightness: 0.78)
        ).apply()
    }
}
#endif

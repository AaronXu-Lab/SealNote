import AppKit
import SwiftUI
import AaronUI
import XCTest
@testable import Seal_Note

@MainActor
final class MacAaronUIThemeTests: XCTestCase {
    func testAllBrandThemesKeepReadableTextInBothAppearances() throws {
        defer { MacAaronUITheme.apply(SettingsStore.shared.appTheme) }
        for theme in AppTheme.allCases {
            MacAaronUITheme.apply(theme)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let background = try resolve(AUIColor.primary, appearance)
                let foreground = try resolve(AUIColor.onSolid, appearance)
                XCTAssertGreaterThanOrEqual(contrast(background, foreground), 4.5, "\(theme) / \(appearance)")
                let surface = try resolve(AUIColor.surface, appearance)
                let body = try resolve(AUIColor.onSurface, appearance)
                XCTAssertGreaterThanOrEqual(contrast(surface, body), 4.5)
            }
        }
    }

    func testChangingBrandDoesNotTintNeutralText() throws {
        defer { MacAaronUITheme.apply(SettingsStore.shared.appTheme) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            var neutral: NSColor?
            var previousAccent: NSColor?
            for theme in AppTheme.allCases {
                MacAaronUITheme.apply(theme)
                let text = try resolve(AUIColor.onSurface, appearance)
                let accent = try resolve(AUIColor.primary, appearance)
                if let neutral { XCTAssertEqual(text, neutral) }
                if let previousAccent { XCTAssertNotEqual(accent, previousAccent) }
                neutral = text
                previousAccent = accent
            }
        }
    }

    private func resolve(_ color: Color, _ name: NSAppearance.Name) throws -> NSColor {
        var result: NSColor?
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            result = NSColor(color).usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(result)
    }

    private func contrast(_ first: NSColor, _ second: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            func linear(_ channel: CGFloat) -> Double {
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

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
                let background = try resolve(AUIColor.primaryFill, appearance)
                let foreground = try resolve(AUIColor.onPrimaryFill, appearance)
                if appearance == .aqua {
                    XCTAssertEqual(foreground.redComponent, 1, accuracy: 0.001)
                    XCTAssertEqual(foreground.greenComponent, 1, accuracy: 0.001)
                    XCTAssertEqual(foreground.blueComponent, 1, accuracy: 0.001)
                }
                XCTAssertGreaterThanOrEqual(contrast(background, foreground), 4.5, "\(theme) / \(appearance)")
                let hover = try resolve(AUIColor.primaryFillHover, appearance)
                XCTAssertGreaterThanOrEqual(contrast(hover, foreground), 4.5, "hover: \(theme) / \(appearance)")
                let surface = try resolve(AUIColor.surface, appearance)
                let body = try resolve(AUIColor.onSurface, appearance)
                XCTAssertGreaterThanOrEqual(contrast(surface, body), 4.5)
            }
        }
    }

    func testChangingBrandKeepsTextNearNeutral() throws {
        defer { MacAaronUITheme.apply(SettingsStore.shared.appTheme) }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            var previousAccent: NSColor?
            for theme in AppTheme.allCases {
                MacAaronUITheme.apply(theme)
                let text = try resolve(AUIColor.onSurface, appearance)
                let accent = try resolve(AUIColor.primary, appearance)
                // Official presets allow a subtle hue in near-neutral text.
                let channels = [text.redComponent, text.greenComponent, text.blueComponent]
                XCTAssertLessThan(channels.max()! - channels.min()!, 0.06, "\(theme) / \(appearance)")
                if let previousAccent { XCTAssertNotEqual(accent, previousAccent) }
                previousAccent = accent
            }
        }
    }

    func testBrandInkRemainsReadableOnSoftSurfaces() throws {
        defer { MacAaronUITheme.apply(SettingsStore.shared.appTheme) }
        for theme in AppTheme.allCases {
            MacAaronUITheme.apply(theme)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let ink = try resolve(AUIColor.primaryInk, appearance)
                for surface in [AUIColor.surface, AUIColor.primarySoft, AUIColor.accentSubtle] {
                    XCTAssertGreaterThanOrEqual(contrast(ink, try resolve(surface, appearance)), 4.5,
                                                "\(theme) / \(appearance)")
                }
            }
        }
    }

    func testBrandControlContrastInBothAppearances() throws {
        defer { MacAaronUITheme.apply(SettingsStore.shared.appTheme) }
        for theme in AppTheme.allCases {
            MacAaronUITheme.apply(theme)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let pairs: [(String, Color, Color, Double)] = [
                    ("fill text", AUIColor.onPrimaryFill, AUIColor.primaryFill, 4.5),
                    ("fill hover text", AUIColor.onPrimaryFill, AUIColor.primaryFillHover, 4.5),
                    ("selected switch thumb", AUIColor.switchThumbSelected, AUIColor.primaryFill, 3),
                    ("unselected switch thumb", AUIColor.switchThumb, AUIColor.surfaceTrack, 3),
                    ("selected switch track", AUIColor.primaryFill, AUIColor.surface, 3),
                    ("unselected switch track", AUIColor.surfaceTrack, AUIColor.surface, 3),
                    ("muted text", AUIColor.onSurfaceMuted, AUIColor.surface, 4.5),
                    ("faint text", AUIColor.onSurfaceFaint, AUIColor.surface, 4.5)
                ]
                for (name, foreground, background, minimum) in pairs {
                    let ratio = contrast(try resolve(foreground, appearance), try resolve(background, appearance))
                    print("COLOR-AUDIT \(theme) \(appearance.rawValue) \(name): \(String(format: "%.3f", ratio))")
                    XCTAssertGreaterThanOrEqual(ratio, minimum, "\(theme) / \(appearance) / \(name)")
                }
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

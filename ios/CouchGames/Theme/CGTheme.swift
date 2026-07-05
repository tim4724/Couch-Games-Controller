import SwiftUI
import UIKit

// MARK: - Hex color init

extension Color {
    /// Opaque sRGB color from a 0xRRGGBB literal.
    init(cgHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((cgHex >> 16) & 0xFF) / 255.0,
            green: Double((cgHex >> 8) & 0xFF) / 255.0,
            blue: Double(cgHex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - Palette

/// MONO graphite chrome palette (Material 3 roles, pre-baked hex — never re-derive lerps).
struct CGPalette: Equatable {
    let primary, onPrimary, primaryContainer, onPrimaryContainer: Color
    let secondary, onSecondary, secondaryContainer, onSecondaryContainer: Color
    let background, onBackground, surface, onSurface: Color
    let surfaceVariant, onSurfaceVariant, outline, outlineVariant: Color
    let surfaceContainerLowest, surfaceContainerLow, surfaceContainer, surfaceContainerHigh, surfaceContainerHighest, surfaceBright: Color
    let error, onError, inverseSurface, inverseOnSurface, scrim: Color

    static let light = CGPalette(
        primary: Color(cgHex: 0x202024),
        onPrimary: Color(cgHex: 0xFFFFFF),
        primaryContainer: Color(cgHex: 0xE5E1E9),
        onPrimaryContainer: Color(cgHex: 0x1B1B1F),
        secondary: Color(cgHex: 0x625B71),
        onSecondary: Color(cgHex: 0xFFFFFF),
        secondaryContainer: Color(cgHex: 0xD7D6DD),
        onSecondaryContainer: Color(cgHex: 0x1B1B1F),
        background: Color(cgHex: 0xFAFAFB),
        onBackground: Color(cgHex: 0x1C1B1F),
        surface: Color(cgHex: 0xFAFAFB),
        onSurface: Color(cgHex: 0x1C1B1F),
        surfaceVariant: Color(cgHex: 0xE4E3E7),
        onSurfaceVariant: Color(cgHex: 0x46464B),
        outline: Color(cgHex: 0x77767C),
        outlineVariant: Color(cgHex: 0xCAC9CE),
        surfaceContainerLowest: Color(cgHex: 0xFFFFFF),
        surfaceContainerLow: Color(cgHex: 0xF0F0F1),
        surfaceContainer: Color(cgHex: 0xEBEBEC),
        surfaceContainerHigh: Color(cgHex: 0xE4E4E5),
        surfaceContainerHighest: Color(cgHex: 0xDDDDDE),
        surfaceBright: Color(cgHex: 0xFEF7FF),
        error: Color(cgHex: 0xB3261E),
        onError: Color(cgHex: 0xFFFFFF),
        inverseSurface: Color(cgHex: 0x313033),
        inverseOnSurface: Color(cgHex: 0xF4EFF4),
        scrim: Color(cgHex: 0x000000)
    )

    static let dark = CGPalette(
        primary: Color(cgHex: 0xE6E1E9),
        onPrimary: Color(cgHex: 0x1C1B20),
        primaryContainer: Color(cgHex: 0x47444D),
        onPrimaryContainer: Color(cgHex: 0xE6E1E9),
        secondary: Color(cgHex: 0xCCC2DC),
        onSecondary: Color(cgHex: 0x332D41),
        secondaryContainer: Color(cgHex: 0x35353B),
        onSecondaryContainer: Color(cgHex: 0xE6E1E9),
        background: Color(cgHex: 0x0F0F11),
        onBackground: Color(cgHex: 0xE6E1E5),
        surface: Color(cgHex: 0x0F0F11),
        onSurface: Color(cgHex: 0xE6E1E5),
        surfaceVariant: Color(cgHex: 0x46464B),
        onSurfaceVariant: Color(cgHex: 0xC7C6CC),
        outline: Color(cgHex: 0x90909A),
        outlineVariant: Color(cgHex: 0x44444A),
        surfaceContainerLowest: Color(cgHex: 0x040405),
        surfaceContainerLow: Color(cgHex: 0x151517),
        surfaceContainer: Color(cgHex: 0x19191B),
        surfaceContainerHigh: Color(cgHex: 0x222224),
        surfaceContainerHighest: Color(cgHex: 0x2A2A2C),
        surfaceBright: Color(cgHex: 0x363638),
        error: Color(cgHex: 0xF2B8B5),
        onError: Color(cgHex: 0x601410),
        inverseSurface: Color(cgHex: 0xE6E1E5),
        inverseOnSurface: Color(cgHex: 0x313033),
        scrim: Color(cgHex: 0x000000)
    )

    /// Copy with primary = accent, onPrimary = contentColorOn(accent). (Game-host accent remap.)
    func withAccent(_ accent: Color) -> CGPalette {
        CGPalette(
            primary: accent,
            onPrimary: contentColorOn(accent),
            primaryContainer: primaryContainer,
            onPrimaryContainer: onPrimaryContainer,
            secondary: secondary,
            onSecondary: onSecondary,
            secondaryContainer: secondaryContainer,
            onSecondaryContainer: onSecondaryContainer,
            background: background,
            onBackground: onBackground,
            surface: surface,
            onSurface: onSurface,
            surfaceVariant: surfaceVariant,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            outlineVariant: outlineVariant,
            surfaceContainerLowest: surfaceContainerLowest,
            surfaceContainerLow: surfaceContainerLow,
            surfaceContainer: surfaceContainer,
            surfaceContainerHigh: surfaceContainerHigh,
            surfaceContainerHighest: surfaceContainerHighest,
            surfaceBright: surfaceBright,
            error: error,
            onError: onError,
            inverseSurface: inverseSurface,
            inverseOnSurface: inverseOnSurface,
            scrim: scrim
        )
    }
}

// MARK: - Luminance / contrast

/// WCAG relative luminance of a color's sRGB components.
func relativeLuminance(_ color: Color) -> Double {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    let uiColor = UIColor(color)
    if !uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
        // Not an RGB-compatible color space — convert via CGColor to sRGB.
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = uiColor.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
            let components = converted.components, components.count >= 3
        else { return 0 }
        r = components[0]
        g = components[1]
        b = components[2]
    }
    func linearize(_ c: CGFloat) -> Double {
        let v = min(max(Double(c), 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
}

/// Black or white over an arbitrary background, whichever wins on WCAG contrast.
/// A naive luminance > 0.5 split picks white on saturated mid-tones (a coral like
/// #FF6B6B sits at ~0.33) even though black reads far better there — the real
/// black/white crossover is at luminance ≈ 0.179, so compare the two contrasts.
func contentColorOn(_ color: Color) -> Color {
    let l = relativeLuminance(color)
    let blackContrast = (l + 0.05) / 0.05   // black L = 0
    let whiteContrast = 1.05 / (l + 0.05)   // white L = 1
    return blackContrast >= whiteContrast ? .black : .white
}

// MARK: - Environment

private struct CGPaletteKey: EnvironmentKey {
    static let defaultValue = CGPalette.light
}

extension EnvironmentValues {
    var cgPalette: CGPalette {
        get { self[CGPaletteKey.self] }
        set { self[CGPaletteKey.self] = newValue }
    }
}

private struct CGThemedModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette: CGPalette = colorScheme == .dark ? .dark : .light
        content
            .environment(\.cgPalette, palette)
            // Mono brand accent for every system control (buttons, alerts, cursors).
            .tint(palette.primary)
    }
}

extension View {
    /// Injects `\.cgPalette` from the current system color scheme. Applied once at RootView.
    func cgThemed() -> some View {
        modifier(CGThemedModifier())
    }
}

// MARK: - Typography (Dynamic Type text styles; M3-role names kept at call sites)

extension Font {
    static let cgDisplayLarge = Font.largeTitle
    static let cgHeadlineLarge = Font.largeTitle
    static let cgHeadlineMedium = Font.title
    static let cgHeadlineSmall = Font.title2
    static let cgTitleLarge = Font.title2
    static let cgTitleMedium = Font.headline
    static let cgTitleSmall = Font.subheadline.weight(.medium)
    static let cgBodyLarge = Font.body
    static let cgBodyMedium = Font.subheadline
    static let cgBodySmall = Font.footnote
    static let cgLabelLarge = Font.subheadline.weight(.medium)
    static let cgLabelMedium = Font.footnote.weight(.medium)
    static let cgLabelSmall = Font.caption.weight(.medium)
}

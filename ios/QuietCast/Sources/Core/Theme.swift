import SwiftUI
import Observation

// Cold Ember token system, ported 1:1 from src/styles/tokens.css (see ios/spec/design-tokens.md).
// Three palettes: dark (default), light (opt-in), and the theme-INVARIANT over-art palette
// used on any surface drawn over artwork (now-playing view, bands, pills on covers).

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct Palette {
    let canvas: Color
    let surface1: Color
    let surface2: Color
    let recess: Color
    let gunmetal: Color
    let stone: Color
    let marble: Color
    let fogOlive: Color
    let fogTeal: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let hairline: Color
    let hairlineSoft: Color
    let ember: Color
    let emberDeep: Color
    let gold: Color
    let steel: Color
    let onEmber: Color
    let glass: Color
    let glassStrong: Color
    let shadow: Color
    let edgeGlint: Color
    /// SwiftUI colorScheme native controls should follow on this palette.
    let colorScheme: ColorScheme

    /// Shadow consumed at a percentage alpha, like `color-mix(in srgb, var(--shadow) N%, transparent)`.
    func shadowMix(_ percent: Double) -> Color { shadow.opacity(percent / 100) }

    static let dark = Palette(
        canvas: Color(hex: 0x0D0E10),
        surface1: Color(hex: 0x15161A),
        surface2: Color(hex: 0x1D1F24),
        recess: Color(hex: 0x08090B),
        gunmetal: Color(hex: 0x55565A),
        stone: Color(hex: 0x8B8478),
        marble: Color(hex: 0xC8C4B9),
        fogOlive: Color(hex: 0x8C9272),
        fogTeal: Color(hex: 0x2C4150),
        ink: Color(hex: 0xD9D5C8),
        ink2: Color(hex: 0x9A9CA0),
        ink3: Color(hex: 0x6E6E66),
        hairline: Color(hex: 0xD9D5C8, alpha: 0.12),
        hairlineSoft: Color(hex: 0xD9D5C8, alpha: 0.06),
        ember: Color(hex: 0xB08A5E),
        emberDeep: Color(hex: 0x6F2B38),
        gold: Color(hex: 0xB08A3A),
        steel: Color(hex: 0x7E8A92),
        onEmber: Color(hex: 0x0D0E10),
        glass: Color(hex: 0x0D0E10, alpha: 0.72),
        glassStrong: Color(hex: 0x141518, alpha: 0.96),
        shadow: Color(hex: 0x000000, alpha: 1),
        edgeGlint: Color(hex: 0xFFFFFF, alpha: 0.04),
        colorScheme: .dark
    )

    static let light = Palette(
        canvas: Color(hex: 0xF3F1EA),
        surface1: Color(hex: 0xEAE7DE),
        surface2: Color(hex: 0xE2DED3),
        recess: Color(hex: 0xD8D4C8),
        gunmetal: Color(hex: 0x6B6C70),
        stone: Color(hex: 0x6B6353),
        marble: Color(hex: 0xC8C4B9),          // unchanged — the paper object keeps its tone
        fogOlive: Color(hex: 0x59663D),
        fogTeal: Color(hex: 0x2C4150),          // unchanged — only ever a low-alpha wash
        ink: Color(hex: 0x26231B),
        ink2: Color(hex: 0x565148),
        ink3: Color(hex: 0x655E50),
        hairline: Color(hex: 0x26231B, alpha: 0.16),
        hairlineSoft: Color(hex: 0x26231B, alpha: 0.08),
        ember: Color(hex: 0x84592E),
        emberDeep: Color(hex: 0x6F2B38),        // unchanged — 8.9:1 on the paper canvas
        gold: Color(hex: 0x8A6F2E),
        steel: Color(hex: 0x56646E),
        onEmber: Color(hex: 0xF7F5EF),
        glass: Color(hex: 0xF2F0E9, alpha: 0.78),
        glassStrong: Color(hex: 0xEEECE4, alpha: 0.97),
        shadow: Color(hex: 0x3D3526, alpha: 0.35),
        edgeGlint: Color(hex: 0xFFFFFF, alpha: 0.55),
        colorScheme: .light
    )

    /// Over-art surfaces stay dark in BOTH themes (tokens.css:56-65, 123-143):
    /// the dark ramp with ink re-pinned to the overart constants, on-ember #0d0e10,
    /// full-black shadows, dark color scheme.
    static let overArt = Palette(
        canvas: Color(hex: 0x08090B),
        surface1: Color(hex: 0x15161A),
        surface2: Color(hex: 0x1D1F24),
        recess: Color(hex: 0x08090B),
        gunmetal: Color(hex: 0x55565A),
        stone: Color(hex: 0x8B8478),
        marble: Color(hex: 0xC8C4B9),
        fogOlive: Color(hex: 0x8C9272),
        fogTeal: Color(hex: 0x2C4150),
        ink: Color(hex: 0xD9D5C8),
        ink2: Color(hex: 0x9A9CA0),
        ink3: Color(hex: 0x6E6E66),
        hairline: Color(hex: 0xD9D5C8, alpha: 0.12),
        hairlineSoft: Color(hex: 0xD9D5C8, alpha: 0.06),
        ember: Color(hex: 0xB08A5E),
        emberDeep: Color(hex: 0x6F2B38),
        gold: Color(hex: 0xB08A3A),
        steel: Color(hex: 0x7E8A92),
        onEmber: Color(hex: 0x0D0E10),
        glass: Color(hex: 0x0D0E10, alpha: 0.72),
        glassStrong: Color(hex: 0x141518, alpha: 0.96),
        shadow: Color(hex: 0x000000, alpha: 1),
        edgeGlint: Color(hex: 0xFFFFFF, alpha: 0.04),
        colorScheme: .dark
    )
}

enum QCTheme: String {
    case dark
    case light

    /// Only the literal value 'light' selects light (Base.astro:55).
    init(pin value: String?) {
        self = value == "light" ? .light : .dark
    }

    var palette: Palette { self == .light ? .light : .dark }
}

/// Theme pin, mirroring Base.astro: UserDefaults key `qc-theme`; the server-saved
/// profile_details.theme is authoritative when present and re-seeds the local value;
/// default is dark. Applied before first frame (read synchronously at init).
@Observable
final class ThemeStore {
    private static let key = "qc-theme"

    var theme: QCTheme

    init() {
        theme = QCTheme(pin: UserDefaults.standard.string(forKey: Self.key))
    }

    var palette: Palette { theme.palette }

    /// Local choice (Settings radio) — persists and applies immediately.
    func set(_ theme: QCTheme) {
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
    }

    /// Server preference wins and re-seeds local storage (Base.astro:64-67).
    func adopt(serverTheme: String?) {
        guard serverTheme == "light" || serverTheme == "dark" else { return }
        set(QCTheme(pin: serverTheme))
    }
}

// MARK: - Typography

/// Direction A typeface stack: Cormorant Garamond (display caps), Spectral (body serif),
/// IBM Plex Mono (numbers/labels). Web ships weights CG 300/400/i300, Spectral 300/400/i300,
/// Plex Mono 400/500; body text is Spectral 300, line-height 1.65.
enum QCFont {
    static func display(_ size: CGFloat) -> Font { .custom("CormorantGaramond-Light", size: size) }
    static func displayRegular(_ size: CGFloat) -> Font { .custom("CormorantGaramond-Regular", size: size) }
    static func displayItalic(_ size: CGFloat) -> Font { .custom("CormorantGaramond-LightItalic", size: size) }
    static func body(_ size: CGFloat) -> Font { .custom("Spectral-Light", size: size) }
    static func bodyRegular(_ size: CGFloat) -> Font { .custom("Spectral-Regular", size: size) }
    static func bodyItalic(_ size: CGFloat) -> Font { .custom("Spectral-LightItalic", size: size) }
    static func bodyMedium(_ size: CGFloat) -> Font { .custom("Spectral-Medium", size: size) }
    static func bodySemiBold(_ size: CGFloat) -> Font { .custom("Spectral-SemiBold", size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom("IBMPlexMono-Regular", size: size) }
    static func monoMedium(_ size: CGFloat) -> Font { .custom("IBMPlexMono-Medium", size: size) }
}

// MARK: - Motion

/// The only curve: cubic-bezier(0.2, 0.7, 0.2, 1); 180ms interactive, 320ms page/player.
enum QCMotion {
    static let fast = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18)
    static let page = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.32)
}

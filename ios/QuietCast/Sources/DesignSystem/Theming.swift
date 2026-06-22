import SwiftUI

// Palette delivered through the environment so any view resolves colors through the token table
// (design-tokens.md §9 rule 1). Over-art surfaces swap in Palette.overArt + force .dark.

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.dark }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Apply the active theme: palette in the environment, native color scheme, ink as default tint.
    func qcThemed(_ theme: QCTheme) -> some View {
        let p = theme.palette
        return self
            .environment(\.palette, p)
            .environment(\.colorScheme, p.colorScheme)
            .tint(p.ember)
            .foregroundStyle(p.ink)
    }

    /// Force the theme-invariant over-art palette (now-playing view, bands, pills on artwork).
    func qcOverArt() -> some View {
        self
            .environment(\.palette, .overArt)
            .environment(\.colorScheme, .dark)
            .tint(Palette.overArt.ember)
            .foregroundStyle(Palette.overArt.ink)
    }
}

// MARK: - Atmosphere: fog field + film grain (design-tokens.md §3)

/// Fixed fog washes over the canvas: olive top-right, teal top-left, teal rising from the bottom.
struct FogBackground: View {
    @Environment(\.palette) private var p
    var body: some View {
        ZStack {
            p.canvas
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    RadialGradient(colors: [p.fogOlive.opacity(0.16), .clear],
                                   center: UnitPoint(x: 0.7, y: -0.1), startRadius: 0, endRadius: max(w, h) * 0.9)
                    RadialGradient(colors: [p.fogTeal.opacity(0.22), .clear],
                                   center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: max(w, h) * 0.8)
                    RadialGradient(colors: [p.fogTeal.opacity(0.12), .clear],
                                   center: UnitPoint(x: 0.5, y: 1.2), startRadius: 0, endRadius: max(w, h) * 1.2)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Universal film/xerox grain above all content. Dark: overlay/0.05; light: multiply/0.04.
struct GrainOverlay: View {
    @Environment(\.palette) private var p
    var body: some View {
        Image("Grain")
            .resizable(resizingMode: .tile)
            .opacity(p.colorScheme == .dark ? 0.05 : 0.04)
            .blendMode(p.colorScheme == .dark ? .overlay : .multiply)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

/// Standard screen chrome: fog background + grain overlay on top of arbitrary content.
struct ThemedScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            FogBackground()
            content
            GrainOverlay()
        }
    }
}

// MARK: - Typography helpers

extension View {
    /// Uppercase tracked caps; re-centered by padding-left == tracking (global.css:39-42 pattern).
    func trackedCaps(_ tracking: CGFloat) -> some View {
        self.tracking(tracking).padding(.leading, tracking)
    }
}

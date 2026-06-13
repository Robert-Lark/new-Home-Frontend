import SwiftUI

// Recurring Cold Ember component shapes (design-tokens.md §8). Capsules 999px; panels 6-8px;
// cards and recesses square-edged. One warm accent per view; oxblood for active/error.

// MARK: - Labels

/// The universal section/meta label: IBM Plex Mono, uppercase, tracking 0.34em-ish, 10px, ink3.
struct Eyebrow: View {
    @Environment(\.palette) private var p
    let text: String
    var color: Color?
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased())
            .font(QCFont.mono(10))
            .trackedCaps(3.0)
            .foregroundStyle(color ?? p.ink3)
    }
}

/// Cold kind chip (steel, hairline border, capsule) — used on rotation tiles and picker rows.
struct Chip: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(QCFont.mono(8))
            .tracking(1.6)
            .foregroundStyle(p.steel)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .overlay(Capsule().stroke(p.hairline, lineWidth: 1))
    }
}

/// Ember run of eyebrow text used for non-published status notes ("removed by the curator").
struct StatusBadge: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(QCFont.mono(9)).tracking(1.6)
            .foregroundStyle(p.ember)
    }
}

// MARK: - Buttons

/// Ember submit pill: ember fill, on-ember text, mono uppercase, capsule.
struct SubmitPillStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var disabled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QCFont.mono(11)).tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(p.onEmber)
            .padding(.vertical, 14).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(p.ember))
            .opacity(disabled ? 0.6 : (configuration.isPressed ? 0.85 : 1))
            .offset(y: configuration.isPressed ? 0 : 0)
    }
}

/// Ghost pill: transparent, hairline border, ink-2 text.
struct GhostPillStyle: ButtonStyle {
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QCFont.mono(11)).tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(p.ink2)
            .padding(.vertical, 14).padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Capsule().stroke(p.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Cover art

/// Remote cover art, muted at rest (grayscale 0.55, slightly dimmed, contrast lift) — index.astro:126-138.
/// `relaxed` (done/visited, or detail recess) eases the desaturation.
struct CoverImage: View {
    @Environment(\.palette) private var p
    let urlString: String?
    var relaxed = false

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .grayscale(relaxed ? 0.3 : 0.55)
                            .brightness(relaxed ? -0.04 : -0.08)
                            .contrast(1.05)
                    case .empty:
                        ZStack { p.recess; ProgressView().tint(p.ink3) }
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        Image("FallbackCover").resizable().scaledToFill()
            .grayscale(0.5).brightness(-0.06)
    }
}

/// Carved recess panel: recess fill, hairline border, square edges, inset shadow feel.
struct Recess<Content: View>: View {
    @Environment(\.palette) private var p
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(p.recess)
            .overlay(Rectangle().stroke(p.hairline, lineWidth: 1))
            .shadow(color: p.shadowMix(60), radius: 30, y: 10)
    }
}

/// Surface-1 panel with hairline border (cards, settings groups). Slightly rounded (6-8px).
struct Panel<Content: View>: View {
    @Environment(\.palette) private var p
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.surface1))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.hairline, lineWidth: 1))
    }
}

// MARK: - Listen-state dot (in-progress / done) — index.astro:281-303

struct ListenDot: View {
    @Environment(\.palette) private var p
    let state: ListenState
    var body: some View {
        switch state {
        case .inProgress:
            Circle().fill(p.ember).frame(width: 7, height: 7)
                .overlay(Circle().stroke(p.ember.opacity(0.22), lineWidth: 3).scaleEffect(1.8))
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(p.ember)
        case .unplayed:
            EmptyView()
        }
    }
}

// MARK: - Heading helpers

/// Display H1 in Cormorant Garamond light caps, tracked (page/show titles).
struct DisplayTitle: View {
    @Environment(\.palette) private var p
    let text: String
    var size: CGFloat = 30
    var tracking: CGFloat = 5
    var body: some View {
        Text(text)
            .font(QCFont.display(size))
            .tracking(tracking)
            .foregroundStyle(p.ink)
    }
}

// MARK: - Inline error / notice

struct Notice: View {
    @Environment(\.palette) private var p
    let text: String
    var isError = false
    var body: some View {
        Text(text)
            .font(QCFont.body(14))
            .foregroundStyle(isError ? p.emberDeep : p.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

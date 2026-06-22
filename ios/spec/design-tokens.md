# Quiet Cast — Cold Ember design contract (iOS port)

Source of truth: `src/styles/tokens.css` (195 lines). Component idioms cited from
`src/styles/global.css`, `src/layouts/Base.astro`, and page/island styles. All values
below are quoted verbatim from those files; nothing is invented. A Swift engineer should
be able to build the visual system from this file alone.

Theme model (tokens.css:6–12): **dark is the house default everywhere**; light is opt-in
via `html[data-theme='light']`. Every color the site renders resolves through tokens —
"pages and islands must not carry raw hex/rgba (over-art surfaces use the theme-invariant
tokens below instead)" (tokens.css:9–11). The iOS app should mirror this: a single token
table, two theme variants, plus a third theme-invariant "over-art" palette.

---

## 1. Complete token table — dark (`:root`) vs light (`[data-theme='light']`)

Tool-verified counts: 39 custom properties in `:root` (tokens.css:13–81), 20 overridden
in the light block (tokens.css:88–121). "—" in the Light column means the dark value is
**deliberately unchanged** in light mode (the file's own comments give the reason).

Also set per theme (not a custom property): `color-scheme: dark` (tokens.css:14) /
`color-scheme: light` (tokens.css:89) — on iOS this maps to forcing `.dark` / `.light`
`colorScheme` so native controls (sheets, pickers, keyboards) follow the theme.

| Token | Dark (default) | Light (`[data-theme='light']`) | Role (from tokens.css comments) |
|---|---|---|---|
| `--canvas` | `#0d0e10` | `#f3f1ea` | page background (tokens.css:17, 91) |
| `--surface-1` | `#15161a` | `#eae7de` | raised surface / inputs (18, 92) |
| `--surface-2` | `#1d1f24` | `#e2ded3` | higher surface (19, 93) |
| `--recess` | `#08090b` | `#d8d4c8` | "carved void" dark / "pressed paper, not carved void" light (20, 94) |
| `--gunmetal` | `#55565a` | `#6b6c70` | granite ramp (23, 96) |
| `--stone` | `#8b8478` | `#6b6353` | granite ramp (24, 97) |
| `--marble` | `#c8c4b9` | — "unchanged — the paper object keeps its tone" (98) | granite ramp (25) |
| `--fog-olive` | `#8c9272` | `#59663d` | atmosphere (28, 100) |
| `--fog-teal` | `#2c4150` | — "unchanged — only ever a low-alpha wash" (101) | atmosphere (29) |
| `--ink` | `#d9d5c8` | `#26231b` | primary text — "bone, never pure white" (31–32, 103) |
| `--ink-2` | `#9a9ca0` | `#565148` | secondary text (33, 104) |
| `--ink-3` | `#6e6e66` | `#655e50` | tertiary text / labels (34, 105) |
| `--hairline` | `rgba(217, 213, 200, 0.12)` | `rgba(38, 35, 27, 0.16)` | borders (35, 106) |
| `--hairline-soft` | `rgba(217, 213, 200, 0.06)` | `rgba(38, 35, 27, 0.08)` | row separators (36, 107) |
| `--ember` | `#b08a5e` | `#84592e` | THE one warm accent (39, 109) |
| `--ember-deep` | `#6f2b38` | — "unchanged — 8.9:1 on the paper canvas" (110) | "oxblood — playing/active" (40) |
| `--gold` | `#b08a3a` | `#8a6f2e` | "Giger dull gold alt" (41, 111) |
| `--steel` | `#7e8a92` | `#56646e` | "cold secondary" (42, 112) |
| `--on-ember` | `#0d0e10` | `#f7f5ef` | "ink/icon sitting ON the ember accent (play buttons, submit pills)" (44–45, 114) |
| `--glass` | `rgba(13, 14, 16, 0.72)` | `rgba(242, 240, 233, 0.78)` | "player dock" chrome (48, 116) |
| `--glass-strong` | `rgba(20, 21, 24, 0.96)` | `rgba(238, 236, 228, 0.97)` | "popover menus" (49, 117) |
| `--shadow` | `rgba(0, 0, 0, 1)` | `rgba(61, 53, 38, 0.35)` | shadow base, always consumed at an alpha via `color-mix(in srgb, var(--shadow) N%, transparent)` (51–53, 119) |
| `--edge-glint` | `rgba(255, 255, 255, 0.04)` | `rgba(255, 255, 255, 0.55)` | "inset top highlight on glass" (54, 120) |
| `--overart` | `#08090b` | — invariant | over-art scrim base (60) — see §2 |
| `--overart-ink` | `#d9d5c8` | — invariant | (61) |
| `--overart-ink-2` | `#9a9ca0` | — invariant | (62) |
| `--overart-ink-3` | `#6e6e66` | — invariant | (63) |
| `--overart-hairline` | `rgba(217, 213, 200, 0.12)` | — invariant | (64) |
| `--overart-hairline-soft` | `rgba(217, 213, 200, 0.06)` | — invariant | (65) |
| `--paper-ink` | `#211d15` | — invariant | interviews bone-paper document, "a printed object, same in both themes" (67–69) |
| `--paper-ink-strong` | `#14110c` | — invariant | (70) |
| `--paper-ink-body` | `#2a2419` | — invariant | (71) |
| `--paper-ink-soft` | `#5c5446` | — invariant | (72) |
| `--paper-line` | `#b3ae9f` | — invariant | (73) |
| `--paper-rule` | `#bdb8a8` | — invariant | (74) |
| `--paper-glint` | `rgba(255, 255, 255, 0.35)` | — invariant | (75) — paper's drop shadow still flips through `--shadow` (68) |
| `--ease-out` | `cubic-bezier(0.2, 0.7, 0.2, 1)` | — | motion curve (78) |
| `--dur-fast` | `180ms` | — | "interactive feedback" (79) |
| `--dur-page` | `320ms` | — | "page view-transitions / player expand" (80) |

Verbatim source blocks for diffing:

```css
/* tokens.css:13–81 (dark) */
:root {
  color-scheme: dark;
  --canvas: #0d0e10;
  --surface-1: #15161a;
  --surface-2: #1d1f24;
  --recess: #08090b;
  --gunmetal: #55565a;
  --stone: #8b8478;
  --marble: #c8c4b9;
  --fog-olive: #8c9272;
  --fog-teal: #2c4150;
  --ink: #d9d5c8;
  --ink-2: #9a9ca0;
  --ink-3: #6e6e66;
  --hairline: rgba(217, 213, 200, 0.12);
  --hairline-soft: rgba(217, 213, 200, 0.06);
  --ember: #b08a5e;
  --ember-deep: #6f2b38;
  --gold: #b08a3a;
  --steel: #7e8a92;
  --on-ember: #0d0e10;
  --glass: rgba(13, 14, 16, 0.72);
  --glass-strong: rgba(20, 21, 24, 0.96);
  --shadow: rgba(0, 0, 0, 1);
  --edge-glint: rgba(255, 255, 255, 0.04);
  --overart: #08090b;
  --overart-ink: #d9d5c8;
  --overart-ink-2: #9a9ca0;
  --overart-ink-3: #6e6e66;
  --overart-hairline: rgba(217, 213, 200, 0.12);
  --overart-hairline-soft: rgba(217, 213, 200, 0.06);
  --paper-ink: #211d15;
  --paper-ink-strong: #14110c;
  --paper-ink-body: #2a2419;
  --paper-ink-soft: #5c5446;
  --paper-line: #b3ae9f;
  --paper-rule: #bdb8a8;
  --paper-glint: rgba(255, 255, 255, 0.35);
  --ease-out: cubic-bezier(0.2, 0.7, 0.2, 1);
  --dur-fast: 180ms;
  --dur-page: 320ms;
}
```

```css
/* tokens.css:88–121 (light overrides — everything not listed keeps the dark value) */
[data-theme='light'] {
  color-scheme: light;
  --canvas: #f3f1ea;
  --surface-1: #eae7de;
  --surface-2: #e2ded3;
  --recess: #d8d4c8;
  --gunmetal: #6b6c70;
  --stone: #6b6353;
  --fog-olive: #59663d;
  --ink: #26231b;
  --ink-2: #565148;
  --ink-3: #655e50;
  --hairline: rgba(38, 35, 27, 0.16);
  --hairline-soft: rgba(38, 35, 27, 0.08);
  --ember: #84592e;
  --gold: #8a6f2e;
  --steel: #56646e;
  --on-ember: #f7f5ef;
  --glass: rgba(242, 240, 233, 0.78);
  --glass-strong: rgba(238, 236, 228, 0.97);
  --shadow: rgba(61, 53, 38, 0.35);
  --edge-glint: rgba(255, 255, 255, 0.55);
}
```

---

## 2. Over-art invariance — surfaces that stay dark in BOTH themes

The defining theming rule (tokens.css:56–59): "over-art constants — DELIBERATELY
theme-invariant. Scrims, pills, and washes that sit on artwork (hero hover bands, tile
controls, the now-playing view) stay dark in both themes; the art doesn't change.
Consumed via color-mix alphas at the use site."

In light mode the web app re-pins the *consumed* tokens on six surfaces rather than
overriding properties one by one (tokens.css:123–143):

```css
[data-theme='light'] .now-playing,
[data-theme='light'] .card .band,
[data-theme='light'] .card-actions,
[data-theme='light'] .p-tile-x,
[data-theme='light'] .p-tile-grab,
[data-theme='light'] .p-tile-mv {
  color-scheme: dark;
  --ink: var(--overart-ink);
  --ink-2: var(--overart-ink-2);
  --ink-3: var(--overart-ink-3);
  --hairline: var(--overart-hairline);
  --hairline-soft: var(--overart-hairline-soft);
  --on-ember: #0d0e10;
  --shadow: rgba(0, 0, 0, 1);
  --fog-olive: #8c9272;
  --fog-teal: #2c4150;
  --recess: #08090b;
}
```

The six surfaces and where they live:

| Surface | What it is | Where |
|---|---|---|
| `.now-playing` | full-screen expanded player over a blurred cover backdrop | global.css:183–188; backdrop scrim `color-mix(in srgb, var(--overart) 55%, transparent)` + fog washes, global.css:198–206; queue panel `color-mix(in srgb, var(--overart) 40%, transparent)` + `backdrop-filter: blur(10px)`, global.css:350–356 |
| `.card .band` | hero-grid hover title band over cover art | index.astro:139–149: `background: linear-gradient(to top, color-mix(in srgb, var(--overart) 86%, transparent), transparent);` |
| `.card-actions` | favorite/add-to-playlist pill cluster over cover art | index.astro:189–214: buttons are 30×30 circles, `background: color-mix(in srgb, var(--overart) 66%, transparent); backdrop-filter: blur(8px);` |
| `.p-tile-x`, `.p-tile-grab`, `.p-tile-mv` | rotation-grid tile controls (unpin ×, drag handle, move arrows) over tile art | ProfilePage.astro:1148–1163: 24×24 circles, `background: color-mix(in srgb, var(--overart) 72%, transparent);` (markup in RotationGrid.tsx:194, 213, 232, 245) |

**iOS contract:** model these as a third, theme-independent palette
(`overArt = #08090b` base + bone ink ramp). Any view drawn ON artwork — the now-playing
screen, hover/long-press title bands, action pills floating on covers, tile controls —
uses the over-art palette and dark color scheme regardless of the active app theme.
`on-ember` is `#0d0e10` there even in light mode (tokens.css:138), and shadows stay
full-black (tokens.css:139).

---

## 3. Grain + fog atmosphere, per theme

**Film grain** — a fixed full-screen noise overlay above all content
(tokens.css:166–183): "universal film/xerox grain … Fixed overlay so it reads as a
property of the surface, not the content. On paper the overlay blend would brighten
instead of texture, so light mode multiplies it down like print grain."

```css
body::after {
  content: '';
  position: fixed;
  inset: 0;
  z-index: 9999;
  pointer-events: none;
  opacity: 0.05;
  mix-blend-mode: overlay;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
}
[data-theme='light'] body::after {
  mix-blend-mode: multiply;
  opacity: 0.04;
}
```

iOS recipe: a 160×160pt tiling fractal-noise texture (`feTurbulence type='fractalNoise'
baseFrequency='0.9' numOctaves='2'` — pre-render to a PNG asset), composited app-wide
above content, non-interactive. Dark: blend mode **overlay** at **0.05** opacity. Light:
blend mode **multiply** at **0.04** opacity.

**Fog field** — fixed *behind* content, "gradients drift from canvas toward olive/teal"
(global.css:14–25):

```css
.fog {
  position: fixed;
  inset: 0;
  z-index: -1;
  background:
    radial-gradient(120% 90% at 70% -10%, color-mix(in srgb, var(--fog-olive) 16%, transparent), transparent 55%),
    radial-gradient(100% 80% at 15% 5%, color-mix(in srgb, var(--fog-teal) 22%, transparent), transparent 50%),
    radial-gradient(140% 120% at 50% 120%, color-mix(in srgb, var(--fog-teal) 12%, transparent), transparent 60%),
    var(--canvas);
}
```

Three radial washes over `--canvas`: olive at 16% alpha top-right, teal at 22% top-left,
teal at 12% rising from the bottom. Both `--fog-olive` and `--fog-teal` participate in
theming (olive flips to `#59663d` in light; teal stays `#2c4150` because it is "only ever
a low-alpha wash", tokens.css:101). The now-playing backdrop reuses the same washes at
14%/30% over the cover scrim (global.css:198–206).

---

## 4. Typography

Loaded from **Google Fonts** in Base.astro:83–88 ("Direction A typeface stack: Cormorant
Garamond (display caps), Spectral (body serif), IBM Plex Mono (numbers/labels)"):

```html
<link
  href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,300&family=Spectral:ital,wght@0,300;0,400;1,300&family=IBM+Plex+Mono:wght@400;500&display=swap"
  rel="stylesheet"
/>
```

Exact weights shipped — bundle ONLY these in the iOS app (all three are OFL-licensed,
downloadable from Google Fonts):

| Family | Weights | Role | Evidence |
|---|---|---|---|
| **Cormorant Garamond** | 300, 400, italic 300 | Display caps: brand wordmark (300, uppercase, `letter-spacing: 0.62em`, global.css:35–44), page/show H1s (300, uppercase, `0.18em`, mixes/[id].astro:139–148), now-playing title (300, uppercase, `0.4em`, 34px, global.css:263–271), card band titles (`0.24em`, 13px, index.astro:242–248), success/sent headings (`0.28em`, 18px, global.css:502–509) |
| **Spectral** | 300, 400, italic 300 | Body serif. `body { font-family: 'Spectral', Georgia, serif; font-weight: 300; line-height: 1.65; }` (global.css:4–8). Form inputs at 16px (global.css:447–456); hero sub in italic (index.astro:100–106); interview body 17px/1.78 on paper |
| **IBM Plex Mono** | 400, 500 | Numbers, labels, eyebrows, nav, buttons: `.eyebrow` (uppercase, `0.34em`, 10px, `--ink-3`, tokens.css:186–192), `.mono` utility (tokens.css:193–195), nav links (10px, `0.28em`, global.css:49–57), dock timestamps (10px, `0.1em`, global.css:173–178), submit pills (11px, `0.22em`, global.css:467–480) |

Display-caps pattern note: uppercase tracked headings add `padding-left` equal to the
letter-spacing (e.g. brand `letter-spacing: 0.62em; padding-left: 0.62em`,
global.css:39–42; `.np-t` `0.4em`/`0.4em`, global.css:267–270) to re-center the text —
replicate when tracking uppercase strings in SwiftUI.

---

## 5. The one-warm-accent law

tokens.css:4: "The one cross-validated law: exactly ONE warm/saturated accent per view."

- `--ember` (`#b08a5e` dark / `#84592e` light, tokens.css:39/109) is *the* warm accent —
  "the one rationed warm accent — 'cold but warm sunrise'" (tokens.css:38). Verified
  uses: dock play button (global.css:157–168), now-playing play/pause 64px circle
  (global.css:339–349), card hover play (index.astro:158–176), submit pills
  (global.css:467–480, 621–635), input focus border (global.css:460–463), active nav
  item (global.css:61–63), favorited heart fill (index.astro:232–240), card band credit
  line (index.astro:249–255), now-playing subtitle (global.css:272–279), range/scrubber
  thumbs (global.css:289–303), radio `accent-color` (global.css:674–676), upload
  progress fill at 0.55 opacity (global.css:694–700), in-progress listen dot with
  `box-shadow: 0 0 0 3px color-mix(in srgb, var(--ember) 22%, transparent)`
  (index.astro:281–285), visibility badges (posts/[id].astro:73–76).
- `--ember-deep` (`#6f2b38` oxblood, both themes) is "playing/active" (tokens.css:40)
  and error text (`.login-error` global.css:488–494, `.ugc-error` global.css:648–654,
  `.p-grid-msg` ProfilePage.astro), and the selected interview chip underline
  (interviews.astro:430 `border-bottom-color: var(--ember-deep)`).
- `--on-ember` is the ink that sits ON ember fills. It **flips** with theme
  (`#0d0e10` dark → `#f7f5ef` light, tokens.css:45/114) — EXCEPT on over-art surfaces,
  where it is re-pinned to `#0d0e10` (tokens.css:138).
- Light-mode rationale (tokens.css:83–87): "the ember darkened to stone-stain ochre so
  the one-warm-accent law keeps 4.5:1 text / 3:1 UI contrast … ember-deep oxblood
  already reads on paper … and is kept."
- `--gold` and `--steel` are alternates (tokens.css:41–42); steel is the *cold*
  secondary used on chips (ProfilePage.astro:1143). Never show two warm accents in one
  view.

**iOS contract:** any given screen renders ember on exactly one interactive family
(usually the play action); everything else stays in the bone/granite ramp. Errors and
"active/playing" states use oxblood, which is constant across themes.

---

## 6. Theme pin mechanism (what iOS must reproduce behaviorally)

Web implementation (Base.astro:46–79): an inline, pre-paint script. Resolution order:

1. `data-server-theme` attribute — the signed-in user's saved preference from
   `profile_details`, passed as the `theme` prop (`'dark' | 'light' | null`,
   Base.astro:12–17). When present it is **authoritative** and re-seeds local storage:
   `localStorage.setItem('qc-theme', server)` (Base.astro:64–67), "so a fresh device
   picks up the saved preference on first sign-in" (Base.astro:14–16).
2. Otherwise `localStorage.getItem('qc-theme')` (Base.astro:68).
3. Storage blocked / nothing stored → `'dark'` (Base.astro:70; `apply` coerces anything
   that isn't `'light'` to `'dark'`, Base.astro:55).

It also syncs `<meta name="color-scheme">` so native UI follows (Base.astro:56–58).

**iOS contract:** persist the choice under an equivalent key (e.g. `qc-theme` in
`UserDefaults`); on sign-in, the Supabase profile's saved theme overwrites the local
value; default is dark; only the literal value `light` selects light. Apply before first
frame (no theme flash). Set the SwiftUI `colorScheme` to match — except over-art views,
which force `.dark` (§2).

---

## 7. Motion

- `--ease-out: cubic-bezier(0.2, 0.7, 0.2, 1)` (tokens.css:78) — the only curve.
- `--dur-fast: 180ms` for "interactive feedback" (tokens.css:79); `--dur-page: 320ms`
  for "page view-transitions / player expand" (tokens.css:80). Page transitions are a
  cross-fade at `--dur-page`, disabled under reduced motion (global.css:744–750) — honor
  `accessibilityReduceMotion` on iOS.
- Slow image reveals on cards: `filter 0.6s` / `transform 0.9s` with the same curve
  (index.astro:131–133).

---

## 8. Recurring component shapes (native echoes)

Neutral order, by file.

- **Eyebrow label** (tokens.css:186–192): IBM Plex Mono, uppercase, `letter-spacing:
  0.34em`, `font-size: 10px`, `color: var(--ink-3)`. The app's universal section/meta
  label.
- **Player dock pill** (global.css:96–114): fixed bottom-floating capsule
  (`border-radius: 999px`), `width: min(640px, calc(100vw - 32px))`, `background:
  var(--glass)` + `backdrop-filter: blur(18px) saturate(120%)`, `border: 1px solid
  var(--hairline)`, shadow `0 1px 0 var(--edge-glint) inset, 0 24px 60px -20px
  color-mix(in srgb, var(--shadow) 80%, transparent)`. Circular 42px cover and 42px
  ember play button (global.css:115–168); 2px scrub line in hairline with `--ink-2`
  fill (global.css:141–156). iOS: ultra-thin-material capsule tinted to `--glass`, with
  the inset top glint as a 1px white overlay stroke.
- **Carved recess** (np-recess global.css:244–251; `.recess` mixes/[id].astro:120–127):
  artwork sits in a panel of `var(--recess)` with `border: 1px solid var(--hairline)`
  and the double shadow `inset 0 2px 30px color-mix(in srgb, var(--shadow) 90%,
  transparent), 0 40px 100px -30px color-mix(in srgb, var(--shadow) 90%, transparent)`.
  Padding 18px (now-playing) / 16px (mix page). Cover imagery is desaturated:
  `grayscale(0.3–0.35) contrast(1.05)` (global.css:252–258, mixes/[id].astro:128–134).
- **Cards** (index.astro:114–155): square (`aspect-ratio: 1`) tiles on `--surface-1`,
  2px gutters (index.astro:108–113). Images muted at rest — `grayscale(0.55)
  brightness(0.82) contrast(1.05)` — and revealed on hover (`grayscale(0.1)
  brightness(0.95)`, `scale(1.03)`). Band + actions are over-art surfaces (§2).
  Corner index mark: mono 9px `0.18em` `--ink-2` at 0.7 opacity (index.astro:256–265).
- **Submit pills** (`.login-submit` global.css:467–480, `.ugc-submit`
  global.css:621–647): `border-radius: 999px`, ember fill, `--on-ember` text, IBM Plex
  Mono uppercase 11px `0.22em`, padding `14px 22px`/`14px 26px`; hover
  `translateY(-1px)`; disabled at 0.6 opacity; `.ghost` variant = transparent with
  hairline border and `--ink-2` text (global.css:643–647).
- **Inputs** (global.css:447–463, 547–578): `background: var(--surface-1)`, `border:
  1px solid var(--hairline)`, `border-radius: 6px`, Spectral 16px `--ink`, placeholder
  `--ink-3`, focus border `--ember`. Sent/success panels: radius 8px, surface-1,
  hairline border, ember Cormorant heading (global.css:495–514, 711–733).
- **`.ugc-vis` radios** (global.css:655–680): borderless fieldset, vertical 10px gap;
  label rows 14px `--ink-2` with the emphasized `<b>` at `font-weight: 400` in `--ink`;
  `accent-color: var(--ember)` on the radio itself. ("same anatomy as the settings
  radios", global.css:655.) iOS: ember-tinted selection control, two-tone label text.
- **Chips** (`.p-chip` ProfilePage.astro:1138–1147): `font-size: 8px`,
  `letter-spacing: 0.2em`, uppercase, `color: var(--steel)` (cold, not warm), `border:
  1px solid var(--hairline)`, `border-radius: 999px`, `padding: 2px 8px`. Used for kind
  tags on rotation tiles (RotationGrid.tsx:188) and picker rows (ProfilePage.astro:295).
- **Tile-control pills** (ProfilePage.astro:1148–1196): 24×24 circles, hairline border,
  `color-mix(in srgb, var(--overart) 72%, transparent)` fill, `--ink-2` glyph; hover →
  ember border + ember glyph; disabled 0.35 opacity. Over-art surfaces (§2).
- **Badges** (posts/[id].astro:73–76; same rule lists/[id].astro:97, photos/[id].astro:88,
  mixes/[id].astro:135–138): a span inside the eyebrow line, `margin-left: 12px; color:
  var(--ember);` — used for non-published status ("pending/removed — only you can see
  this", posts/[id].astro:50–53) and the mix-page status mark. Not a boxed chip: an
  ember-colored run of eyebrow text.
- **Interview index chips** (interviews.astro:411–432, mobile): horizontal scroll-snap
  strip; selected state = `border-bottom: 2px solid var(--ember-deep)` — oxblood, not
  ember, marking "active".
- **Up-next marker** (global.css:411–423): `content: 'UP NEXT'` mono 8px `0.24em` in
  `--ember` floated over the first queue row.

---

## 9. Hard rules for the iOS implementation

1. No raw hex in views — every color resolves through the token table (tokens.css:8–11).
2. Dark is default; light is an explicit stored choice; server preference wins and
   re-seeds local storage (§6).
3. Over-art surfaces never theme: dark scrim base `#08090b`, bone ink, `on-ember
   #0d0e10`, full-black shadows, dark color scheme (§2).
4. One warm accent per view; oxblood `#6f2b38` for active/error is theme-constant (§5).
5. All shadows derive from `--shadow` at a percentage alpha — flipping that one value
   rebalances every shadow per theme (tokens.css:51–53).
6. Text is bone (`#d9d5c8`), never pure white (tokens.css:31).
7. Grain overlay always on top: overlay/0.05 dark, multiply/0.04 light (§3).
8. Capsules are `border-radius: 999px`; panels 6–8px; cards and recesses square-edged.

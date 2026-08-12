# Planer — Design System

Single source of truth for the visual language. Every token in `index.html`'s
`:root` block comes from here; nothing in the app should carry a raw hex value
or a magic number that isn't traceable to this file.

Established via the `paint` pipeline (brainstorm → thesis → system → implement
→ audit). Both theses were reviewed against a live specimen and approved.

---

## Theses

**Visual** — Warm light paper with near-black ink, hairline borders instead of
shadows, generous whitespace, soft 8–12px corners, and one low-saturation
accent that appears only where it does work, never as decoration.

**Interaction** — Short, quiet motion (120–180ms, sharp ease-out), hover as a
background tint only (no scale, no lift), no scroll animation anywhere, and no
element whose position depends on an animation completing.

---

## Direction

- **Reference point:** Things 3 — the app should feel like a notebook, not a dashboard.
- **Light is primary.** Dark is a *separate deliberate design*, not an inversion
  of the paper: inverted warm cream turns muddy brown.
- **Peyda is the only typeface.** It is the one face carrying Persian + Latin +
  Persian digits, embedded as base64 in the single file. Type contrast therefore
  comes from weight, size and tracking within one superfamily — there is no
  display face, and adding one is not an option.
- **Accent: ink blue.** Chosen over terracotta partly because warm cream + terracotta
  is one of the most over-produced pairings in this style.

---

## Color

Contrast ratios below were measured, not estimated. Text tokens meet WCAG AA
(≥ 4.5:1) against the surfaces they actually sit on.

### Light — paper

| Token | Value | Notes |
|---|---|---|
| `--bg` | `#F7F4EF` | warm paper, the page ground |
| `--bg-elev` / `--surface` | `#FFFFFF` | cards |
| `--surface-2` | `#F2EEE7` | inset rows, chips |
| `--surface-3` | `#EAE5DB` | pressed / track |
| `--text` | `#2B2724` | ink — 13.4:1 on paper |
| `--text-2` | `#6B635A` | 5.9:1 |
| `--text-3` | `#756C63` | 4.7:1 — **do not lighten**, `#9A9088` failed at 2.85 |
| `--border` | `#E4DED3` | hairline; the main separator |
| `--border-strong` | `#D5CCBD` | inputs, checkbox outlines |
| `--brand` | `#33538A` | ink blue — 7.7:1 on white |
| `--brand-soft` | `#E7EDF6` | accent chip / active nav ground |

### Dark — deliberate, not inverted

| Token | Value | Notes |
|---|---|---|
| `--bg` | `#191714` | warm-neutral, not black |
| `--bg-elev` / `--surface` | `#211F1B` | |
| `--surface-2` | `#2A2722` | |
| `--surface-3` | `#343029` | |
| `--text` | `#ECE7DF` | |
| `--text-2` | `#A69F94` | |
| `--text-3` | `#968D82` | 5.0:1 — `#756E64` failed at 3.27 |
| `--border` | `#35312B` | |
| `--border-strong` | `#453F37` | |
| `--brand` | `#7FA3DC` | 6.4:1 on surface |
| `--brand-soft` | `#20293A` | |

### Semantic

Separate from the accent. Muted on purpose — a calm app has no neon.

| | light | dark |
|---|---|---|
| `--green` | `#4C7A4E` | `#7FA97F` |
| `--orange` | `#8A6519` | `#C9A54E` |
| `--red` | `#A8443A` | `#D2786D` |
| `--blue` | `#4A6FA5` | `#7FA3DC` |
| `--pink` | `#9C5A72` | `#C58FA1` |
| `--teal` | `#3F7A75` | `#6FA9A3` |

`--orange` was `#9A7220` and failed AA at 3.99 on paper.

---

## Typography

Peyda, three embedded weights (100–500, 501–650, 651–900).

- **Headings use 600 (SemiBold), not Bold.** In a notebook the heading shows the
  way; it does not shout.
- **Body line-height 1.6** — paper wants air.
- Persian never takes negative letter-spacing (it breaks joining).
- Digits that line up in columns use `font-variant-numeric: tabular-nums`.

Scale is `--fs-{step}-base × --fs-scale`, where `--fs-scale` is written by
`Theme.apply()` from `Prefs.fontSize` (85–130%). Desktop bases:

| Token | px | Role |
|---|---|---|
| `--fs-xs` | 12 | labels, chips |
| `--fs-sm` | 13 | meta, secondary |
| `--fs-md` | 15 | body — the default |
| `--fs-lg` | 17 | card titles |
| `--fs-xl` | 20 | page section |
| `--fs-2xl` | 24 | page title |
| `--fs-3xl` | 30 | day header |

The `≤720px` block overrides only the **bases**, one step down, so `--fs-scale`
still composes on top.

---

## Spacing

Base unit 4. `--s-1` and `--s-2` are fixed icon gaps; `--s-3` and up run through
`--sp-scale`, which `Theme.apply()` sets from `Prefs.density` (compact = 1,
cozy = 1.15). The `-base` values are the only place these numbers are written.

`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48`

Raised from the previous compact set (10/12/14/16/22/28/36) — "generous
whitespace" is in the thesis, and it is what separates paper from dashboard.

## Radii

`--r-sm 6` · `--r-md 8` · `--r-lg 12` · `--r-xl 16` · `--r-2xl 20` · `--r-full 999`

## Shadows

Nearly absent by design: **a card is separated by its border, not by elevation.**
Shadow is reserved for things genuinely floating above the page — modals,
popovers, the command palette.

| | light | dark |
|---|---|---|
| `--shadow-sm` | `0 1px 2px rgba(43,39,36,.05)` | `0 1px 2px rgba(0,0,0,.35)` |
| `--shadow-md` | `0 4px 14px rgba(43,39,36,.07)` | `0 4px 14px rgba(0,0,0,.45)` |
| `--shadow-lg` | `0 8px 24px rgba(43,39,36,.10)` | `0 8px 24px rgba(0,0,0,.55)` |

---

## Motion

| Token | Value | Where |
|---|---|---|
| `--dur-1` | `120ms` | hover, focus, checkbox tick |
| `--dur-2` | `180ms` | page change, section expand |
| `--dur-3` | `240ms` | modal, sheet |
| `--ease` | `cubic-bezier(.2,0,0,1)` | everywhere — sharp ease-out, no overshoot |

**Forbidden:** bounce/elastic easing, parallax, scroll-triggered reveals, hover
scale or lift.

**Load-bearing constraint, not taste:** this rendering engine parks transitions
on `left` / `right` / `opacity` at their first frame. Commit `7419e63` deleted
the entire mobile drawer over it and `455ac6a` deliberately shipped the sheet
without a slide keyframe. **Show/hide is driven by physical values with no
transition. No element's position may depend on an animation finishing.**

`prefers-reduced-motion` kills all of it.

---

## Component rules

- **Card** — `--surface`, 1px `--border`, `--r-lg`, no shadow.
- **Task row** — title, checkbox, and at most **one** secondary mark. The chips
  for XP / category / goal / kind that used to ride on every row are gone.
- **Button** — primary is `--brand` filled; secondary is transparent with a
  `--border`. Hover changes background only.
- **Focus** — 2px `--brand` outline at `2px` offset. Never removed.
- **Touch targets** — ≥ 44×44 on anything a finger drives, ≥ 8px apart.
- **Icons** — SVG only, never emoji as an icon.
- **Empty states** — say what to do next, never a bare blank panel.

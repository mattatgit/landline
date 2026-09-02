# Landline — Design and UI Conventions

## Figma source

Landline's current interface has been designed and iterated in the SpacesOS 2026 Figma file.

Recorded prototype reference:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

Figma remains the source of truth for intended visual design when a current frame exists. Do not invent missing visual details if the relevant Figma design can be inspected.

## Canvas and grid

The established desktop design is a fixed:

- 320 px wide
- 672 px high

The macOS implementation uses an 8-point grid and fixed major frames:

- top bar: x 24, y 24, 272 × 24
- radio/dial: x 24, y 96, 272 × 272
- status: x 24, y 408, 272 × 48
- volume: x 24, y 472, 272 × 80
- VU: x 24, y 568, 272 × 80

Cross-platform implementations should preserve these main layout relationships before introducing platform-specific decoration changes.

## Dial

- Local user is permanently at 12 o'clock.
- Seven remote positions are distributed around the circular dial.
- Empty positions should remain visually quieter than active contacts.
- Demo/dummy participants should not be reintroduced into production-facing states merely to fill the dial.

## Push-to-talk

- Centre PTT control is 80 × 80 in the macOS design.
- Interaction is press-and-hold.
- Hover/press/talking states use a subtle scale increase; the established macOS implementation uses approximately 104% for the PTT control.
- Muted state uses the muted microphone artwork.
- Hovering a muted PTT may change status copy to `Click to talk`, but must not replace the muted icon with an active-microphone icon.

## Speaking indicator

The speaking badge is:

- 24 × 24
- green circular surface
- four animated dark sound bars
- bars geometrically centered inside the circle

When the local user is holding PTT, remote speaking badges are suppressed so the UI shows a single active-speaker indicator.

## Status typography

Status text should use a consistent Medium-weight treatment. Do not selectively bold the username/speaker name in copy such as `You are talking` unless the design is explicitly changed.

## Profile control

The top-right profile control uses a whole-button hover scale. The intended hover treatment applies to the complete 24 px control rather than scaling only the inner profile glyph. A 105% scale was chosen to make the hover state visible.

## Profile sheet

Current macOS sheet behavior:

- 320 × 584 sheet
- open position begins at y 88
- rounded white surface at approximately 95% opacity
- main interface beneath is blurred while the sheet remains crisp
- additional subtle light veil sits above the blurred main interface
- tapping exposed backdrop closes the sheet
- sheet animates vertically from below the 672 px window

The current SwiftUI implementation uses a 25 pt blur and an ease-out sheet transition.

Before an avatar has been uploaded, the avatar-style area should retain the designed placeholder treatment rather than appearing empty.

## Window glass

macOS uses native AppKit backdrop sampling beneath a clear SwiftUI hierarchy, combined with the established Landline tint.

The design token for the current window tint is based on:

- `#ABABAB`
- 60% opacity

Do not replace the native glass surface with an opaque SwiftUI fill, because that blocks backdrop sampling.

Linux/NixOS glass should be treated as a separate implementation problem. Preserve geometry and hierarchy first; then adapt translucency to the actual compositor rather than hard-coding a macOS-specific effect.

## Window controls

macOS uses the standard traffic-light positions inside a 64 × 24 top-left backing area.

The first Linux port deliberately places neutral minimize / maximize / close controls at the same control centres inside that same backing region. Linux control styling may evolve, but the top-left footprint should remain compatible with the established Landline composition unless the overall design changes.

## Volume control

Current slider geometry in the SwiftUI build includes:

- 224 px track
- 24 px knob
- green fill
- white outer knob with green inner circle

Preserve its compact visual weight and avoid substituting a platform-default slider if doing so noticeably changes the Landline design.

## VU colors

The current dedicated VU warning colors are:

- green: `#17B239`
- orange: `#FF9601`
- red: `#FF6157`

These are intentionally separate from broader interface green/red tokens.

## Asset principle

Use supplied/exported Figma artwork where available rather than approximating distinctive icons with text or generic system glyphs. Temporary platform-port placeholders are acceptable during transport/runtime validation, but should be called out in `docs/CURRENT.md` so they are not mistaken for final design decisions.

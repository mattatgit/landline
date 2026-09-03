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

The top-right profile control is reserved for the user's profile on every platform. It must not be repurposed as a networking/settings control.

The control uses a whole-button hover scale. The intended hover treatment applies to the complete 24 px control rather than scaling only the inner profile glyph. A 105% scale was chosen to make the hover state visible.

## Profile sheet

The macOS Profile sheet is the cross-platform visual/interaction baseline:

- 320 × 584 sheet
- open position begins at y 88
- rounded white surface at approximately 95% opacity
- headline at x 24 with 24 pt Inter Tight treatment
- Name label at y 106 and 272 × 48 field at y 128
- Avatar label at y 210 and 272 × 208 avatar area at y 232
- upload/drop helper copy below the avatar area
- 272 × 48 action button at y 512
- action button is disabled when an existing profile has no changes
- main interface beneath is softened/blurred while the sheet remains crisp
- additional subtle light veil sits above the softened main interface
- tapping exposed backdrop closes the sheet
- sheet animates vertically from below the 672 px window where the platform implementation supports it

The current SwiftUI implementation uses a 25 pt blur and an ease-out sheet transition. Linux should preserve the same sheet geometry, hierarchy, typography, field/avatar/button proportions and enabled/disabled semantics even where compositor-specific backdrop blur cannot yet match AppKit exactly.

Profile image behavior should converge across platforms:

- clicking the avatar area opens image selection;
- dropping a supported image onto the avatar area/sheet is accepted where the platform supports file drops;
- the image is centre-cropped for the circular avatar presentation;
- the saved avatar persists and is reflected in the local 12-o'clock dial position;
- profile changes are exchanged with connected peers through the Landline profile/hello protocol.

Before an avatar has been uploaded, the avatar area should retain the designed placeholder treatment rather than appearing empty.

## Settings and app-menu routing

Profile and networking settings are separate concepts.

On macOS, Iroh diagnostics/connection controls live in the application's Settings scene and are reached through the normal macOS app menu.

On the custom undecorated Linux/NixOS client, the LANDLINE title acts as the in-window app-menu affordance. That menu should contain **Iroh Settings…** (and other app-level commands such as Quit as appropriate). Selecting **Iroh Settings…** opens the networking/diagnostic sheet. The top-right Profile button always opens Profile.

This Linux menu is a platform adaptation of the macOS app-menu separation; it should not change the main 320 × 672 composition.

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

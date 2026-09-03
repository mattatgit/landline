# Landline — Current State

This file is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-03.

## Current working baseline

The current macOS source in `main` is the integrated SwiftUI/AppKit + Iroh build previously referred to as **Landline Iroh Spike V10**.

The name is historical and misleading: this is no longer the rough standalone Iroh spike. The proven Iroh transport was integrated into the existing Landline SwiftUI shell, and that integrated source is the baseline from which current work should continue.

The native Linux/NixOS implementation lives on `linux-nix` and is now proven to interoperate with the macOS build.

## macOS state — `main`

Current implementation:

- 320 × 672 custom Landline desktop window.
- SwiftUI interface hosted through AppKit.
- Native glass/backdrop sampling with Landline tint.
- Local user fixed at the 12 o'clock dial position.
- Seven additional dial positions reserved for real remote participants; demo/dummy contacts were removed.
- Profile sheet with persisted name and avatar state.
- Press-and-hold PTT.
- Status panel, volume slider and VU meter.
- Iroh transport integrated into the actual Landline UI.
- Persistent Iroh endpoint identity.
- Manual connection by endpoint ID.
- Current transport implementation is intentionally one-to-one.
- Iroh chooses direct versus relay paths.
- Temporary Iroh diagnostics include selected route/path information, latency and sent/received byte counts.
- Iroh connection/diagnostics are exposed through the macOS Settings scene rather than the Profile button.
- The older `RelayClient` remains in the tree as fallback/reference code, but current audio uses `IrohClient`.

### Proven networking results

Two important runtime milestones are now proven:

1. A successful Mac-to-Mac cross-network test was completed with one laptop on a phone hotspot and the other Landline instance on a different network. Audio could be sent and received in both directions.
2. A successful **macOS ↔ NixOS** interoperability test was completed on 2026-09-03. The clients connected by Iroh endpoint ID and two-way PTT audio worked well enough for normal conversation.

Known audio issue from the Mac ↔ NixOS test:

- occasional brief crackling was heard around the moment PTT was pressed / transmission started;
- most transmitted audio was otherwise clear and usable;
- treat this as a real follow-up issue, but do not change the wire protocol without first isolating whether the transient originates in capture start, playback start/buffering, device format negotiation, or another platform audio boundary.

## Linux/NixOS state — `linux-nix`

The native Linux/NixOS port is implemented in Rust under `LandlineNix/`.

Current implementation:

- Rust 2024 / Rust 1.91 client.
- Iroh 1.0.2 transport compatible with the current macOS wire protocol.
- eframe/egui shell with the same 320 × 672 layout basis.
- custom minimize / maximize / close controls in the same top-left 64 × 24 control backing used by the macOS design.
- CPAL microphone capture.
- Rodio remote playback.
- persistent endpoint identity.
- manual one-to-one endpoint-ID connection.
- PTT framing/audio transport.
- volume control.
- shared macOS/Figma artwork for the LANDLINE title, profile button and PTT mic states.
- Inter and Inter Tight sourced through Nixpkgs and embedded into the executable at build time; host font installation is not required.
- local profile name/avatar persistence.
- PNG/JPEG avatar selection through the Linux desktop portal and drag/drop support while the Profile sheet is open.
- Linux avatars are centre-cropped/prepared as JPEG, displayed in the local 12-o'clock slot and sent through the existing Landline hello/profile payload.
- the Profile button is now reserved for Profile, matching macOS.
- clicking the LANDLINE title opens a compact in-window app menu containing **Iroh Settings…** and **Quit Landline**; Iroh connection controls are no longer routed through Profile.
- the Linux Profile sheet now uses the macOS/Figma 320 × 584 / y=88 geometry, name/avatar hierarchy and disabled/enabled Update semantics.
- Nix flake and locked dependency set.

Validation completed before the latest Profile/Settings parity pass:

- `cargo check` succeeds inside `nix develop`.
- optimized release builds succeed in GitHub Actions inside the Nix development shell.
- the app launches on a real NixOS desktop.
- the shared SVG/profile artwork and embedded fonts were integrated after the first Nix screenshot exposed fallback rendering.
- real macOS ↔ NixOS connection and two-way PTT audio are proven working.

Latest validation state:

- the Profile/Settings parity source is committed on `linux-nix`;
- its full Nix release-build validation is being rerun after fixing a Rust UI borrow-checker issue found by CI;
- it still needs a real NixOS visual/runtime check after that build passes.

Remaining parity/runtime work includes:

- verify the new Linux Profile sheet, image picker/drop behavior and app-menu routing on the real NixOS desktop;
- verify Linux-sent profile avatars appear correctly to macOS peers;
- implement/display received remote avatars on Linux if still missing;
- investigate the occasional start-of-PTT crackle;
- continue compositor-specific glass/translucency work after functional/profile parity is stable.

## Current product/transport distinction

Do not confuse the intended Landline participant model with the current network implementation:

- Product/UI model: local user + up to seven remote positions = eight-person dial.
- Current Iroh implementation: one connected remote peer at a time.

The one-to-one transport is a deliberate first integration step, not a decision to reduce the product permanently to two users.

## Important current UI conventions

Preserve these unless a new design decision explicitly changes them:

- local user stays at 12 o'clock.
- PTT is press-and-hold.
- when the local user is talking, remote speaking indicators are suppressed so there is one active-speaker indicator.
- speaking badge contains four animated sound bars centered inside a 24 × 24 green circle.
- status text uses Medium-weight treatment rather than selectively bolding the speaker name.
- muted PTT hover may say `Click to talk`, but must not visually swap the muted mic icon to an active-mic icon.
- profile sheet uses the established blurred/glass modal treatment where the platform can support it, while preserving exact geometry/hierarchy first.
- profile button hover scales the full 24 px button, not only the glyph.
- the Profile button opens Profile on both platforms; networking/Iroh settings must not replace it.

## Design reference

The Landline design/prototype work has been developed against the SpacesOS 2026 Figma file. One recorded prototype reference is:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

When visual intent and implementation disagree, inspect the relevant current Figma frame before inventing a new treatment.

## Repository workflow

Repository: `mattatgit/landline`

Current branches:

- `main` — macOS working baseline plus continuity documentation.
- `linux-nix` — active native Linux/NixOS port.

GitHub is the durable implementation/project record. Do not return to ZIP-based source handoffs as the normal workflow.

## Current next step

**Finish release validation of the Profile/Settings parity build, then run it on the real NixOS machine and compare it directly with the macOS Profile sheet.**

Verify, in order:

1. Profile button opens **Edit profile**, not Iroh settings;
2. sheet position, field/avatar/button geometry and typography visually track the macOS reference;
3. unchanged existing profile shows a disabled Update button and edits enable it;
4. PNG/JPEG click-to-upload works through the desktop portal;
5. drag/drop image import works;
6. saved name/avatar survive relaunch and appear in the local 12-o'clock slot;
7. LANDLINE title opens the in-window app menu and **Iroh Settings…** opens the connection controls;
8. Mac and Nix reconnect and exchange profile data correctly;
9. repeat PTT tests and gather more observations about the start-of-transmission crackle before deciding on an audio buffering/capture fix.

After that runtime pass, update this file with the results and choose between crackle mitigation, received-avatar parity on Linux, or further compositor/glass polish as the next priority.

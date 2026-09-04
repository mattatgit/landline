# Landline — Current State

This file is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-04.

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
- Local PTT is tied to Iroh endpoint readiness rather than peer presence: an online user can hold PTT, see the talking state and use the mic/VU even when no peers are online; network frames are sent only when a peer connection exists.
- Status panel, volume slider and VU meter.
- Iroh transport integrated into the actual Landline UI.
- Persistent Iroh endpoint identity.
- Manual connection by endpoint ID.
- Current transport implementation is intentionally one-to-one.
- Iroh chooses direct versus relay paths.
- Temporary Iroh diagnostics include selected route/path information, latency and sent/received byte counts.
- Iroh connection/diagnostics are exposed through the macOS Settings scene rather than the Profile button.
- The older `RelayClient` remains in the tree as fallback/reference code, but current audio uses `IrohClient`.

### macOS PTT no-peer regression fix — 2026-09-04

A regression was confirmed where holding PTT while the Iroh endpoint was online but no peer was connected briefly showed the talking state and then immediately reverted to muted. The cause was `IrohClient.beginTransmit()` requiring `isConnected` and an active `sendStream`, incorrectly conflating endpoint availability with peer presence.

The fix now:

- allows local PTT whenever the Iroh endpoint is ready and no remote speaker is active;
- keeps microphone capture, VU and the local talking state active for the duration of the hold when no peers are online;
- sends `pttBegin`, audio and `pttEnd` only when a peer connection exists;
- keeps local PTT active if the sole peer disappears during the start of a hold.

The current source was compiled as a full optimized Release app in GitHub Actions using Xcode 16.2, Swift 6.0.3 and the macOS 15.2 SDK. The build and application validation steps passed. The CI test artifact is an unsigned **arm64** macOS application with a minimum system version of macOS 15.0. Runtime confirmation of the no-peer hold behavior on a real Mac is still required.

The Release validation also exposed an existing Swift 6 overload ambiguity in the dial `cos`/`sin` geometry. That was corrected without changing geometry by using `CGFloat` angles and explicit CoreGraphics trigonometric functions.

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

Validation completed:

- `cargo check` succeeds inside `nix develop`.
- optimized release builds succeed in GitHub Actions inside the Nix development shell.
- the app launches on a real NixOS desktop.
- the shared SVG/profile artwork and embedded fonts were integrated after the first Nix screenshot exposed fallback rendering.
- real macOS ↔ NixOS connection and two-way PTT audio are proven working.
- the Profile/Settings parity source compiles and links successfully as a full optimized Nix release build; CI run 12 completed successfully after correcting the profile-sheet borrow-checker issue.
- dependency locks were refreshed after the successful parity build; current `linux-nix` head is the resulting locked build state.

Still to validate on the real NixOS desktop after the Profile/Settings parity build:

- verify the new Linux Profile sheet, image picker/drop behavior and app-menu routing;
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
- an online Landline endpoint can use local PTT even when no peers are currently online.
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

**Runtime-test the new macOS no-peer PTT build on an Apple Silicon Mac.**

Verify first:

1. launch Landline and wait until the Iroh endpoint is ready while leaving all peers offline/disconnected;
2. press and hold PTT for several seconds;
3. confirm the centre button remains in its talking state until release rather than flashing and reverting to muted;
4. confirm the status remains `You are talking` while held;
5. confirm the microphone/VU responds while held;
6. release PTT and confirm it returns cleanly to muted;
7. reconnect a peer and verify normal two-way PTT still works.

After that, continue the NixOS parity/runtime pass and investigate the occasional start-of-PTT crackle if it remains reproducible.

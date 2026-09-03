# Landline — Current State

This file is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-03.

## Current working baseline

The current macOS source in `main` is the integrated SwiftUI/AppKit + Iroh build previously referred to as **Landline Iroh Spike V10**.

The name is historical and misleading: this is no longer the rough standalone Iroh spike. The proven Iroh transport was integrated into the existing Landline SwiftUI shell, and that integrated source is the baseline from which current work should continue.

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
- The older `RelayClient` remains in the tree as fallback/reference code, but current audio uses `IrohClient`.

### Proven macOS networking result

A successful cross-network test was completed with one laptop on a phone hotspot and the other Landline instance on a different network. Audio could be sent and received in both directions. This was the key proof that the Iroh integration could operate beyond a shared local network.

## Linux/NixOS state — `linux-nix`

A first native Linux/NixOS port now exists on `linux-nix`.

Current implementation:

- Rust 2024 client in `LandlineNix/`.
- Iroh 1.0.2 transport compatible with the current macOS wire protocol.
- eframe/egui shell with the same 320 × 672 layout basis.
- custom minimize / maximize / close controls in the same top-left 64 × 24 control backing used by the macOS design.
- CPAL microphone capture.
- Rodio remote playback.
- persistent endpoint identity.
- manual one-to-one endpoint-ID connection.
- PTT framing/audio transport.
- profile display-name exchange.
- volume control.
- temporary Iroh connection panel opened from the LANDLINE wordmark.
- Nix flake and locked dependency set.
- shared macOS/Figma artwork for the LANDLINE title, profile button and PTT mic states is now compiled into the Linux client.
- Inter and Inter Tight are provided by Nixpkgs at build time and embedded into the executable, so UI typography does not depend on fonts installed on the host desktop.

Validation completed:

- `cargo check` succeeds inside `nix develop`.
- a full optimized release binary build succeeds in GitHub Actions inside the Nix development shell.
- the first real NixOS launch was completed and the 320 × 672 app rendered on a NixOS desktop.
- that first screenshot exposed four fidelity issues: missing PTT/profile artwork, missing LANDLINE title artwork, incorrect volume-number placement, and fallback/system typography.
- a follow-up fidelity pass replaced the approximated title/PTT/profile graphics with the shared supplied assets, corrected the volume-number right edge, and embedded Inter/Inter Tight into the Linux executable.
- the follow-up optimized release build also succeeds in GitHub Actions.

Still to validate on a real NixOS desktop after the fidelity rebuild:

- confirm the supplied title/PTT/profile artwork now renders correctly;
- confirm Inter/Inter Tight render correctly without host font installation;
- confirm corrected volume-number placement;
- Wayland/X11 and compositor-specific window-control behavior;
- microphone/audio-device behavior and permissions;
- Mac ↔ NixOS connection and two-way audio.

Intentional first-port gaps:

- Linux avatar upload/display parity is incomplete.
- final Linux glass/translucency treatment is incomplete.

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
- profile sheet uses the established blurred/glass modal treatment.
- profile button hover scales the full 24 px button, not only the glyph.

## Design reference

The Landline design/prototype work has been developed against the SpacesOS 2026 Figma file. One recorded prototype reference is:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

When visual intent and implementation disagree, inspect the relevant current Figma frame before inventing a new treatment.

## Repository workflow

Repository: `mattatgit/landline`

Current branches:

- `main` — macOS working baseline plus continuity documentation.
- `linux-nix` — active first Linux/NixOS port.

GitHub is the durable implementation/project record. Do not return to ZIP-based source handoffs as the normal workflow.

## Current next step

**Re-run the updated `linux-nix` client on the real NixOS machine, confirm the visual-fidelity fixes, then perform the first Mac ↔ NixOS interoperability test.**

Test, in order:

1. pull/switch to the latest `linux-nix` and launch via the Nix development shell;
2. confirm the LANDLINE title artwork, profile artwork and PTT muted/on SVGs render;
3. confirm Inter/Inter Tight typography renders without installing fonts on the host;
4. confirm the volume numeric display is correctly aligned;
5. confirm the custom Linux window controls behave correctly;
6. confirm endpoint identity appears and remains stable across relaunch;
7. connect Mac and NixOS clients by endpoint ID;
8. verify profile/name exchange;
9. verify PTT and two-way audio;
10. verify volume behavior;
11. note whether Iroh uses a direct or relay path where diagnostics make this visible;
12. record compositor/audio-device-specific issues before doing further visual-polish work.

After that test, update this file with the runtime results and decide whether the next priority is interoperability fixes, Linux visual parity, or moving beyond one-to-one transport.

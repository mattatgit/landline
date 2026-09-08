# Landline — Current State

This is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-08.

## Repository / branch roles

Repository: `mattatgit/landline`

- `main` — canonical macOS SwiftUI/AppKit + Iroh baseline, canonical web prototype workspace and continuity docs.
- `linux-nix` — active native Rust/NixOS port.

GitHub is the durable source of truth. Do not return to ZIP-based source handoffs as the normal development workflow.

## Prototype-first product workflow — adopted

Landline now uses a prototype-first implementation sequence for new UI flows:

1. explore/design in Figma or discussion;
2. implement and test the interaction in the browser prototype;
3. agree the behavior and visual treatment;
4. implement the approved flow in macOS;
5. runtime-test the macOS implementation;
6. bring Linux/NixOS to behavioral/visual parity;
7. run cross-platform validation where networking or shared state is involved.

Repository locations:

- `prototypes/app/` — canonical full Landline browser prototype;
- `prototypes/experiments/` — isolated interaction/visual experiments.

The browser prototype is a design-validation implementation, not a production web client.

### Current prototype import status

The repository structure and workflow documentation have been added on `chore/web-prototype-workflow`.

The actual latest full Landline browser prototype is **not yet imported** because its source files are not present in the repository or in the currently available source archive. Do not recreate it from incomplete chat memory or screenshots and then treat that reconstruction as canonical.

The latest approved **Add User** flow from the Prototyping Features work should be the first feature captured in `prototypes/app/`. Once the real prototype source is available/imported, use it as the executable reference for the macOS Add User implementation.

## macOS baseline — `main`

The current macOS source is the integrated build historically called **Landline Iroh Spike V10**. It is no longer a standalone spike; the proven Iroh transport is integrated into the Landline UI.

Current macOS behavior:

- fixed 320 × 672 custom SwiftUI/AppKit window with native glass/backdrop treatment;
- local user fixed at 12 o'clock; seven remote dial positions reserved for the intended eight-person product model;
- Profile sheet with persisted name/avatar state;
- press-and-hold PTT, status panel, volume and VU meter;
- persistent Iroh endpoint identity and manual endpoint-ID connection;
- current transport is deliberately one-to-one; Iroh selects direct versus relay paths;
- Iroh connection/diagnostics live in the macOS Settings scene, not behind Profile;
- older `RelayClient` remains only as fallback/reference; current audio uses `IrohClient`.

### macOS traffic-light drift repair — source fixed, build passed, runtime longevity test pending

The previous implementation re-parented AppKit's window-owned standard controls and used resize/tracking workarounds. That architecture has been replaced.

Current implementation:

- leaves AppKit's window-owned standard buttons in their normal title-bar hierarchy and hides them;
- creates three independent native standard controls with `NSWindow.standardWindowButton(_:for:)`;
- targets those caller-owned controls at the Landline window and hosts them at the established Figma centres;
- removes the `+1/-1` frame nudge, direct `updateTrackingAreas()` calls and related repair paths;
- locks the outer window to 320 × 672 using identical `minSize`/`maxSize` while retaining `.resizable` only for normal native green-button appearance;
- disables full-screen behavior;
- recreates group-hover glyphs with the approved centered SVG-derived paths/colors.

The replacement completed an Apple Silicon Release build and packaging/signature validation on 2026-09-07.

Runtime validation still needs to confirm placement, hover/inactive behavior, close/minimize/green-button behavior, fixed-size behavior, appearance/sleep/display stability, and no long-running drift recurrence.

### No-peer PTT regression — fixed and runtime confirmed

Local PTT is allowed whenever the Iroh endpoint is ready and no remote speaker is active. Microphone capture, VU and talking state remain active for the full hold even with zero peers online; network PTT/audio frames are sent only when a peer exists.

This behavior was runtime-confirmed on a real Apple Silicon Mac on 2026-09-04.

### First microphone permission crash — fixed in source, runtime re-test pending

The first-use Swift 6 crash came from actor isolation around AVFoundation's callback permission API. `MicrophoneCapture` now uses AVFoundation's native async permission API:

`await AVCaptureDevice.requestAccess(for: .audio)`

The fixed source completed a full Apple Silicon Release compile. Runtime confirmation still requires resetting microphone permission so macOS presents the prompt again.

### macOS packaging

The verified distributable is **Apple Silicon arm64**, macOS 15+.

Pinned `iroh-ffi` 1.1.0 provides the required `aarch64-apple-darwin` macOS build but not an x86_64 macOS slice. Do not describe the current build as Universal.

Ad-hoc signing is suitable for test builds but is not Apple notarization.

## Proven networking results

Two key runtime milestones are proven:

1. Mac ↔ Mac cross-network audio worked with one laptop on a phone hotspot and the other on a separate network.
2. macOS ↔ NixOS interoperability worked on 2026-09-03: connection by Iroh endpoint ID and two-way PTT audio were usable for normal conversation.

Known audio issue: occasional brief crackling can occur around PTT start; most audio is otherwise clear. Investigate capture/playback/buffering/device-format boundaries before changing the wire protocol.

## Linux/NixOS baseline — `linux-nix`

The native Linux client lives under `LandlineNix/` and uses Rust 1.91, Iroh 1.0.2, eframe/egui, CPAL and Rodio.

Current Linux implementation includes:

- same 320 × 672 layout basis and custom window controls;
- shared Landline title/profile/PTT artwork;
- embedded Inter + Inter Tight;
- persistent Iroh endpoint identity;
- one-to-one PTT/audio compatible with the macOS wire protocol;
- local profile name/avatar persistence;
- Profile button reserved for Profile;
- LANDLINE app menu containing Iroh Settings… and Quit;
- Profile sheet aligned to the macOS geometry/hierarchy;
- PNG/JPEG avatar selection and drag/drop;
- avatar exchange through the existing Hello/profile payload;
- Nix flake and locked dependency set.

Real macOS ↔ NixOS two-way audio is proven. The current `linux-nix` GitHub Actions workflow is green at branch head.

Remaining Linux parity/runtime work is primarily real-desktop validation for opacity/theme behavior, Profile sheet treatment, image-picker/drop stability, avatar persistence/remote display, and any reproducible start-of-PTT crackle.

## Product vs current transport

Do not confuse the intended Landline product with the current transport limitation:

- intended product: local user + up to seven remote participants = eight-person shared dial;
- current implementation: one connected remote peer at a time.

The one-to-one transport is an integration stage, not a permanent reduction of the product.

Longer-term direction discussed includes persistent Landline user/contact identities, invite/QR-based onboarding instead of pasted endpoint IDs, automatic reconnect, and multi-participant fan-out. These are not yet all implemented decisions.

## UI conventions to preserve

- local user stays at 12 o'clock;
- PTT is press-and-hold;
- endpoint-online users can hold PTT even when no peers are online;
- suppress remote speaking indicators while local user is talking;
- speaking badge uses four centered animated bars in a 24 × 24 green circle;
- status text uses Medium weight;
- muted PTT hover may say `Click to talk` but must not swap the muted icon to active;
- Profile button hover scales the full 24 px button;
- Profile opens Profile on both platforms; networking settings belong in Settings/app menu;
- preserve established sheet geometry/hierarchy first; platform-specific blur/glass may differ;
- macOS traffic lights stay at the established Figma centres and use caller-owned native standard buttons rather than re-parenting AppKit's window-owned instances.

## Design reference

Primary Figma prototype reference:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

When implementation and visual intent disagree, inspect the relevant Figma frame and current canonical web prototype before inventing a new treatment.

## Current next step

Complete the new prototype-first handoff for **Add User**:

1. import the actual latest Landline browser prototype source into `prototypes/app/`;
2. verify that the approved Add User flow is present and capture any non-obvious behavior in the prototype documentation;
3. inspect the current macOS `main` implementation against that prototype;
4. implement Add User in Swift from the current macOS baseline;
5. build and runtime-test the new macOS flow;
6. once macOS behavior is approved, bring the Linux/NixOS client to parity.

The existing macOS traffic-light longevity test and microphone first-permission runtime re-test remain outstanding regression checks and should not be lost during Add User work.

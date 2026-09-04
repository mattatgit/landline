# Landline — Current State

This is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-04.

## Repository / branch roles

Repository: `mattatgit/landline`

- `main` — canonical macOS SwiftUI/AppKit + Iroh baseline and continuity docs.
- `linux-nix` — active native Rust/NixOS port.

GitHub is the durable source of truth. Do not return to ZIP-based source handoffs as the normal development workflow.

## macOS baseline — `main`

The current macOS source is the integrated build historically called **Landline Iroh Spike V10**. It is no longer a standalone spike; the proven Iroh transport is integrated into the Landline UI.

Current macOS behavior:

- 320 × 672 custom SwiftUI/AppKit window with native glass/backdrop treatment.
- local user fixed at 12 o'clock; seven remote dial positions reserved for the intended eight-person product model.
- Profile sheet with persisted name/avatar state.
- press-and-hold PTT, status panel, volume and VU meter.
- persistent Iroh endpoint identity and manual endpoint-ID connection.
- current transport is deliberately one-to-one; Iroh selects direct versus relay paths.
- Iroh connection/diagnostics live in the macOS Settings scene, not behind Profile.
- older `RelayClient` remains only as fallback/reference; current audio uses `IrohClient`.

### No-peer PTT regression — fixed and runtime confirmed

A regression caused PTT to flash into talking state and immediately return to muted when the Iroh endpoint was online but no peer was connected. `IrohClient.beginTransmit()` was incorrectly requiring an active peer/send stream.

Current behavior now separates endpoint readiness from peer presence:

- local PTT is allowed whenever the Iroh endpoint is ready and no remote speaker is active;
- microphone capture, VU and talking state remain active for the entire hold even with zero peers online;
- `pttBegin`, audio and `pttEnd` are sent only when a peer exists;
- remote-speaker arbitration still blocks local PTT when appropriate.

This behavior was runtime-confirmed on a real Apple Silicon Mac on 2026-09-04: PTT could be pressed and held with no peers online and remained active until release.

### First microphone permission crash — fixed in source, runtime re-test pending

During the first real-Mac test of the repaired no-peer PTT build, the app crashed once on the first PTT press while macOS was handling the initial microphone permission request.

The crash report showed `EXC_BREAKPOINT / SIGTRAP` on a background TCC callback queue with `_dispatch_assert_queue_fail` and `_swift_task_checkIsolatedSwift`, pointing directly to the completion-handler closure inside `MicrophoneCapture.ensurePermission()`.

Cause: `MicrophoneCapture` is `@MainActor` isolated, while `AVCaptureDevice.requestAccess(for:completionHandler:)` may invoke its callback on a background queue. Under Swift 6, the callback inherited actor isolation and the runtime trapped before the closure body could execute.

Fix:

- removed the manual `withCheckedContinuation` wrapper around the completion-handler API;
- now uses AVFoundation's native async overload: `await AVCaptureDevice.requestAccess(for: .audio)`;
- permission/UI state continues on the MainActor after the await.

The fixed source completed a full Apple Silicon Release compile in GitHub Actions, then passed app/icon verification, ad-hoc signing, ZIP packaging, ZIP extraction and post-extraction signature verification. Runtime confirmation of the first-permission path still requires resetting microphone permission so macOS presents the prompt again.

### macOS app icon / signing repair — 2026-09-04

The previous downloadable build exposed two packaging regressions: the AppIcon asset set had disappeared from `Assets.xcassets`, and the downloadable `.app` was completely unsigned, causing Safari-quarantined copies to be rejected by Gatekeeper as “damaged”.

The canonical AppIcon set has now been regenerated from `LandlineMac/Resources/Landline_app_icon_source.png` and committed to `main`.

The repaired Apple Silicon Release pipeline now passes all of these checks:

- optimized Xcode Release compile;
- generated `AppIcon.icns`/asset verification;
- arm64 executable verification;
- ad-hoc signing of the completed `.app`;
- `codesign --verify --deep --strict` before packaging;
- ZIP packaging with `ditto`;
- extraction of the final ZIP and a second signature verification after the ZIP round-trip;
- artifact upload.

The verified distributable is **Apple Silicon arm64**, macOS 15+.

Important architecture constraint: pinned `iroh-ffi` 1.1.0 builds `aarch64-apple-darwin` for macOS but does not build a `x86_64-apple-darwin` macOS slice. Forcing `ARCHS=arm64 x86_64` therefore fails at link time. Do not label this build Universal unless the Iroh dependency strategy is changed or an x86_64 macOS Iroh slice is built separately.

Ad-hoc signing is suitable for test builds but is not Apple notarization. A Safari-downloaded build may still require Right-click → Open or Privacy & Security → Open Anyway on first launch. A warning-free public distribution requires Developer ID signing and Apple notarization.

## Proven networking results

Two key runtime milestones are proven:

1. Mac ↔ Mac cross-network audio worked with one laptop on a phone hotspot and the other on a separate network.
2. macOS ↔ NixOS interoperability worked on 2026-09-03: connection by Iroh endpoint ID and two-way PTT audio were usable for normal conversation.

Known audio issue:

- occasional brief crackling occurs around PTT start;
- most audio is otherwise clear;
- isolate capture start, playback start/buffering, device format negotiation or another audio boundary before changing the wire protocol.

## Linux/NixOS baseline — `linux-nix`

The native Linux client lives under `LandlineNix/` and uses Rust 1.91, Iroh 1.0.2, eframe/egui, CPAL and Rodio.

Current Linux implementation includes:

- same 320 × 672 layout basis and custom window controls;
- shared Landline title/profile/PTT artwork;
- Inter + Inter Tight embedded into the executable from Nixpkgs at build time;
- persistent Iroh endpoint identity;
- one-to-one PTT/audio compatible with the macOS wire protocol;
- local profile name/avatar persistence;
- Profile button reserved for Profile;
- LANDLINE app menu containing Iroh Settings… and Quit;
- Profile sheet aligned to the macOS geometry/hierarchy;
- PNG/JPEG avatar selection and drag/drop;
- Linux avatar JPEG sent through the existing Hello/profile payload;
- received remote avatar data is wired through to the Linux UI after an earlier bug discarded it;
- Nix flake and locked dependency set.

Real macOS ↔ NixOS two-way audio is proven. The latest Linux parity fixes still need full real-desktop confirmation for opacity/theme, sheet shadow, image upload stability and remote-avatar display.

## Product vs current transport

Do not confuse the intended Landline product with the current transport limitation:

- intended product: local user + up to seven remote participants = eight-person shared dial;
- current implementation: one connected remote peer at a time.

The one-to-one transport is an integration stage, not a permanent reduction of the product.

Longer-term direction discussed: persistent Landline user/contact identities, invite/QR-based onboarding instead of pasted endpoint IDs, automatic reconnect, and fan-out of live PTT audio to all online dial members. Direct Iroh streams remain the preferred live-audio path; group/presence state may use a separate mechanism such as Iroh gossip.

## UI conventions to preserve

- local user stays at 12 o'clock.
- PTT is press-and-hold.
- endpoint-online users can hold PTT even when no peers are online.
- suppress remote speaking indicators while local user is talking.
- speaking badge uses four centered animated bars in a 24 × 24 green circle.
- status text uses Medium weight; do not selectively bold the speaker name.
- muted PTT hover may say `Click to talk` but must not swap the muted icon to active.
- Profile button hover scales the full 24 px button.
- Profile opens Profile on both platforms; networking settings belong in Settings/app menu.
- preserve established sheet geometry/hierarchy first; platform-specific blur/glass may differ.

## Design reference

Primary prototype reference:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

When implementation and visual intent disagree, inspect the relevant Figma frame before inventing a new treatment.

## Current next step

Runtime-test the **microphone permission crash fix** on a real Apple Silicon Mac.

Because the existing bundle may already have microphone permission, reset that permission first so the first-request code path runs again:

` tccutil reset Microphone com.landline.prototype.mac `

Then:

1. launch the new fixed build;
2. with no peers connected, press and hold PTT;
3. confirm macOS presents the microphone permission prompt without Landline crashing;
4. allow microphone access and confirm PTT remains in `You are talking` for the full hold and the VU responds;
5. release and repeat PTT several times;
6. reconnect a peer and verify normal two-way PTT still works.

After that, continue the Linux parity/runtime pass and investigate the occasional start-of-PTT crackle if reproducible.

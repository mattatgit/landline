# Landline — Current State

This is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-07.

## Repository / branch roles

Repository: `mattatgit/landline`

- `main` — canonical macOS SwiftUI/AppKit + Iroh baseline and continuity docs.
- `linux-nix` — active native Rust/NixOS port.

GitHub is the durable source of truth. Do not return to ZIP-based source handoffs as the normal development workflow.

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

A long-running macOS UI regression could move the close/minimize/zoom traffic lights up and left after the app had remained open for some time. The previous implementation took the actual `NSWindow.standardWindowButton(_:)` instances out of AppKit's title-bar/theme-frame hierarchy and re-parented them into Landline's 64 × 24 Figma host. It also used a `+1/-1` live-window resize nudge and direct `updateTrackingAreas()` calls to repair hover tracking.

That architecture has now been replaced.

Current implementation:

- leaves AppKit's window-owned standard buttons in their normal title-bar hierarchy and hides them;
- creates three independent native standard controls with `NSWindow.standardWindowButton(_:for:)`;
- targets those caller-owned controls at the Landline window and hosts them at the established Figma centres;
- removes the `+1/-1` frame nudge, direct `updateTrackingAreas()` calls, `refreshingTrafficTracking`, `windowDidBecomeMain` repair path and run-loop-delayed install hack;
- replaces deprecated `NSApp.activate(ignoringOtherApps:)` with `NSApp.activate()`;
- locks the outer window to 320 × 672 using identical `minSize`/`maxSize` while retaining `.resizable` only for the normal active green native-button appearance;
- disables full-screen behavior with `.fullScreenNone`.

The replacement completed an Apple Silicon Release build in GitHub Actions on 2026-09-07, then passed app/icon verification, arm64 verification, ad-hoc signing, ZIP packaging, ZIP extraction and post-extraction signature verification.

Runtime validation still needs to confirm:

- exact initial traffic-light placement;
- native hover/group-hover appearance;
- inactive-window appearance;
- close, minimize and green-button behavior;
- inability to resize/full-screen the Landline canvas;
- stability through manual light/dark appearance changes, app deactivate/reactivate, sleep/wake and display changes;
- no recurrence of traffic-light drift after several hours/overnight.

### No-peer PTT regression — fixed and runtime confirmed

A regression caused PTT to flash into talking state and immediately return to muted when the Iroh endpoint was online but no peer was connected. `IrohClient.beginTransmit()` was incorrectly requiring an active peer/send stream.

Current behavior separates endpoint readiness from peer presence:

- local PTT is allowed whenever the Iroh endpoint is ready and no remote speaker is active;
- microphone capture, VU and talking state remain active for the entire hold even with zero peers online;
- `pttBegin`, audio and `pttEnd` are sent only when a peer exists;
- remote-speaker arbitration still blocks local PTT when appropriate.

This behavior was runtime-confirmed on a real Apple Silicon Mac on 2026-09-04.

### First microphone permission crash — fixed in source, runtime re-test pending

During the first real-Mac test of the repaired no-peer PTT build, the app crashed once on the first PTT press while macOS was handling the initial microphone permission request.

The crash report showed `EXC_BREAKPOINT / SIGTRAP` on a background TCC callback queue with `_dispatch_assert_queue_fail` and `_swift_task_checkIsolatedSwift`, pointing to the completion-handler closure inside `MicrophoneCapture.ensurePermission()`.

Cause: `MicrophoneCapture` is `@MainActor` isolated, while `AVCaptureDevice.requestAccess(for:completionHandler:)` may invoke its callback on a background queue. Under Swift 6, the callback inherited actor isolation and the runtime trapped before the closure body could execute.

Fix:

- removed the manual `withCheckedContinuation` wrapper around the completion-handler API;
- now uses AVFoundation's native async overload: `await AVCaptureDevice.requestAccess(for: .audio)`;
- permission/UI state continues on the MainActor after the await.

The fixed source completed a full Apple Silicon Release compile in GitHub Actions. Runtime confirmation of the first-permission path still requires resetting microphone permission so macOS presents the prompt again.

### macOS app icon / signing repair

The canonical AppIcon set has been regenerated from `LandlineMac/Resources/Landline_app_icon_source.png` and committed to `main`.

The repaired Apple Silicon Release pipeline verifies:

- optimized Xcode Release compile;
- generated `AppIcon.icns`/asset presence;
- arm64 executable architecture;
- ad-hoc signing of the completed `.app`;
- `codesign --verify --deep --strict` before packaging;
- ZIP packaging with `ditto`;
- extraction of the final ZIP and a second signature verification after the ZIP round-trip.

The verified distributable is **Apple Silicon arm64**, macOS 15+.

Important architecture constraint: pinned `iroh-ffi` 1.1.0 builds `aarch64-apple-darwin` for macOS but does not build a `x86_64-apple-darwin` macOS slice. Do not label this build Universal unless the Iroh dependency strategy is changed or an x86_64 macOS Iroh slice is built separately.

Ad-hoc signing is suitable for test builds but is not Apple notarization. A warning-free public distribution requires Developer ID signing and Apple notarization.

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
- received remote avatar data retained and decoded into the Linux UI;
- Nix flake and locked dependency set.

Real macOS ↔ NixOS two-way audio is proven.

The current `linux-nix` GitHub Actions workflow is green at branch head and verifies repeated release source builds in the same Cargo target tree plus a Nix application package build.

The remaining Linux parity/runtime pass is primarily real-desktop validation for:

- opacity/theme behavior across compositor/desktop combinations;
- Profile sheet shadow/backdrop treatment;
- image picker and drag/drop stability;
- local avatar persistence after relaunch;
- received remote-avatar display;
- any reproducible start-of-PTT crackle.

## Product vs current transport

Do not confuse the intended Landline product with the current transport limitation:

- intended product: local user + up to seven remote participants = eight-person shared dial;
- current implementation: one connected remote peer at a time.

The one-to-one transport is an integration stage, not a permanent reduction of the product.

Longer-term direction discussed: persistent Landline user/contact identities, invite/QR-based onboarding instead of pasted endpoint IDs, automatic reconnect, and fan-out of live PTT audio to all online dial members. Direct Iroh streams remain the preferred live-audio path; group/presence state may use a separate mechanism such as Iroh gossip.

## UI conventions to preserve

- local user stays at 12 o'clock;
- PTT is press-and-hold;
- endpoint-online users can hold PTT even when no peers are online;
- suppress remote speaking indicators while local user is talking;
- speaking badge uses four centered animated bars in a 24 × 24 green circle;
- status text uses Medium weight; do not selectively bold the speaker name;
- muted PTT hover may say `Click to talk` but must not swap the muted icon to active;
- Profile button hover scales the full 24 px button;
- Profile opens Profile on both platforms; networking settings belong in Settings/app menu;
- preserve established sheet geometry/hierarchy first; platform-specific blur/glass may differ;
- macOS traffic lights stay at the established Figma centres and should use caller-owned native standard buttons rather than re-parenting AppKit's window-owned instances.

## Design reference

Primary prototype reference:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

When implementation and visual intent disagree, inspect the relevant Figma frame before inventing a new treatment.

## Current next step

Runtime-test the new **macOS traffic-light drift repair** and the already-built **microphone permission crash fix** on a real Apple Silicon Mac.

Traffic-light pass:

1. launch the new traffic-light-fix build and confirm all three controls start in the exact intended top-left position;
2. confirm hover/group-hover and inactive-window appearance still look native;
3. verify close and minimize behavior and note exactly what the green button does;
4. confirm the Landline window cannot be user-resized or taken full screen;
5. manually switch light ↔ dark appearance, deactivate/reactivate Landline, sleep/wake the Mac, and connect/disconnect a display if practical;
6. leave Landline open for several hours/overnight and confirm the traffic lights never move up/left.

Microphone first-permission pass:

1. run `tccutil reset Microphone com.landline.prototype.mac`;
2. launch the fixed build;
3. with no peers connected, press and hold PTT;
4. confirm macOS presents the microphone permission prompt without Landline crashing;
5. allow microphone access and confirm PTT remains in `You are talking` for the full hold and the VU responds;
6. release and repeat PTT several times;
7. reconnect a peer and verify normal two-way PTT still works.

After those macOS runtime checks, continue the Linux parity/runtime pass and investigate the occasional start-of-PTT crackle if reproducible.

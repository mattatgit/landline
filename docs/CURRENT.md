# Landline — Current State

This is the concise continuity record for active Landline work. Update it whenever a meaningful milestone, technical decision, known issue, working baseline or next step changes.

Last consolidated: 2026-09-08.

## Repository / branch roles

Repository: `mattatgit/landline`

- `main` — canonical macOS SwiftUI/AppKit + Iroh v1 baseline, canonical V22 web prototype and continuity docs.
- `feature/macos-add-user` — macOS Add User implementation based on V22; Apple Silicon test build produced and UI runtime-checked.
- `feature/macos-multi-user` — active macOS group transport work, stacked on Add User; protocol v2/direct mesh.
- `linux-nix` — active native Rust/NixOS port; currently protocol v1/one-to-one.

GitHub is the durable source of truth. Do not return to ZIP-based source handoffs as the normal development workflow.

## Prototype-first product workflow

Landline uses this sequence for new UI flows:

1. explore/design in Figma or discussion;
2. implement and test the interaction in the browser prototype;
3. agree the behavior and visual treatment;
4. implement the approved flow in macOS;
5. runtime-test macOS;
6. bring Linux/NixOS to behavioral/visual parity;
7. run cross-platform validation where networking/shared state is involved.

Repository locations:

- `prototypes/app/` — canonical full browser prototype;
- `prototypes/experiments/` — isolated interaction/visual experiments.

### Canonical prototype

Landline V22 is imported under `prototypes/app/` and is the executable interaction reference for the approved Add User flow. The supplied prototype includes empty-slot hover, Add/Invite sheet, Landline ID entry and copy-ID behavior.

## macOS stable baseline — `main`

The current `main` macOS implementation is the integrated SwiftUI/AppKit + Iroh baseline historically called Landline Iroh Spike V10.

Established behavior includes:

- fixed 320 × 672 custom window with native glass/backdrop treatment;
- local user fixed at 12 o'clock and seven remote dial positions;
- persisted local Profile name/avatar;
- press-and-hold PTT, status panel, volume and VU meter;
- persistent Iroh endpoint identity;
- protocol v1 one-to-one Iroh transport with direct/relay selection managed by Iroh;
- Iroh diagnostics in macOS Settings;
- older `RelayClient` retained only as fallback/reference.

### Proven v1 networking

- Mac ↔ Mac cross-network audio worked with one laptop on a phone hotspot and the other on a separate network.
- macOS ↔ NixOS connection by endpoint ID and two-way PTT/audio worked on 2026-09-03.

Known audio issue: occasional brief crackling can occur around PTT start; most audio is otherwise clear. Investigate capture/playback/buffering/device-format boundaries before changing the PCM packet format.

## Add User — `feature/macos-add-user`

The approved V22 Add User flow has been implemented natively in Swift on a branch based on updated `main`.

Current behavior:

- empty dial positions expose the Add User hover/plus treatment;
- status bar changes to `Add someone to Landline` while hovering an empty position;
- clicking an empty position opens the Add/Invite bottom sheet;
- entering a real Iroh endpoint ID and pressing Return uses the existing Iroh connection path;
- the connected peer is assigned to the dial position selected by the user;
- the user's local endpoint ID can be copied from the sheet;
- existing Profile/PTT behavior is preserved.

The Add User branch completed Apple Silicon Release compile/package/signature checks. A real Mac runtime test confirmed the new UI appears and behaves correctly. Actual connection initiated through the new Add User sheet still requires a second user/Mac runtime test.

## Multi-user transport — `feature/macos-multi-user`

This branch is stacked on the Add User branch so the previous two-person checkpoint remains intact.

### Protocol v2

The branch deliberately moves the macOS transport from:

`landline-iroh-audio/1`

to:

`landline-iroh-audio/2`

Protocol v1 remains the proven one-to-one/cross-platform baseline. Protocol v2 is intentionally incompatible with the current NixOS v1 implementation until NixOS parity work begins.

### Group topology

The v2 macOS client now uses a full direct peer mesh rather than a hidden host/relay model:

- each remote endpoint has an independent `PeerSession`/QUIC stream;
- manually adding a peer no longer disconnects existing users;
- membership frames share known endpoint IDs;
- newly discovered peer pairs establish direct sessions using a deterministic initiation rule;
- the product limit remains local user + seven remotes;
- one peer/session failure removes that peer without collapsing the rest of the group;
- local PTT begin/audio/end is broadcast to every connected direct peer;
- a peer joining while local PTT is already held receives the current `pttBegin` state before subsequent audio;
- duplicate simultaneous manual connections deterministically keep the same physical QUIC session on both Macs.

### Group speaker arbitration

Stable behavior targets one effective speaker at a time.

- local PTT is rejected when a known remote speaker already owns the floor;
- if two clients begin before receiving the other's `pttBegin`, the lexicographically lower endpoint ID wins deterministically;
- the losing local client stops capture/talking UI immediately and broadcasts `pttEnd`;
- receivers play audio only from the currently selected speaker session and discard competing packets.

This is distributed collision resolution, not a central floor server. Three-or-more-client runtime testing is required before treating it as proven.

### Build status

The v2 transport, Add User UI and floor-revocation UI hook have completed Apple Silicon arm64 Release builds successfully on `macos-15` GitHub runners. The duplicate-session review fix also completed a successful Release build.

No 3+ client runtime test has yet been performed.

## Linux/NixOS baseline — `linux-nix`

The native Linux client lives under `LandlineNix/` and uses Rust 1.91, Iroh 1.0.2, eframe/egui, CPAL and Rodio.

Current Linux behavior includes:

- same 320 × 672 layout basis and custom window controls;
- shared Landline title/profile/PTT artwork;
- embedded Inter + Inter Tight;
- persistent Iroh endpoint identity;
- protocol v1 one-to-one PTT/audio;
- local profile name/avatar persistence;
- Profile sheet and image selection/drop;
- avatar exchange through v1 Hello/profile payload;
- Nix flake and locked dependency set.

The current `linux-nix` CI baseline is green and real macOS ↔ NixOS v1 audio is proven.

Do not attempt a v2 Mac ↔ v1 Nix connection and interpret failure as a regression: the ALPN difference is intentional. NixOS should move to Add User + v2 group semantics only after macOS group behavior is runtime-proven.

## macOS regressions / outstanding checks

### Traffic-light drift repair

Source repair and Release packaging passed 2026-09-07. A longer real-Mac stability test remains pending for hover/inactive behavior, close/minimize/green button behavior, sleep/display/appearance changes and long-running drift recurrence.

### No-peer PTT

Fixed and runtime-confirmed 2026-09-04. Endpoint-online users can hold PTT with zero peers; capture/VU/talking state remain active while network sends simply have no destinations.

### First microphone permission path

The Swift 6 permission crash is fixed in source using:

`await AVCaptureDevice.requestAccess(for: .audio)`

A first-permission real-Mac re-test after resetting TCC remains pending.

### Packaging

The current macOS distributable target is Apple Silicon arm64, macOS 15+. Pinned `iroh-ffi` 1.1.0 does not provide the required x86_64 macOS slice. Do not label current builds Universal.

Ad-hoc signing is appropriate for test builds, not release notarization.

## UI conventions to preserve

- local user stays at 12 o'clock;
- PTT is press-and-hold;
- no-peer PTT remains allowed while the endpoint is online;
- suppress remote speaking indicators while local user is talking;
- speaking badge uses four centered animated bars in a 24 × 24 green circle;
- status text uses Medium weight;
- muted PTT hover may say `Click to talk` but must not swap the muted icon to active;
- Profile button hover scales the whole 24 px control;
- Profile opens Profile; networking settings belong in Settings/app menu;
- preserve established sheet geometry/hierarchy first;
- macOS traffic lights use caller-owned native standard buttons at the established Figma centres.

## Design reference

Primary Figma prototype reference:

`https://www.figma.com/proto/cbBv0kCV29fX8h2QXbZNDk/SpacesOS-2026?node-id=3911-102362&p=f&viewport=-1105%2C1488%2C0.5&t=zjZbXgJbbsOfVRT9-1&scaling=min-zoom&content-scaling=fixed&starting-point-node-id=3911%3A102362&page-id=3889%3A130618`

For Add User behavior, also inspect the canonical V22 source in `prototypes/app/`.

## Current next step

Runtime-validate protocol v2 with real Macs before bringing NixOS forward:

1. package the current `feature/macos-multi-user` Apple Silicon build;
2. connect two clients through the Add User sheet and confirm the existing two-person behavior remains good;
3. add a third Mac/client and verify all three avatars populate through membership/mesh discovery;
4. verify A → B+C, B → A+C and C → A+B PTT/audio;
5. verify active-speaker badges/status identify the actual speaker on every client;
6. verify one peer quitting/removing network does not tear down the other pair;
7. exercise near-simultaneous PTT and confirm the group converges to one speaker without mixed playback;
8. repeat across separate networks where practical;
9. after macOS group behavior is approved, bring NixOS Add User + protocol v2/group transport to parity and run Mac/Nix group tests.

Do not lose the traffic-light longevity and microphone first-permission regression checks while group work continues.

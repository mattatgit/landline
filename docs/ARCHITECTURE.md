# Landline — Architecture

This document records the current implementation architecture and the intended compatibility relationship between platform clients.

## Repository/platform split

### macOS — `main`

Primary source:

- `LandlineMac/`
- `LandlineMac.xcodeproj/`

Main technologies:

- Swift / SwiftUI
- AppKit for the custom desktop window and backdrop behavior
- AVFoundation / AVAudioEngine for microphone capture and playback support
- Iroh through `IrohLib`

Important source files:

- `LandlineMac/ContentView.swift` — main UI, profile state, PTT interaction and audio/network coordination
- `LandlineMac/LandlineMacApp.swift` — application/window hosting and macOS Settings scene
- `LandlineMac/IrohClient.swift` — active Iroh transport integration
- `LandlineMac/IrohWire.swift` — frame definitions shared with the Linux implementation
- `LandlineMac/MicrophoneCapture.swift` — microphone capture, VU analysis and PCM encoding
- `LandlineMac/RemoteAudioPlayback.swift` — remote PCM playback
- `LandlineMac/IrohSettingsView.swift` — connection/diagnostic Settings UI
- `LandlineMac/RelayClient.swift` — older relay/WebSocket transport retained as fallback/reference, not the current audio path

### Linux/NixOS — `linux-nix`

Primary source:

- `LandlineNix/`
- `flake.nix`
- `flake.lock`

Current stack:

- Rust 2024 / Rust 1.91
- Iroh 1.0.2
- eframe/egui 0.31.1 with Wayland and X11 support
- CPAL 0.15.3 for capture
- Rodio 0.20.1 for playback
- Tokio for async/network tasks
- `rfd`/XDG desktop portal for Linux image-file selection
- `image` for local avatar decoding/cropping/JPEG preparation
- Nix flake for reproducible development/build dependencies

The Linux client is a native port rather than a SwiftUI compatibility layer. Product behavior and the Landline wire protocol are shared; UI/audio implementation is platform-native.

## Iroh connection architecture

The current integration is intentionally one-to-one and uses manual peer discovery.

Each client:

1. loads or creates a persistent Iroh identity;
2. binds an Iroh endpoint;
3. registers the Landline ALPN;
4. exposes its endpoint ID;
5. can connect to another endpoint ID or accept an incoming connection;
6. opens/accepts one bidirectional stream;
7. carries profile, PTT, audio and diagnostic ping/pong frames over that stream.

Iroh chooses the underlying network path. The application should not assume a connection is direct; relay is a valid Iroh-managed path.

The macOS client periodically inspects Iroh path snapshots and exposes temporary diagnostics for selected path, route and latency.

## Participant architecture

The UI model and transport model currently differ by design:

- UI: local participant + seven remote slots.
- Transport: one connected peer.

`IrohClient` publishes seven remote slots so the existing dial does not become transport-specific. The first real peer is inserted into that model while future transport work can expand without replacing the visual participant layout.

## PTT ownership

There is currently no central speaker arbiter in the Iroh path.

For the one-to-one build:

- local PTT is allowed when the local endpoint is ready and the remote peer is not already marked as speaking;
- local microphone capture and talking state may remain active with no peer connected;
- `pttBegin`, audio and `pttEnd` are sent only when a peer/send stream exists;
- remote speaking state blocks local PTT in the current one-to-one arbitration model.

This is sufficient for the current one-to-one proof but should be revisited when transport expands to multiple remote peers or simultaneous connection topologies.

## Audio architecture

### macOS capture

`MicrophoneCapture` uses `AVAudioEngine` and converts the input buffer to:

- mono
- signed 16-bit PCM
- microphone-native sample rate

A bounded mailbox sits between the realtime audio callback and the async network sender so network stalls discard older frames rather than allowing latency to grow indefinitely.

Initial microphone permission is requested through AVFoundation's native async API. This avoids the Swift 6 actor-isolation runtime trap that occurred when the completion-handler API inherited `@MainActor` isolation and was invoked by TCC on a background callback queue.

### Linux capture/playback

The Linux client uses CPAL for microphone capture and Rodio for playback while preserving the same Landline network packet representation. Platform audio-device behavior can differ, so runtime issues such as start-of-PTT transients should be investigated at the capture/playback boundary without changing the wire protocol unless evidence requires it.

### Playback

The receiver parses the audio packet header and schedules/plays the mono PCM at the supplied sample rate. Playback volume is controlled locally.

### Cross-platform rule

Linux must remain byte-compatible with the macOS audio packet format described in `docs/PROTOCOL.md` unless both clients are deliberately versioned together.

Real macOS ↔ NixOS connection and two-way PTT audio have already been proven in runtime testing.

## Profile exchange

The Iroh hello payload carries:

- endpoint ID
- display name
- avatar kind
- optional avatar data

Both macOS and the current Linux parity implementation can send a JPEG avatar encoded as Base64 using the existing `avatarKind = jpeg` / `avatarData` contract. The Linux client centre-crops selected PNG/JPEG images, prepares a compact JPEG representation for persistence/transmission, and renders a local texture for the 12-o'clock avatar.

The Linux receive path now retains remote avatar data and decodes it into a remote avatar texture for display. Full real-desktop confirmation of remote-avatar rendering remains part of the current Linux parity/runtime pass.

## Settings/UI routing architecture

Networking settings and user profile editing remain separate UI concerns.

- macOS exposes Iroh diagnostics/connection controls through the SwiftUI `Settings` scene and normal app menu.
- the undecorated Linux window has no macOS-style global app menu, so the LANDLINE title opens a small in-window app menu containing **Iroh Settings…** and app-level commands.
- the top-right Profile button opens only the Profile sheet on both platforms.

This routing is a platform adaptation, not a transport difference.

## Window/UI architecture

### macOS

The SwiftUI root intentionally uses the full 320 × 672 design area. AppKit provides the window/backdrop surface beneath SwiftUI so an opaque SwiftUI root does not block desktop sampling.

The outer AppKit window is deliberately fixed at 320 × 672. It retains `.resizable` in the style mask so AppKit produces the normal active green native window-control appearance, but `minSize` and `maxSize` are both set to the design size and full-screen behavior is disabled with `.fullScreenNone`.

The macOS traffic lights use caller-owned native standard buttons rather than re-parenting the three instances owned by AppKit's title-bar/theme-frame hierarchy:

- AppKit's window-owned close/minimize/zoom buttons remain in their normal hierarchy and are hidden;
- Landline creates three new native buttons with `NSWindow.standardWindowButton(_:for:)`;
- those buttons are targeted at the Landline window and hosted inside the 64 × 24 Figma control region;
- button centres remain fixed at x=12/32/52 and y=12 inside that host;
- the former `+1/-1` live-window resize nudge, manual `updateTrackingAreas()` calls and `windowDidBecomeMain` repair path have been removed.

This architecture avoids relying on private `_NSThemeFrame` ownership behavior while retaining AppKit-rendered controls. The replacement passed an Apple Silicon Release compile/package/signature validation on 2026-09-07. Real-Mac validation is still required for group-hover appearance, inactive-window appearance, close/minimize/green-button behavior, appearance changes, sleep/wake and long-running traffic-light position stability.

### Linux

The first port uses an undecorated eframe window and custom-painted window controls in the same design region used by the macOS traffic-light backing. Final glass/translucency behavior may need compositor-specific treatment and should not compromise the cross-platform layout contract merely to imitate one desktop environment.

The Linux Profile sheet follows the same 320 × 584 / y=88 geometry and core interaction hierarchy as macOS, while native AppKit-quality backdrop blur remains compositor-specific follow-up work.

## Linux resources and font packaging

Visual assets that are common to the product should be shared from the same supplied artwork rather than redrawn independently on Linux. The current Linux client carries copies of the established LANDLINE title SVG, muted/on PTT SVGs and profile artwork under `LandlineNix/assets/` and renders them through egui image loaders.

Landline should not depend on the host Linux desktop having the design fonts installed. The current Nix build selects Inter and Inter Tight from Nixpkgs/Google Fonts through `flake.nix`. `LandlineNix/build.rs` locates those font files during compilation and copies them into Cargo's build output, where `include_bytes!` embeds them into the executable. egui then registers the embedded font data when the application starts.

The Linux CI workflow explicitly verifies repeated release source builds in the same target tree and also builds the Nix application package, guarding against the earlier generated-font permission issue.

This gives the Linux binary deterministic Landline typography while avoiding a user-level/system-wide font installation requirement. If a future distributable uses an AppImage, Flatpak or another bundle format, the same principle applies: fonts are application resources, not a desktop prerequisite.

## Persistence

Current local persistence includes:

- stable Iroh endpoint identity on both platforms;
- macOS profile name/avatar state;
- Linux profile name plus prepared Base64 JPEG avatar data in the Linux profile store.

Do not replace stable endpoint identity with an ephemeral key without an explicit product/architecture decision: endpoint stability is required for repeatable manual peer testing and may later support a contact model.

## Compatibility priority

When implementing cross-platform changes, priority order is:

1. preserve the existing wire contract or version it deliberately;
2. preserve PTT/audio semantics;
3. preserve stable identity behavior;
4. use native platform audio/window/file-selection APIs appropriately;
5. then pursue visual parity and platform-specific polish.

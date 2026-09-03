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
- `LandlineMac/LandlineMacApp.swift` — application/window hosting
- `LandlineMac/IrohClient.swift` — active Iroh transport integration
- `LandlineMac/IrohWire.swift` — frame definitions shared with the Linux implementation
- `LandlineMac/MicrophoneCapture.swift` — microphone capture, VU analysis and PCM encoding
- `LandlineMac/RemoteAudioPlayback.swift` — remote PCM playback
- `LandlineMac/IrohSettingsView.swift` — temporary connection/diagnostic UI
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

- local PTT is granted immediately if connected and the peer is not already marked as speaking;
- `pttBegin` announces local transmission;
- audio frames follow while the local capture is active;
- `pttEnd` clears the speaking state.

This is sufficient for the current one-to-one proof but should be revisited when transport expands to multiple remote peers or simultaneous connection topologies.

## Audio architecture

### macOS capture

`MicrophoneCapture` uses `AVAudioEngine` and converts the input buffer to:

- mono
- signed 16-bit PCM
- microphone-native sample rate

A bounded mailbox sits between the realtime audio callback and the async network sender so network stalls discard older frames rather than allowing latency to grow indefinitely.

### Playback

The receiver parses the audio packet header and schedules/plays the mono PCM at the supplied sample rate. Playback volume is controlled locally.

### Cross-platform rule

Linux must remain byte-compatible with the macOS audio packet format described in `docs/PROTOCOL.md` unless both clients are deliberately versioned together.

## Profile exchange

The Iroh hello payload currently carries:

- endpoint ID
- display name
- avatar kind
- optional avatar data

macOS can send a JPEG avatar encoded as Base64. The first Linux port exchanges display names but does not yet implement full avatar parity.

## Window/UI architecture

### macOS

The SwiftUI root intentionally uses the full 320 × 672 design area. AppKit provides the window/backdrop surface beneath SwiftUI so an opaque SwiftUI root does not block desktop sampling.

### Linux

The first port uses an undecorated eframe window and custom-painted window controls in the same design region used by the macOS traffic-light backing. Final glass/translucency behavior may need compositor-specific treatment and should not compromise the cross-platform layout contract merely to imitate one desktop environment.

## Linux resources and font packaging

Visual assets that are common to the product should be shared from the same supplied artwork rather than redrawn independently on Linux. The current Linux client carries copies of the established LANDLINE title SVG, muted/on PTT SVGs and profile artwork under `LandlineNix/assets/` and renders them through egui image loaders.

Landline should not depend on the host Linux desktop having the design fonts installed. The current Nix build selects Inter and Inter Tight from Nixpkgs/Google Fonts through `flake.nix`. `LandlineNix/build.rs` locates those font files during compilation and copies them into Cargo's build output, where `include_bytes!` embeds them into the executable. egui then registers the embedded font data when the application starts.

This gives the Linux binary deterministic Landline typography while avoiding a user-level/system-wide font installation requirement. If a future distributable uses an AppImage, Flatpak or another bundle format, the same principle applies: fonts are application resources, not a desktop prerequisite.

## Persistence

Current local persistence includes:

- stable Iroh endpoint identity;
- macOS profile state;
- Linux profile/display-name state as implemented by the first port.

Do not replace stable endpoint identity with an ephemeral key without an explicit product/architecture decision: endpoint stability is required for repeatable manual peer testing and may later support a contact model.

## Compatibility priority

When implementing cross-platform changes, priority order is:

1. preserve the existing wire contract or version it deliberately;
2. preserve PTT/audio semantics;
3. preserve stable identity behavior;
4. use native platform audio/window APIs appropriately;
5. then pursue visual parity and platform-specific polish.

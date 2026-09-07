# Landline

Landline is a desktop peer-to-peer walkie-talkie app with a compact, tactile push-to-talk interface.

The current working macOS baseline combines the established SwiftUI/AppKit Landline UI with Iroh networking. The build lineage was previously called `Landline Iroh Spike V10`; despite that historical name, the source now in `main` is the integrated Landline UI + Iroh implementation rather than the earlier rough transport spike.

## Repository state

Repository: `mattatgit/landline`

Active branches:

- `main` — current macOS baseline and project continuity documentation.
- `linux-nix` — active native Linux/NixOS port, implemented in Rust and kept wire-compatible with the macOS Iroh transport.

Normal development should happen directly from GitHub. ZIP-file exchange is no longer part of the intended workflow.

## Current macOS implementation

The macOS app is in:

- `LandlineMac/`
- `LandlineMac.xcodeproj/`

Current characteristics:

- SwiftUI interface hosted in a custom AppKit window.
- Fixed 320 × 672 Landline window geometry.
- Native macOS glass/backdrop treatment.
- Local user fixed at the 12 o'clock dial position, with seven remote participant slots around the dial.
- Press-and-hold push-to-talk.
- Profile name/avatar persistence.
- Status, volume and VU panels.
- Iroh peer-to-peer transport using a stable persisted endpoint identity.
- Manual peer connection by Iroh endpoint ID.
- Current networking integration is intentionally one-to-one even though the UI preserves the eight-person dial model.
- Direct versus relay path selection is handled by Iroh.
- Temporary Iroh diagnostics expose connection path, latency and traffic information.
- Local PTT can remain active while held even when the endpoint is online but no peer is connected.
- The Swift 6 first-use microphone permission crash has been fixed in source by using AVFoundation's native async permission API.

The earlier WebSocket/relay implementation remains in the source tree as fallback/reference code, but the current UI sends and receives audio through `IrohClient`.

The current distributable pipeline produces an Apple Silicon arm64 macOS 15+ build. It verifies the app icon, ad-hoc signing, ZIP packaging and post-extraction signature integrity. The current pinned Iroh dependency does not provide an x86_64 macOS slice, so this build must not be described as Universal.

The remaining macOS validation item is a real-device re-test of the initial microphone permission path after resetting TCC state.

## Current Linux/NixOS implementation

The native Linux port lives on `linux-nix` in `LandlineNix/`.

It uses:

- Rust 1.91 / Rust 2024
- Iroh 1.0.2
- eframe/egui for the desktop shell
- CPAL for microphone capture
- Rodio for playback
- Nix flakes for the development/build environment

The Linux port currently includes:

- the core 320 × 672 layout and custom window controls;
- shared Landline title/profile/PTT artwork;
- Inter and Inter Tight embedded into the executable from Nixpkgs at build time;
- persistent Iroh endpoint identity;
- one-to-one PTT/audio compatible with the macOS wire protocol;
- local profile name/avatar persistence;
- PNG/JPEG avatar selection and drag/drop;
- Linux avatar JPEG transmission through the existing hello/profile payload;
- received remote avatar data wired through to the Linux UI;
- LANDLINE app menu with Iroh Settings… and Quit;
- Profile button reserved for Profile;
- a Nix flake and locked dependency set.

Real macOS ↔ NixOS interoperability has been proven: connection by Iroh endpoint ID and two-way PTT audio were usable for normal conversation. The latest Linux parity work still needs full real-desktop confirmation for compositor-dependent opacity/theme behavior, sheet shadow, image-upload stability and remote-avatar display.

The current `linux-nix` GitHub Actions workflow is green at branch head and performs repeated release source builds plus a Nix application package build.

## NixOS run path

```sh
git clone https://github.com/mattatgit/landline.git
cd landline
git switch linux-nix
nix develop
cargo run --manifest-path LandlineNix/Cargo.toml
```

## Proven networking milestones

Two important runtime results are already established:

1. Mac ↔ Mac cross-network audio worked with one laptop on a phone hotspot and the other on a separate network.
2. macOS ↔ NixOS connection and two-way PTT audio worked on 2026-09-03.

An occasional brief crackle can occur around PTT start. Most audio is otherwise clear. This should be investigated at capture/playback/buffering boundaries before changing the wire protocol.

## Product versus current transport

The intended Landline product remains an eight-person shared dial:

- local user at 12 o'clock;
- up to seven remote participants.

The current Iroh integration is deliberately one-to-one. That is an integration-stage transport limitation, not a reduction of the intended product model.

## Project context

Project continuity is stored in this repository rather than relying primarily on ChatGPT conversation history.

When starting a new Landline chat, send:

`/context`

The context loader in `CONTEXT.md` tells ChatGPT to read `docs/CURRENT.md`, this README, the durable project documents in `docs/`, relevant source, and recent branch/commit state before continuing.

See:

- `docs/CURRENT.md` — concise active-state record and next step
- `docs/PRODUCT.md` — product intent and behavior
- `docs/ARCHITECTURE.md` — implementation architecture and platform split
- `docs/DESIGN.md` — UI/design conventions and fidelity notes
- `docs/DEVELOPMENT.md` — repository/build/test workflow
- `docs/PROTOCOL.md` — cross-platform Iroh framing/audio compatibility contract

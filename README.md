# Landline

Landline is a desktop peer-to-peer walkie-talkie app with a compact, tactile push-to-talk interface.

The current working macOS baseline combines the established SwiftUI/AppKit Landline UI with Iroh networking. The build lineage was previously called `Landline Iroh Spike V10`; despite that historical name, the source now in `main` is the integrated Landline UI + Iroh implementation rather than the earlier rough transport spike.

## Repository state

Repository: `mattatgit/landline`

Active branches:

- `main` — current macOS baseline and project continuity documentation.
- `linux-nix` — first native Linux/NixOS port, implemented in Rust and kept wire-compatible with the macOS Iroh transport.

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

The earlier WebSocket/relay implementation remains in the source tree as fallback/reference code, but the current UI sends and receives audio through `IrohClient`.

## Current Linux/NixOS implementation

The first Linux port lives on `linux-nix` in `LandlineNix/`.

It uses:

- Rust
- Iroh
- eframe/egui for the desktop shell
- CPAL for microphone capture
- Rodio for playback
- Nix flakes for the development/build environment

The Linux port currently reproduces the core 320 × 672 layout, Iroh identity/connection flow, PTT/audio behavior, profile-name exchange, volume control and Linux window controls. Avatar parity and the final compositor-specific glass treatment remain follow-up work.

The `linux-nix` branch has passed both `cargo check` and a full release binary build inside the repository's Nix development shell. Real NixOS runtime testing and Mac ↔ NixOS interoperability testing are the next validation step.

## NixOS run path

```sh
git clone https://github.com/mattatgit/landline.git
cd landline
git switch linux-nix
nix develop
cargo run --manifest-path LandlineNix/Cargo.toml
```

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

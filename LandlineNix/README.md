# Landline for NixOS — first port

This is the first native Linux/NixOS port of the integrated Landline + Iroh macOS build.

## Current scope

- 320 × 672 Landline desktop shell using the same layout coordinates as the macOS app.
- Custom Linux window controls in the same 64 × 24 top-left backing area used for macOS traffic lights.
- Stable Iroh endpoint identity persisted under the user's local data directory.
- Manual one-to-one peer connection by Iroh endpoint ID.
- Landline wire protocol `landline-iroh-audio/1`, compatible with the current macOS branch.
- Push-to-talk microphone capture using CPAL.
- Remote audio playback and volume control.
- Profile display-name exchange.
- Direct/relay selection remains Iroh-managed, as on macOS.
- Exact shared Landline title, profile and PTT artwork is compiled into the Linux client from the repository assets.
- Inter and Inter Tight are sourced from Nixpkgs at build time and embedded into the executable, so the runtime does not depend on system-installed UI fonts.
- GitHub Actions builds the release client inside the repository's Nix development shell.

Avatar upload/display parity and the final Linux glass treatment are not part of this first compiler/interoperability pass.

## Run on NixOS

```sh
git clone https://github.com/mattatgit/landline.git
cd landline
git switch linux-nix
nix develop
cargo run --manifest-path LandlineNix/Cargo.toml
```

The first `nix develop` resolves the pinned Rust toolchain, Linux GUI/audio libraries, and build-time Inter font sources from the repository's flake. Font data is embedded into the compiled executable by `LandlineNix/build.rs`; no system-wide font installation is required to render the Landline UI.

## Connect to the Mac build

1. Launch Landline on both machines.
2. On Linux, click the **LANDLINE** wordmark to open the temporary Iroh connection panel.
3. Copy the Linux endpoint ID into the macOS Iroh Settings panel, or paste the Mac endpoint ID into the Linux peer field.
4. Connect from either side.
5. Hold the centre PTT button and verify audio in both directions.

The endpoint key is persisted, so the Linux endpoint ID should stay the same between launches.

## Window controls

NixOS does not define one universal titlebar style—the actual convention comes from KDE Plasma, GNOME, Hyprland, etc. For this custom undecorated Landline window the first port uses neutral Linux-style minimize, maximize/restore and close controls, positioned at the exact macOS control centres inside the existing 64 × 24 backing box.

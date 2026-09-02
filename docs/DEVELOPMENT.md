# Landline — Development Workflow

## Source of truth

GitHub is the durable source of truth for implementation files and continuity documentation.

Repository: `mattatgit/landline`

Do not return to ZIP-file exchange as the normal development workflow. If a local build/archive is used temporarily for diagnosis, resulting source changes and decisions should still be committed back into the repository.

## Current branch strategy

The repository currently has two active branches:

- `main` — current macOS working baseline and the canonical continuity documentation.
- `linux-nix` — first native Linux/NixOS port and its CI/build tooling.

There is not yet a formal `develop` branch workflow for Landline. Do not assume the Dialogue branch model applies automatically.

For focused future work, temporary `feature/*` branches or pull requests may be useful, but the intended target branch should be chosen based on platform:

- macOS-only work normally begins from `main`;
- Linux/NixOS work normally begins from `linux-nix` until that port is ready to integrate/restructure;
- wire/protocol changes must be coordinated across both implementations.

## macOS build

Open:

`LandlineMac.xcodeproj`

The source tree under `LandlineMac/` corresponds to the integrated SwiftUI + Iroh baseline previously called Landline Iroh Spike V10.

When changing the macOS app:

1. preserve the established 320 × 672 window geometry unless the design changes;
2. preserve stable Iroh endpoint identity;
3. preserve `docs/PROTOCOL.md` compatibility unless intentionally versioning the protocol;
4. test PTT start/end behavior and remote playback;
5. check profile persistence/exchange when touching hello/profile code;
6. verify glass/window behavior separately from network behavior.

The older `RelayClient` remains as reference/fallback code. Do not accidentally reconnect the main UI to it when changing transport code unless that is the explicit task.

## Linux/NixOS build

From the repository root:

```sh
git switch linux-nix
nix develop
cargo run --manifest-path LandlineNix/Cargo.toml
```

Useful compiler/build checks:

```sh
nix develop --command cargo check --manifest-path LandlineNix/Cargo.toml
nix develop --command cargo build --release --manifest-path LandlineNix/Cargo.toml
```

The Nix flake and Rust lockfile are committed to make builds reproducible.

The `linux-nix` GitHub Actions workflow performs a full release build inside the Nix development shell. Keep that gate working when changing Rust dependencies, Nix libraries or Linux UI/audio code.

## Cross-platform test sequence

When changing transport/audio code, test in increasing order of complexity:

1. compile/build each changed platform;
2. launch and confirm endpoint identity appears;
3. confirm identity persists across relaunch;
4. connect two clients on the same local network;
5. verify PTT/audio in both directions;
6. repeat across separate networks where practical;
7. for cross-platform work, test Mac ↔ NixOS;
8. inspect direct/relay route diagnostics when investigating connectivity/latency.

Avoid changing UI polish and transport fundamentals in the same debugging pass when that would make failures difficult to isolate.

## Linux first-port validation

The first real NixOS test should record:

- NixOS version;
- desktop/compositor (for example Plasma/KWin, GNOME/Mutter, Hyprland);
- Wayland or X11;
- audio stack/device behavior;
- whether microphone capture starts successfully;
- whether playback is audible and volume behaves correctly;
- whether custom minimize/maximize/close controls work;
- whether dragging the undecorated window works;
- stable endpoint ID across relaunch;
- successful/failed Mac ↔ Nix connection;
- PTT/audio direction(s) that work or fail;
- visible route/relay information where available.

Summarize the result in `docs/CURRENT.md` immediately after a meaningful test milestone.

## Protocol changes

`docs/PROTOCOL.md` is the human-readable compatibility contract. Actual source remains authoritative when code and docs conflict.

Before changing any of the following, inspect both platform implementations:

- ALPN;
- frame kinds;
- frame header layout;
- hello JSON fields;
- audio packet layout;
- maximum frame size;
- PTT ordering/semantics.

If a breaking change is required, prefer an explicit protocol-version change rather than silently altering `landline-iroh-audio/1`.

## Documentation maintenance

Update `docs/CURRENT.md` when any of these change:

- latest known working baseline;
- branch purpose/status;
- major architecture decision;
- successful or failed interoperability milestone;
- important known issue;
- agreed next step.

Update durable docs when the underlying decision changes:

- `PRODUCT.md` — product behavior/scope
- `ARCHITECTURE.md` — implementation structure
- `DESIGN.md` — UI/design conventions
- `DEVELOPMENT.md` — build/branch/test workflow
- `PROTOCOL.md` — cross-platform wire contract

`/context` itself is read-only. Do not edit documentation simply because a context load occurred.

## Secrets and generated files

Do not commit private keys, credentials or environment secrets.

The persisted Iroh endpoint identity is application runtime data and should remain in the user's application data location, not in the repository.

Do not commit local build products, Xcode DerivedData, Cargo target output or machine-specific configuration unless deliberately required by a reproducible build workflow.

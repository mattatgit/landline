# Landline — Development Workflow

## Source of truth

GitHub is the durable source of truth for implementation files and continuity documentation.

Repository: `mattatgit/landline`

Do not return to ZIP-file exchange as the normal development workflow. If a local build/archive is used temporarily for diagnosis, resulting source changes and decisions should still be committed back into the repository.

## Current branch strategy

The repository currently has two active branches:

- `main` — current macOS working baseline and the canonical continuity documentation.
- `linux-nix` — active native Linux/NixOS port and its CI/build tooling.

There is not yet a formal `develop` branch workflow for Landline.

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
6. verify glass/window behavior separately from network behavior;
7. when changing microphone permission or capture startup, explicitly test the first-permission path after resetting TCC state.

The older `RelayClient` remains as reference/fallback code. Do not accidentally reconnect the main UI to it when changing transport code unless that is the explicit task.

### Current macOS packaging constraint

The verified downloadable build is Apple Silicon arm64 for macOS 15+.

The current pinned `iroh-ffi` dependency provides an `aarch64-apple-darwin` macOS build but not an x86_64 macOS slice. Do not label or package the current app as Universal unless the Iroh dependency strategy changes or a compatible x86_64 slice is produced separately.

The current Release pipeline verifies the generated app icon, arm64 executable, ad-hoc signature, ZIP packaging and post-extraction signature integrity. Ad-hoc signing is appropriate for test builds but is not a substitute for Developer ID signing and notarization.

### Current microphone-permission regression test

The Swift 6 first-use microphone permission crash is fixed in source. To exercise the original failure path on a real Mac:

```sh
tccutil reset Microphone com.landline.prototype.mac
```

Then launch the current build and verify that the permission prompt appears without a crash, microphone access can be allowed, PTT stays active for the full hold, the VU responds, and subsequent PTT holds behave normally.

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
nix build .#landline -L
```

The Nix flake and Rust lockfile are committed to make builds reproducible.

The current `linux-nix` GitHub Actions workflow performs a full release build inside the Nix development shell, deliberately repeats the release build in the same target tree to catch stale generated-file permission problems, and builds the Nix application package. The latest run at the current branch head is successful.

Keep that gate working when changing Rust dependencies, Nix libraries, generated resources or Linux UI/audio code.

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

Mac ↔ NixOS connection by endpoint ID and two-way PTT audio are already proven. Future transport changes should preserve that working baseline.

Avoid changing UI polish and transport fundamentals in the same debugging pass when that would make failures difficult to isolate.

## Linux runtime/parity validation

The initial NixOS runtime/interoperability milestone has been completed. Real Mac ↔ NixOS two-way audio is proven.

The remaining Linux parity/runtime pass should record:

- NixOS version;
- desktop/compositor;
- Wayland or X11;
- opacity/theme behavior;
- Profile sheet shadow/backdrop behavior;
- image picker and drag/drop stability;
- local avatar persistence after relaunch;
- remote-avatar display from a connected Mac peer;
- custom minimize/maximize/close behavior;
- window dragging behavior;
- any start-of-PTT audio crackle and whether it is capture- or playback-side.

Summarize meaningful results in `docs/CURRENT.md` immediately after each milestone.

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

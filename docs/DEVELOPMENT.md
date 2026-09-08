# Landline — Development Workflow

## Source of truth

GitHub is the durable source of truth for implementation files, browser prototypes and continuity documentation.

Repository: `mattatgit/landline`

Do not return to ZIP-file exchange as the normal development workflow. If a local build/archive is used temporarily for diagnosis, resulting source changes and decisions should still be committed back into the repository.

## Prototype-first UI workflow

For new UI flows, use this sequence unless the task is explicitly a native-only fix:

1. explore/design the interaction in Figma or discussion;
2. implement and test it in the browser prototype;
3. agree the behavior and visual treatment;
4. implement the approved flow in the macOS app;
5. runtime-test the macOS implementation;
6. implement Linux/NixOS parity;
7. run cross-platform validation where networking/shared state is involved.

Repository locations:

- `prototypes/app/` — canonical full browser prototype and the executable interaction reference for approved new flows before native implementation;
- `prototypes/experiments/` — small isolated tests for a specific visual/interaction question.

An experiment is not automatically canonical. Once accepted, integrate the result into `prototypes/app/` or explicitly record the approved decision.

Keep prototypes lightweight. Prefer plain HTML/CSS/JavaScript while sufficient; do not add React, Vite, npm or another build stack unless a real prototype requirement justifies it.

When implementing a UI flow natively, inspect the relevant current Figma frame and canonical web prototype rather than reconstructing behavior from chat memory.

## Current branch strategy

The repository currently has two long-lived platform branches:

- `main` — current macOS working baseline, canonical web prototype workspace and canonical continuity documentation.
- `linux-nix` — active native Linux/NixOS port and its CI/build tooling.

There is not a formal `develop` branch. Focused work may use temporary `feature/*`, `fix/*` or `chore/*` branches and pull requests.

For current work:

- prototype and macOS changes normally begin from `main`;
- Linux/NixOS work normally begins from `linux-nix` until the Linux source is integrated/restructured;
- wire/protocol changes must be coordinated across both implementations.

A later cleanup may place `LandlineNix/` on `main` beside `LandlineMac/` and `prototypes/`. Do not make that restructuring a prerequisite for ordinary product work while the current branch setup remains functional.

## macOS build

Open:

`LandlineMac.xcodeproj`

`LandlineMac/` contains source/resources; `LandlineMac.xcodeproj/` is Xcode's directory-bundle project metadata and build configuration. Both are normal parts of the macOS project.

The source tree under `LandlineMac/` corresponds to the integrated SwiftUI + Iroh baseline previously called Landline Iroh Spike V10.

When changing the macOS app:

1. inspect any approved prototype/Figma reference for the flow first;
2. preserve the established 320 × 672 window geometry unless the design changes;
3. preserve stable Iroh endpoint identity;
4. preserve `docs/PROTOCOL.md` compatibility unless intentionally versioning the protocol;
5. test PTT start/end behavior and remote playback when the touched code can affect them;
6. check profile persistence/exchange when touching hello/profile code;
7. verify glass/window behavior separately from network behavior;
8. when changing microphone permission or capture startup, explicitly test the first-permission path after resetting TCC state.

The older `RelayClient` remains as reference/fallback code. Do not accidentally reconnect the main UI to it unless that is the explicit task.

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

Useful checks:

```sh
nix develop --command cargo check --manifest-path LandlineNix/Cargo.toml
nix develop --command cargo build --release --manifest-path LandlineNix/Cargo.toml
nix build .#landline -L
```

The Nix flake and Rust lockfile are committed to make builds reproducible. Keep the Linux GitHub Actions release/Nix build gate working when changing Rust dependencies, Nix libraries, generated resources or Linux UI/audio code.

When bringing an approved macOS feature to Linux, match behavior and hierarchy first, then adapt platform-specific window/glass/file-picker details appropriately rather than forcing AppKit behavior onto Linux.

## Cross-platform test sequence

When changing transport/audio/shared state, test in increasing order of complexity:

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

## Protocol changes

`docs/PROTOCOL.md` is the human-readable compatibility contract. Actual source remains authoritative when code and docs conflict.

Before changing ALPN, frame kinds/header layout, hello fields, audio packet layout, maximum frame size or PTT ordering/semantics, inspect both platform implementations. If a breaking change is required, prefer an explicit protocol-version change rather than silently altering `landline-iroh-audio/1`.

## Documentation maintenance

Update `docs/CURRENT.md` when any of these change:

- latest known working baseline;
- canonical prototype state or approved flow awaiting native implementation;
- branch purpose/status;
- major architecture decision;
- successful or failed interoperability milestone;
- important known issue;
- agreed next step.

Update durable docs when the underlying decision changes:

- `PRODUCT.md` — product behavior/scope
- `ARCHITECTURE.md` — implementation structure
- `DESIGN.md` — UI/design conventions
- `DEVELOPMENT.md` — prototype/build/branch/test workflow
- `PROTOCOL.md` — cross-platform wire contract

`/context` itself is read-only. Do not edit documentation simply because a context load occurred.

## Secrets and generated files

Do not commit private keys, credentials or environment secrets.

The persisted Iroh endpoint identity is application runtime data and should remain in the user's application data location, not in the repository.

Do not commit local build products, Xcode DerivedData, Cargo target output, `node_modules` or machine-specific configuration unless deliberately required by a reproducible build workflow.

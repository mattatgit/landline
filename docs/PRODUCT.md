# Landline — Product

## Purpose

Landline is a desktop peer-to-peer walkie-talkie app designed to make short, low-friction voice communication feel more like a physical radio than a conventional calling app.

The core interaction is deliberately simple: see who is available, hold the central push-to-talk control, speak, release it, and listen.

## Product principles

- **Immediate** — the main communication action should be available without navigating through call setup flows.
- **Tactile** — press-and-hold PTT should feel like operating a physical control.
- **Ambient** — people can remain visible in the dial without a conventional ringing/call-session metaphor.
- **Small-group first** — the interface is designed around a compact dial with one local user and up to seven remote positions.
- **Peer-to-peer where possible** — connectivity should not require all audio to pass through an application-owned central server when Iroh can establish direct or relayed peer connectivity.
- **Visually restrained** — the product uses a compact custom desktop window, translucent/glass surfaces, a small number of controls and strong state cues.

## Participant model

The intended interface model is eight positions total:

- local user permanently at 12 o'clock;
- seven remote participant positions around the circular dial.

The current Iroh implementation is intentionally one-to-one, so only one real remote peer is populated today. The seven-slot UI model is retained so transport work can expand later without redesigning the fundamental interface.

## Core interaction

### Push to talk

- PTT is press-and-hold, not toggle-to-talk.
- The centre control represents the local microphone state.
- The local user should not begin a transmission while a connected remote peer is already speaking in the current one-to-one implementation.
- Releasing PTT ends transmission promptly.
- Only one active-speaker indicator should be shown at a time in the current UI.

### Presence and speaking state

- The local profile occupies the 12 o'clock position.
- Real connected peers populate remaining dial positions.
- Speaking is indicated with a green circular badge containing animated audio bars.
- Empty positions remain visually distinct from active participants.

### Status

The status area communicates contextual state such as:

- ready / waiting for peer;
- muted;
- hover hint such as `Click to talk`;
- local speaking state;
- remote speaking state;
- connection or error state.

Status copy should remain concise and should not use arbitrary mixed font weights unless the design explicitly requires it.

### Volume and meter

- Remote playback volume is controlled locally.
- The VU meter gives feedback while transmitting.
- Existing green/orange/red VU zones are separate from broader interface colors and should remain visually stable unless the design changes.

## Profile

The local user can create/edit a simple profile including:

- display name;
- avatar image or default avatar treatment.

The macOS implementation persists profile information and sends the current profile to the connected peer through the Iroh hello message.

## Connectivity model

Current connection setup is intentionally manual for the technical integration phase:

- each client has a stable Iroh endpoint ID;
- one peer's endpoint ID is entered into the other client;
- Iroh handles the path, including direct connectivity or relay when required.

Manual endpoint-ID entry is not necessarily the final consumer-facing discovery/onboarding experience. It exists to prove transport and cross-platform interoperability before a more polished contact/discovery model is designed.

## Platform direction

Current platforms under active development:

- macOS — primary working implementation in SwiftUI/AppKit.
- Linux/NixOS — native Rust port on `linux-nix`.

The platform implementations should preserve the same product behavior and wire protocol while using appropriate native UI/audio technologies for each operating system.

## Current versus future scope

Current technical milestone:

- prove reliable peer connection and two-way PTT audio across networks and platforms while preserving the established Landline UI.

Likely later product work includes:

- multiple simultaneous remote participants rather than the current one-to-one transport;
- a user-friendly contact/discovery/invite flow instead of manual endpoint IDs;
- stronger cross-platform visual parity;
- polished packaging/install/update flows;
- persistence/sync decisions for contacts and identity beyond the current local profile/endpoint persistence.

Do not treat these later items as already-decided implementation details unless they are recorded in `docs/CURRENT.md` or a newer project decision.

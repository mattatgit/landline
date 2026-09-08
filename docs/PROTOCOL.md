# Landline — Iroh Wire Protocol

This document is the human-readable compatibility contract between Landline platform implementations.

The source code remains authoritative. If this document and the implementation disagree, inspect both clients before making further changes and then update this file.

## Versions / ALPNs

### Protocol v1 — proven one-to-one baseline

ALPN:

`landline-iroh-audio/1`

Protocol v1 is the proven Mac ↔ Mac and macOS ↔ NixOS one-to-one baseline. Keep it as the historical compatibility reference while multi-user work is validated.

### Protocol v2 — multi-user group branch

ALPN:

`landline-iroh-audio/2`

The macOS `feature/macos-multi-user` branch uses v2. It keeps the proven v1 frame layout, hello payload, PTT/audio packet formats and ping/pong encoding, while adding group membership and a direct peer mesh.

A v2 macOS build is intentionally not wire-compatible with the current v1 NixOS client. Linux/NixOS must be moved to v2 before cross-platform group testing.

## Transport

Each peer pair uses one bidirectional Iroh/QUIC stream. Profile, membership, control and audio frames share that stream and are separated by a small application-level frame header.

Protocol v1 has one remote session at a time.

Protocol v2 supports up to seven remote sessions. Group members form a full direct mesh: every participant establishes an Iroh session to every other participant rather than routing group audio through a hidden host.

This means:

- local PTT/audio is broadcast to every direct peer session;
- a remote speaker's packets arrive on that speaker's own session, so speaker identity does not need to be wrapped into every audio packet;
- one peer disconnecting removes only that peer;
- once the mesh is established, the group does not depend on the user who originally introduced members.

## Frame layout

Each Landline frame is:

```text
byte 0      message kind (UInt8)
bytes 1-4   payload length (UInt32 little-endian)
bytes 5...  payload bytes
```

Header size: 5 bytes.

Maximum payload size: 256 KiB.

## Message kinds

Values 1–6 are unchanged from v1. Protocol v2 adds value 7.

| Value | Kind | Payload |
| ---: | --- | --- |
| 1 | `hello` | UTF-8 JSON profile object |
| 2 | `pttBegin` | empty |
| 3 | `audio` | Landline PCM audio packet |
| 4 | `pttEnd` | empty |
| 5 | `ping` | UInt64 little-endian nonce |
| 6 | `pong` | same UInt64 nonce |
| 7 | `membership` | UTF-8 JSON endpoint-ID list; v2 only |

Do not reorder or reuse existing numeric values inside a protocol version.

## Hello payload

The hello JSON object is unchanged in v2:

```json
{
  "endpointId": "<iroh endpoint id>",
  "name": "<display name>",
  "avatarKind": "default | jpeg",
  "avatarData": "<optional base64 JPEG>"
}
```

Behavior:

- `endpointId` identifies the peer and is also persisted locally through the client's Iroh secret key;
- `name` is normalized by the receiving client;
- `avatarKind = "jpeg"` means `avatarData` contains a Base64 JPEG;
- default-avatar state uses `avatarKind = "default"` and no image bytes;
- the macOS sender renders custom avatars to a 128 × 128 JPEG before Base64 encoding;
- both sides send their current hello when a connection is installed.

## v2 membership payload

Protocol v2 adds:

```json
{
  "endpointIds": [
    "<endpoint id 1>",
    "<endpoint id 2>"
  ]
}
```

The list contains the sender's current known group membership, capped at the eight-person product size.

When a client learns a previously unknown endpoint ID, the two peers use a deterministic initiation rule for automatically discovered mesh edges: the lexicographically lower endpoint ID initiates the Iroh connection. This prevents both sides from creating the same automatic mesh edge simultaneously.

If two users manually initiate the same peer pair at nearly the same time, both clients deterministically keep the same physical QUIC connection: the lower endpoint ID's outbound session.

Membership is rebroadcast when peers join or leave so the mesh converges without a permanent host.

## PTT sequence

Normal transmission sequence on each peer session is unchanged:

```text
pttBegin
zero or more audio frames
pttEnd
```

In v2, a local transmission broadcasts that sequence to every connected peer session.

The macOS client may still enter local capture/talking state when its Iroh endpoint is ready but zero peers are connected. No network frames are emitted in that case.

### v2 speaker arbitration

Stable group behavior allows one effective speaker at a time.

A client will not start local PTT while it already knows a remote speaker is active. If two clients begin close enough together that neither has yet received the other's `pttBegin`, all v2 macOS clients use the same deterministic tie-break: the lexicographically lower endpoint ID wins the floor.

A losing local sender stops local transmit/capture and broadcasts `pttEnd`. Receivers accept audio only from the currently selected speaker session and ignore competing audio frames.

This is a distributed collision-resolution rule, not a centralized floor server. Runtime testing with three or more real clients remains required before treating it as fully proven group arbitration.

## Audio packet format

The payload of an `audio` frame remains:

```text
bytes 0-3   sampleRate (UInt32 little-endian)
bytes 4-7   frameCount (UInt32 little-endian)
bytes 8...  mono signed 16-bit PCM samples
```

Current audio properties:

- mono;
- signed Int16 PCM;
- little-endian sample representation on the current targets;
- sample rate supplied per packet;
- macOS source uses the microphone's native input sample rate.

The receiver validates the header/sample count before playback and plays/resamples as required by its native audio stack.

Mac ↔ Mac cross-network audio and macOS ↔ NixOS two-way PTT/audio are proven using protocol v1. Protocol v2 multi-user audio is compile-validated on macOS but not yet runtime-proven with three or more clients.

## Realtime / latency behavior

The macOS capture path uses a bounded queue between the realtime audio callback and network sending. If networking falls behind, older frames are dropped instead of allowing an ever-growing latency backlog.

In v2, each captured network frame is written to every current direct peer session. A failure writing to one peer removes only that peer session and does not collapse local PTT or other group connections.

An occasional brief crackle has been observed around PTT start in the v1 baseline. Treat capture start, playback start/buffering and device-format negotiation as the first investigation areas before changing the audio packet format.

## Ping / pong

`ping` and `pong` carry an 8-byte UInt64 nonce in little-endian order.

In v2, the temporary macOS Settings diagnostics measure application RTT against one selected peer session rather than all group peers simultaneously. Global byte counters aggregate traffic across the group.

## Iroh path behavior

The Landline wire protocol does not encode whether a connection is direct or relayed.

Direct/relay selection is Iroh-managed independently for each peer pair. Control/audio behavior should be identical on either route.

## Compatibility checklist

Before changing the protocol, compare all active platform implementations for:

- exact ALPN bytes;
- 5-byte frame header;
- UInt32 payload-length endianness;
- message-kind numeric values;
- hello JSON field names/types;
- v2 membership JSON field names/types;
- audio sample-rate/frame-count header;
- signed 16-bit mono PCM representation;
- PTT begin/audio/end ordering;
- group speaker-arbitration semantics;
- ping/pong UInt64 encoding;
- maximum payload assumptions.

Record intentional incompatibility or a version transition in `docs/CURRENT.md` before relying on it during cross-platform testing.

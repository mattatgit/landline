# Landline — Iroh Wire Protocol

This document is the human-readable compatibility contract between Landline platform implementations.

The source code remains authoritative. If this document and the implementation disagree, inspect both clients before making further changes and then update this file.

## Version / ALPN

Current ALPN:

`landline-iroh-audio/1`

A breaking framing/audio/control change should normally use a new protocol version rather than silently changing the semantics of `/1`.

## Transport

Landline uses one bidirectional Iroh/QUIC stream in the current one-to-one integration.

Profile/control/audio frames share that stream and are separated by a small application-level frame header.

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

Current numeric values:

| Value | Kind | Payload |
| ---: | --- | --- |
| 1 | `hello` | UTF-8 JSON profile object |
| 2 | `pttBegin` | empty |
| 3 | `audio` | Landline PCM audio packet |
| 4 | `pttEnd` | empty |
| 5 | `ping` | UInt64 little-endian nonce |
| 6 | `pong` | same UInt64 nonce |

Do not reorder/reuse these numeric values inside protocol version 1.

## Hello payload

Both current platform implementations use a JSON object with these fields:

```json
{
  "endpointId": "<iroh endpoint id>",
  "name": "<display name>",
  "avatarKind": "default | jpeg",
  "avatarData": "<optional base64 JPEG>"
}
```

Current behavior:

- `endpointId` identifies the peer and is also persisted locally through the client's Iroh secret key.
- `name` is normalized by the receiving client.
- `avatarKind = "jpeg"` means `avatarData` contains a Base64 JPEG.
- default-avatar state uses `avatarKind = "default"` and no image bytes.
- the macOS sender renders custom avatars to a 128 × 128 JPEG before Base64 encoding.
- the Linux client can persist and send its prepared JPEG avatar using the same fields.
- the Linux receive path now retains remote avatar data and decodes it for UI display.

Both sides send their current hello when a connection is installed so either connection direction populates the peer UI.

Full real-desktop confirmation of Linux remote-avatar presentation remains a UI/runtime validation task, not a protocol gap.

## PTT sequence

Normal connected-peer transmission sequence:

```text
pttBegin
zero or more audio frames
pttEnd
```

In the current one-to-one application behavior, a client should not begin local PTT while the connected peer is already marked as transmitting.

The macOS client may still enter local capture/talking state when its Iroh endpoint is ready but no peer is connected. In that state no PTT or audio frames are emitted because there is no peer stream. This is an application-state behavior and does not alter the on-wire sequence above.

A future multi-peer speaker-arbitration mechanism may need a protocol extension/version change; do not infer that the current one-to-one local rule is sufficient for eight active peers.

## Audio packet format

The payload of an `audio` frame is:

```text
bytes 0-3   sampleRate (UInt32 little-endian)
bytes 4-7   frameCount (UInt32 little-endian)
bytes 8...  mono signed 16-bit PCM samples
```

Current audio properties:

- mono
- signed Int16 PCM
- little-endian sample representation on the current targets
- sample rate supplied per packet
- macOS source uses the microphone's native input sample rate

The receiver should validate the header/sample count before playback and play/resample as required by its native audio stack.

Mac ↔ Mac cross-network audio and macOS ↔ NixOS two-way PTT/audio have both been proven using protocol version 1.

## Realtime/latency behavior

The macOS capture path uses a bounded queue between the realtime audio callback and network sending. If networking falls behind, older frames are dropped instead of allowing an ever-growing latency backlog.

Cross-platform implementations should preserve that low-latency principle even if their audio buffering implementation differs.

An occasional brief crackle has been observed around PTT start. Treat capture start, playback start/buffering and device-format negotiation as the first investigation areas before changing the protocol.

## Ping/pong

`ping` and `pong` carry an 8-byte UInt64 nonce in little-endian order.

The application uses this to measure application-level RTT over the exact framed stream used for PTT/audio. This is separate from Iroh's path RTT diagnostics.

## Iroh path behavior

The Landline wire protocol does not encode whether the connection is direct or relayed.

Direct/relay selection is Iroh-managed. Clients may expose path diagnostics, but control/audio behavior should be identical on either route.

## Compatibility checklist

Before changing the protocol, compare macOS and Linux implementations for:

- exact ALPN bytes;
- 5-byte frame header;
- UInt32 payload length endianness;
- message-kind numeric values;
- hello JSON field names/types;
- audio sample-rate/frame-count header;
- signed 16-bit mono PCM representation;
- PTT begin/audio/end ordering;
- ping/pong UInt64 encoding;
- maximum payload assumptions.

Record any intentional incompatibility or version transition in `docs/CURRENT.md` before relying on it during cross-platform testing.

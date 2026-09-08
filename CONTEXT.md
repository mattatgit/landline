# Landline — Context Loader

This file defines the standard context-loading workflow for ChatGPT conversations about Landline.

## Shortcut

When the user's entire message is `/context`, load the current Landline project context from this repository before continuing.

Do not ask the user to restate project history that is already recorded here.

## Load order

1. Read `docs/CURRENT.md` first. Treat it as the concise continuity record and the primary statement of the current next step.
2. Read `README.md`.
3. Read the durable project documents:
   - `docs/PRODUCT.md`
   - `docs/ARCHITECTURE.md`
   - `docs/DESIGN.md`
   - `docs/DEVELOPMENT.md`
   - `docs/PROTOCOL.md`
4. If the task concerns a UI flow or interaction that has been prototyped, inspect `prototypes/README.md` and the relevant source under `prototypes/app/` before changing native code. Use `prototypes/experiments/` only when an isolated experiment is directly relevant.
5. Inspect the current `main` source relevant to the next task.
6. If the task concerns Linux/NixOS or cross-platform interoperability, inspect the current `linux-nix` branch as well.
7. Check recent commits, branch heads and relevant CI state when necessary to understand changes made after the documentation was last updated.
8. If a current Figma frame is material to the task, use the Figma design as the visual source of truth rather than inferring intent from an older implementation screenshot.

## Current branch meaning

- `main` — current macOS working baseline plus canonical project continuity documentation and canonical web prototypes.
- `linux-nix` — active native Linux/NixOS port.

Do not assume one branch supersedes the other: they currently represent platform implementations that are expected to remain wire-compatible.

The preferred product-development sequence for new UI work is web prototype → macOS implementation/runtime validation → Linux/NixOS parity. This does not mean the browser prototype is a production Landline client; it is the executable interaction reference used before native implementation.

## Ground rules

- GitHub is the source of truth for implementation files.
- `docs/CURRENT.md` is the short continuity record, not a substitute for inspecting source when implementation details matter.
- Figma is the source of truth for intended visual design where a current design exists.
- For an approved new UI flow, the canonical browser implementation under `prototypes/app/` is the executable interaction reference to inspect before changing native clients.
- An isolated prototype under `prototypes/experiments/` does not become canonical behavior until its accepted result is integrated into `prototypes/app/` or otherwise recorded as an approved decision.
- `docs/PROTOCOL.md` records the cross-platform compatibility contract, but actual macOS/Linux source must be checked before changing the wire format.
- Update `docs/CURRENT.md` when a meaningful milestone, technical decision, known issue, working baseline or next step changes.
- Update the durable documents when their underlying product/design/architecture/development/protocol decisions change.
- Do not rely on chat memory as the primary project record. Chat/project history may supplement the repository but should not override newer repository evidence.
- Do not invent missing project history or prototype source. If the repository documentation/source does not support something, say so.
- Do not modify files merely because `/context` was invoked. Context loading is read-only unless the user also asks for a change.
- Do not reintroduce ZIP-file handoffs as the normal source workflow; work from the repository unless there is a specific diagnostic reason not to.

## Response after loading

Reply concisely with:

- confirmation that Landline context is loaded;
- the current web-prototype state when relevant;
- the current macOS implementation/baseline;
- the current Linux/NixOS implementation state when relevant;
- the current next step recorded in `docs/CURRENT.md`;
- any important mismatch between the documentation, branch heads, CI state or current source.

After that, continue normally with the user's request.

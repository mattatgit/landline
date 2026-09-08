# Landline Web Prototypes

This directory is the canonical repository home for Landline's browser-based interaction prototypes.

## Role in the product workflow

For new UI flows, the normal implementation sequence is:

1. design/idea in Figma or discussion;
2. implement and test the interaction in a web prototype;
3. agree the behavior and visual treatment;
4. implement the approved flow in the macOS app;
5. runtime-test the macOS implementation;
6. bring the Linux/NixOS app to behavioral and visual parity;
7. run cross-platform validation when networking or shared state is involved.

The web prototype is therefore a design-validation implementation, not a production web version of Landline.

## Structure

- `app/` — the canonical full Landline web prototype. When a feature has been integrated here, this is the browser prototype to inspect before implementing the same flow natively.
- `experiments/` — small, focused prototypes used to validate an isolated interaction, visual detail or platform behavior without loading the complete app prototype.

## Prototype principles

- Prefer plain HTML, CSS and JavaScript while that remains sufficient.
- Do not add a framework/build system merely for convenience; introduce one only when the prototypes genuinely require it.
- Use supplied Figma/exported artwork where available rather than approximating distinctive assets.
- Keep the canonical prototype runnable with minimal setup.
- Record important approved interaction decisions in the relevant prototype README and durable project docs.
- Do not treat an experiment as the canonical app behavior until its result has been accepted and integrated into `app/`.

## Source of truth

For visual intent, current Figma frames remain the primary design source of truth. The web prototype is the primary executable interaction reference for an approved flow before native implementation.

When the web prototype and an older native implementation differ because a new flow is being developed, inspect the prototype and current Figma design before changing native code.

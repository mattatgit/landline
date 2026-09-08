# Canonical Landline Web Prototype

This directory contains the current full browser prototype used to validate Landline UI flows before they are implemented in the native clients.

## Current version

**LANDLINE browser prototype V22** is the canonical prototype currently stored here.

V22 is based on the established V21 browser prototype and adds the approved **Add Users** flow while retaining the existing profile, PTT, status, volume, VU and avatar interactions.

Open `index.html` directly in a modern browser.

## V22 Add Users flow

- Hover any empty dial slot to reveal the 56 px add-user state and the `Add someone to Landline` status message.
- Click an empty slot to open the Add / Invite sheet.
- The **Add someone** section accepts a Landline ID.
- Press Return after entering an ID to populate the selected slot with a prototype contact and close the sheet.
- The **Invite someone** section shows the local user's six-word Landline ID.
- **Copy Landline ID** copies that ID, briefly shows `Copied`, then closes the sheet.

`README.txt` is retained as the source notes supplied with V22, and `ASSET-SOURCES.txt` records prototype asset provenance.

## Structure

The prototype is deliberately lightweight and self-contained:

- `index.html` — markup, prototype state and interaction logic
- `styles.css` — layout and visual styling
- `assets/` — local SVG and PNG assets
- `README.txt` — supplied version notes
- `ASSET-SOURCES.txt` — asset-source notes

No package manager, build step, framework, CDN or external runtime dependency is required.

## Feature handoff

For new Landline UI work:

1. design/idea is explored and validated in the web prototype;
2. approved behavior is recorded here when it is not obvious from the interaction itself;
3. implement the approved behavior in `LandlineMac/`;
4. runtime-test it on macOS;
5. implement corresponding Linux/NixOS parity work;
6. validate cross-platform behavior where applicable.

The **Add Users** flow is the first feature using this prototype → macOS → NixOS handoff workflow.

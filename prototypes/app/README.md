# Canonical Landline Web Prototype

This directory contains the current full browser prototype used to validate Landline UI flows before they are implemented in the native clients.

## Status

The directory structure is now canonical, but the latest existing Landline web prototype has not yet been imported into GitHub because its source files are not present in the repository or in the currently available source archive.

Do not recreate that prototype from memory or from screenshots alone. Import the actual latest prototype source, then use this directory as the durable reference going forward.

## Expected lightweight structure

While plain web technologies remain sufficient, prefer:

- `index.html`
- `styles.css`
- `app.js`
- `assets/`

A different structure is acceptable if the real prototype already uses one; preserving the working prototype is more important than forcing a rename.

## Feature handoff

Once a new interaction is approved here:

1. record any non-obvious behavior in this README or a feature note;
2. implement it in `LandlineMac/`;
3. validate it on macOS;
4. implement corresponding parity work in `LandlineNix/` when that source is integrated/current for the task.

The current Add User flow should be the first feature imported and handed off through this workflow.

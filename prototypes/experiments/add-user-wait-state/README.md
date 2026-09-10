# Add User wait-state experiment

This isolated prototype tests the revised Add User flow before it is integrated into the canonical browser prototype under `prototypes/app/`.

## Interaction

1. Hover any empty dial slot and click it.
2. The revised Figma Add / Invite sheet opens.
3. Enter any non-empty Landline ID. The **Add to Landline** button becomes active.
4. Click **Add to Landline** (or press Return).
5. The sheet slides down and the selected slot shows the 48 px blue graduated-outline wait ring.
6. The ring rotates continuously while the connection is simulated.
7. After 2.2 seconds, the ring is replaced by the prototype contact avatar.

The wait-ring stroke uses the two colours read directly from Figma node `4171:55829` (`#1286B6` → `#096286`) at a 2 px stroke width. Only the gradient ring rotates; the dial slot remains fixed.

This experiment is not yet canonical product behavior. Once the interaction and timing are approved, fold it into `prototypes/app/` and update the canonical prototype documentation.

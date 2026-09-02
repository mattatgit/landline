# Landline — Context Loader

This file defines the standard context-loading workflow for ChatGPT conversations about Landline.

## Shortcut

When the user sends `/context`, load the current project context from this repository before continuing.

Do not ask the user to restate project history that is already recorded in the repository or current ChatGPT Project context.

## Load order

1. Read `docs/CURRENT.md` if it exists. Treat it as the concise continuity record.
2. Read `README.md` if it exists.
3. Read other files in `docs/` if that directory exists.
4. Inspect the current source tree and the files relevant to the next task.
5. Check recent commits or branch state when necessary to understand the latest implementation.

## Ground rules

- GitHub is the source of truth for implementation files.
- Figma is the source of truth for intended visual design where a Figma design exists.
- Do not rely on chat memory as the primary project record.
- Do not invent missing product history or decisions. If continuity documentation has not yet been established for Landline, say so and use only what the repository and current Project context support.
- Do not modify files merely because `/context` was invoked. Context loading is read-only unless the user also asks for a change.

## Response after loading

Reply concisely with:

- confirmation that context is loaded;
- the current implementation/state supported by the repository;
- the recorded next step, if one exists;
- any important missing or stale continuity documentation.

After that, continue normally with the user's request.

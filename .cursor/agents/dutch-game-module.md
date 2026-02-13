---
name: dutch-game-module
description: Limits context to the Dutch game module in Dart backend and Flutter app. Use when the user wants answers, edits, or searches restricted to Dutch game code—e.g. game logic, UI, state, or shared code in dart_bkend_base_01 or flutter_base_05.
---

You operate with **context limited to the Dutch game module** in two directories:

- `dart_bkend_base_01/lib/modules/dutch_game/`
- `flutter_base_05/lib/modules/dutch_game/`

## Scope rules

1. **Read only** from paths under those two directories (and their subdirectories). Do not read core managers, other modules, or files outside the Dutch game module unless the user explicitly asks you to reference a specific file elsewhere.

2. **Search only** within those paths when using search or grep. Target directories for all searches: `dart_bkend_base_01/lib/modules/dutch_game/` and `flutter_base_05/lib/modules/dutch_game/` (or a subpath the user specifies).

3. **Base answers only** on content found in the Dutch game module. If the answer depends on core managers, base classes, or other modules, say so and suggest switching to full-context or referencing the specific file the user needs.

4. **Edits**: Only create or modify files under the two Dutch game paths above. Do not change files outside the Dutch game module.

## When invoked

1. Confirm you are in Dutch-game-module mode (context limited to the two paths above).
2. List or explore the Dutch game module structure if relevant (backend_core, screens, widgets, managers, utils, etc.).
3. Use only files under `dart_bkend_base_01/lib/modules/dutch_game/` and `flutter_base_05/lib/modules/dutch_game/` for reading, searching, and reasoning.
4. If the user asks to "limit context to Dutch game" or to those paths, you are already in that mode—proceed under these rules.

## Out of scope

- Do not pull in or summarize code from core managers (`lib/core/`), other modules, or non–Dutch-game paths unless the user explicitly requests a specific file by path.
- If the task requires codebase-wide context (e.g. module registration, app entry point), say so and suggest running the request without this agent or in the main chat.

Stay strictly within the two Dutch game module directories for all context and edits.

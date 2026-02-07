# Lottie Animations (Flutter Base 05)

This document describes how Lottie animations are used in the app, how to add or replace them, and how the winner trophy Lottie was fixed when it failed to parse due to missing composition metadata.

---

## Overview

- **Package**: [lottie](https://pub.dev/packages/lottie) (Dart/Flutter Lottie player).
- **Current use**: Winner celebration on the **Game Ended** modal when the current user wins. A Lottie (or fallback trophy icon) is shown inside the modal just above the players list.
- **Asset**: `assets/lottie/winner01.lottie` (sourced from [LottieFiles](https://app.lottiefiles.com)).

---

## Asset Setup

- **Location**: Place `.lottie` or `.json` Lottie files under `flutter_base_05/assets/lottie/`.
- **pubspec.yaml**: The folder is declared so all files are included:

  ```yaml
  flutter:
    assets:
      - assets/lottie/
  ```

- **Loading in code**: Use `Lottie.asset('assets/lottie/your_file.lottie', ...)` or, for `.lottie` (dotlottie) archives, the custom decoder described below.

---

## .lottie (DotLottie) Format

A `.lottie` file is a **ZIP archive** containing:

- **manifest.json** – DotLottie manifest (version, list of animations).
- **One or more JSON files** – The actual Lottie composition(s), e.g. `a/Main Scene.json`.

The `lottie` package can decode this via `LottieComposition.decodeZip()`, but you must choose **which** JSON to use (the first `.json` in the archive is not always the main animation). In this project we use a **custom decoder** that picks the first `.json` in the file list; repacking the zip with the **animation JSON first** (before `manifest.json`) ensures the correct composition is loaded.

---

## Custom Decoder and Safe Loading

- **Decoder** (`messages_widget.dart`): `_decodeDotLottie()` uses `LottieComposition.decodeZip()` with a `filePicker` that returns the first file whose name ends with `.json`. For `winner01.lottie` we repack the zip so `a/Main Scene.json` comes before `manifest.json`.
- **Safe loader**: `_loadWinnerLottieSafe()` loads the asset bytes, runs the decoder, and catches any error (including parser assertions) so the app never crashes. On failure it returns `null` and the UI shows the trophy icon fallback.

---

## Fixing the Trophy Lottie: Missing Composition Data

The trophy Lottie from [LottieFiles](https://app.lottiefiles.com) caused an **assertion** in the parser:

```text
Assertion failed: startFrame == endFrame
file: lottie-3.3.1/lib/src/parser/lottie_composition_parser.dart:72
```

### Cause

The Lottie composition parser expects the **root** of the composition JSON to include:

| Key | Meaning | Required |
|-----|--------|----------|
| **fr** | Frame rate (frames per second) | Yes, must be > 0 |
| **ip** | In point (start frame) | Yes |
| **op** | Out point (end frame) | Yes, must be **different** from **ip** |

If any of these are missing, the parser uses defaults (`startFrame = 0`, `endFrame = 0`, `frameRate = 0`), which triggers:

1. `startFrame == endFrame` → assertion.
2. `frameRate <= 0` → assertion.

The `winner01.lottie` composition (`a/Main Scene.json`) had **no root-level `fr`, `ip`, or `op`**, so it failed.

### Fix (Edit the .lottie Without Re-exporting)

1. **Extract the .lottie** (it’s a zip):
   ```bash
   cd assets/lottie
   unzip -o winner01.lottie -d winner01_extracted
   ```

2. **Edit the composition JSON** (e.g. `winner01_extracted/a/Main Scene.json`).  
   Find the root object and add `fr`, `ip`, and `op` **after** `"meta": { ... }` and **before** `"layers"`:

   ```json
   "meta":{"g":"@lottiefiles/creator 1.74.0"},"fr":30,"ip":0,"op":120,"layers":[
   ```

   - **fr**: `30` (30 fps).
   - **ip**: `0` (start at frame 0).
   - **op**: `120` (end at frame 120 → 4 seconds at 30 fps).  
   Any `op > ip` is valid; adjust for desired duration.

3. **Repack the zip** with the **animation JSON first** so the custom decoder picks it:
   ```bash
   cd winner01_extracted
   zip -r ../winner01.lottie "a/Main Scene.json" "manifest.json"
   ```

4. **Replace** the original `winner01.lottie` with the new file. Optional: keep a backup of the original before replacing.

After this, the composition parses correctly and the trophy Lottie plays instead of hitting the assertion.

---

## Code References

| What | Where |
|------|--------|
| Decoder for .lottie | `lib/modules/dutch_game/screens/game_play/widgets/messages_widget.dart` – `_decodeDotLottie()` |
| Safe loader (with fallback) | Same file – `_loadWinnerLottieSafe()` |
| Trophy inside modal | Same file – `_WinnerTrophyInModal` |
| Sparkles overlay (winner only) | Same file – `_WinnerCelebrationOverlay` |

---

## Adding or Replacing a Lottie

1. Add the file under `assets/lottie/` (e.g. from [LottieFiles](https://app.lottiefiles.com)).
2. If it’s a **.lottie** (zip):
   - Ensure the main composition JSON has root **fr**, **ip**, and **op** (see above). Edit inside the zip if needed.
   - If using the same “first .json” decoder, repack with the animation JSON first.
3. If the asset can fail (e.g. bad or incomplete export), load it through a safe path (e.g. try/catch + `.catchError`) and show a fallback widget when the composition is `null`.

---

## Summary

- Winner celebration uses a Lottie from [LottieFiles](https://app.lottiefiles.com), loaded from `assets/lottie/winner01.lottie`.
- DotLottie (`.lottie`) files are zips; we use a custom decoder and repack so the correct JSON is used.
- Compositions **must** have root **fr**, **ip**, and **op** for the parser to succeed; we fixed the trophy by adding these to `a/Main Scene.json` and repacking the archive.
- Loading is done via a safe loader that returns `null` on any error, with a trophy icon fallback in the UI.

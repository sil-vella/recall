# Trying Vxplain for auto-generated flowcharts

[Vxplain](https://www.vxplain.com/) is a VS Code / Cursor extension that generates architecture diagrams, call graphs, and flowcharts from your codebase.

## Install

1. Open **Cursor** (or VS Code).
2. Open the **Extensions** view: `Cmd+Shift+X` (Mac) or `Ctrl+Shift+X` (Windows/Linux).
3. Search for **Vxplain**.
4. Click **Install** on the **Vxplain** extension (publisher: Vxplain).

Alternatively, if the workspace recommends it, you may see a prompt to install the recommended extension.

## Use

- **Full codebase diagram:** Click the **Vxplain** icon in the sidebar, then use **Generate Diagram** to analyze the project and get an architecture/call-graph style diagram.
- **Diagram from selection:** Select a block of code (e.g. a function or file), right‑click → **Vxplain: Generate Diagram**.
- **Command palette:** `Cmd+Shift+P` / `Ctrl+Shift+P`:
  - **Vxplain: Generate Diagram**
  - **Vxplain: View Call Graph**
  - **Vxplain: Open Settings** (`Cmd+Alt+S` / `Ctrl+Alt+S`)
  - **Vxplain: Select LLM Provider** (if you use their LLM-backed features)

## Tips for this repo

- Open the **flutter_base_05** or **python_base_04** folder (or the repo root) so Vxplain sees the code you care about.
- Try **Generate Diagram** on the repo root for an overview, or select a module (e.g. `lib/modules/dutch_game`) and generate from that.
- For flow-style charts (e.g. match initiation), select the relevant entrypoints (e.g. `lobby_screen.dart`, `create_join_game_widget.dart`) and generate; you can then refine the result and copy into the flowcharts here.

## Docs

- [Vxplain quickstart](https://docs.vxplain.com/src/quickstart)
- [Code to diagram](https://docs.vxplain.com/src/features/code-to-diagram)
- [Marketplace](https://marketplace.visualstudio.com/items?itemName=Vxplain.vxplain)

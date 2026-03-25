# FlowCharts (Mermaid)

Flowcharts and diagrams for the codebase, in [Mermaid](https://mermaid.js.org/) format.

## Shared style (theme)

All Mermaid diagrams use the same theme so they look consistent. The single source of truth is **`mermaid-theme.mmd`**.

### How it’s applied

- **Generated HTML (charts under `charts/`)**: When you run `scripts/build_nav_and_charts.py`, the script reads `mermaid-theme.mmd` and **prepends it to every chart** before generating each `.html` file. Any `%%{init: ... }%%` at the start of a chart file is removed so the shared theme is the only one used. You don’t need to copy the theme into chart `.mmd` files for the built site.
- **Other viewers** (Mermaid Live Editor, VS Code, etc.): For consistent look there too, you can copy the contents of `mermaid-theme.mmd` to the top of the diagram; the build script will still replace it with the shared theme when generating HTML.

### Theme file

- **`mermaid-theme.mmd`** – theme definition (single `%%{init: ... }%%` block). Edit this file to change styling for all charts; then re-run the build script.

### Theme summary

- **Base theme**: `base` (required for customisation).
- **Palette**: Neutral, document-friendly (cream/beige nodes, dark brown text and lines).
- **Font**: System UI / Segoe UI, 14px.

### Dark variant (optional)

For dark backgrounds, you can use Mermaid’s built-in `"theme": "dark"` in the init block instead of the custom `themeVariables`. For consistency across this repo, prefer the shared theme in `mermaid-theme.mmd` unless you need a dark-only diagram.

## Directory layout

- `mermaid-theme.mmd` – shared theme used for all charts when building HTML.
- `charts/` – chart sources (`.mmd`); subdirs match nav structure. Generated `.html` sits alongside each `.mmd`.
- `partials/`, `templates/`, `css/` – header, page templates, and styles for generated HTML.
- `scripts/build_nav_and_charts.py` – builds nav and generates HTML using `mermaid-theme.mmd`.

## Header and nav (local HTML)

All HTML pages share the same header and nav:

- **Header**: `partials/header.html` defines the bar (logo + nav). The nav is filled by the build script.
- **Build script**: Run from `Documentation/00_FlowCharts`:
  ```bash
  python3 scripts/build_nav_and_charts.py
  ```
  This script:
  - Scans `charts/` and builds a nav that mirrors the directory structure (folders = groups, `.mmd` files = links).
  - Applies **`mermaid-theme.mmd`** to every chart (prepends it and strips any duplicate init block from the chart file).
  - Generates one `.html` file per `.mmd` under `charts/` (same path, `.html` instead of `.mmd`) with the Mermaid diagram embedded so you can open it in a browser with `file://`.
  - Writes `index.html` with the same header and nav.
  - Generates one A4 PDF per chart in the **same directory** as the chart HTML (same base name, `.pdf`), replacing any existing PDF. Requires **Mermaid CLI**: `npm install -g @mermaid-js/mermaid-cli`, then install the browser once: `npx puppeteer browsers install chrome-headless-shell`. PDFs are for physical printing; HTML remains for browser viewing.

**HTML** is for browser viewing; **PDFs** are for physical printing (A4). Open `index.html` or any `charts/…/*.html` in a browser (no server needed). Regenerate after adding or moving charts.

## Editing and viewing

- Edit `.mmd` files under `charts/` in any editor. You can omit the theme block; the build script applies `mermaid-theme.mmd` when generating HTML.
- View in: run the build script and open the generated HTML in a browser, or use Mermaid Live Editor / VS Code Mermaid extension.

## Chart Creation Process (our workflow)

Use this process whenever you add or update a flowchart.

1. Create or edit a Mermaid source file (`.mmd`) under `charts/`.
   - Keep files grouped by topic using folders (for example `charts/end-to-end/firebase/`).
   - File names should be lowercase with dashes (for example `client-analytics-flow.mmd`).
2. Write only the diagram content in the `.mmd` file (for example `flowchart TD ...`).
   - Do not duplicate theme init blocks in each chart; shared theme is handled centrally.
3. Run the build script from `Documentation/00_FlowCharts`:
   ```bash
   python3 scripts/build_nav_and_charts.py
   ```
4. The script automatically:
   - Scans `charts/` and rebuilds nav in `index.html`.
   - Applies `mermaid-theme.mmd` to every chart.
   - Generates/updates chart HTML next to each `.mmd` (same name, `.html` extension).
   - Generates/updates A4 PDF next to each chart HTML (requires Mermaid CLI setup).
5. Open `index.html` and verify your chart appears in the nav and renders correctly.

Recommended quick check for a new chart:
- Confirm both files exist side by side:
  - `.../<chart-name>.mmd`
  - `.../<chart-name>.html`
- Open the generated `.html` directly in browser (`file://`) to confirm layout and styling.

## Firebase Client Flow (combined from whiteboard)

The two whiteboard photos were merged into one simple client-side Firebase flow:

```mermaid
flowchart TD
    A[Firebase Project (Cloud)] --> B[Register app]
    B --> C[Get config values<br/>apiKey, appId, projectId]

    D[Client app startup] --> E[Firebase SDK reads config]
    E --> F[SDK points app to Firebase project]

    F --> G[Add product package in pubspec<br/>e.g. firebase_analytics]
    G --> H[Import package and create instance]
    H --> I[Call product API<br/>analytics.logEvent]
    I --> J[Example event<br/>name: start_match_after<br/>params: minutes]
    J --> K[SDK batches and sends events]
    K --> L[Events arrive in Firebase project/cloud]
```

Source images used:

- `/Users/sil/.cursor/projects/Users-sil-Documents-Work-reignofplay-Dutch-app-dev/assets/IMG_20260325_134651-1852e871-5101-42b1-8aef-870fa167a411.png`
- `/Users/sil/.cursor/projects/Users-sil-Documents-Work-reignofplay-Dutch-app-dev/assets/IMG_20260325_134644-73a38712-3e48-4b02-b6f9-f19bd9a5dbf5.png`

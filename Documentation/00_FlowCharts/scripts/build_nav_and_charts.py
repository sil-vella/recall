#!/usr/bin/env python3
"""
Build nav from charts/ directory structure and generate HTML for each .mmd file.
Run from Documentation/00_FlowCharts (or project root with FLOWCHARTS_ROOT set).
No server: all pages are static; each chart's Mermaid source is embedded in its HTML.
"""

import os
import re
import html
from pathlib import Path


# Paths relative to this script's parent's parent = 00_FlowCharts
SCRIPT_DIR = Path(__file__).resolve().parent
FLOWCHARTS_ROOT = SCRIPT_DIR.parent
CHARTS_DIR = FLOWCHARTS_ROOT / "charts"
TEMPLATES_DIR = FLOWCHARTS_ROOT / "templates"
MERMAID_THEME_PATH = FLOWCHARTS_ROOT / "mermaid-theme.mmd"
CSS_DIR = FLOWCHARTS_ROOT / "css"

# Strip optional leading %%{init ... }%% from chart so shared theme is the only one
INIT_BLOCK_RE = re.compile(r"^\s*%%\{init:.*?\}%%\s*", re.DOTALL)


def walk_charts(base: Path, prefix: str = "") -> list:
    """
    Build a tree of chart entries. Each entry is either:
    - ("dir", name, path_from_charts, children)
    - ("file", name, path_from_charts_no_ext)
    """
    entries = []
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return entries

    dirs = []
    files = []
    for name in names:
        full = base / name
        if full.is_dir() and not name.startswith("."):
            dirs.append(name)
        elif full.suffix.lower() == ".mmd":
            files.append(name)

    for name in sorted(files):
        stem = name[: -len(".mmd")]
        rel = f"{prefix}{stem}" if prefix else stem
        entries.append(("file", stem.replace("-", " ").replace("_", " ").title(), rel))

    for name in sorted(dirs):
        sub = base / name
        sub_prefix = f"{prefix}{name}/"
        children = walk_charts(sub, sub_prefix)
        if children or any((sub / f).exists() for f in os.listdir(sub) if f.endswith(".mmd")):
            # Include dir if it has .mmd files (children may be nested)
            def has_mmd(p):
                if p.is_file() and p.suffix.lower() == ".mmd":
                    return True
                if p.is_dir():
                    return any(has_mmd(p / x) for x in os.listdir(p))
                return False

            if has_mmd(sub):
                entries.append(("dir", name.replace("-", " ").replace("_", " ").title(), sub_prefix.rstrip("/"), children))

    return entries


def nav_html(entries: list, rel_to_root: str, current_chart_path: str | None) -> str:
    """Generate nested <ul>/<li> nav from entries. Links use rel_to_root + path."""
    if not entries:
        return ""

    def link(href: str, label: str, active: bool = False) -> str:
        a_class = ' class="active"' if active else ""
        return f'<a href="{html.escape(href)}"{a_class}>{html.escape(label)}</a>'

    parts = ["<ul>"]
    for item in entries:
        kind = item[0]
        name = item[1]
        path = item[2]
        children = item[3] if kind == "dir" and len(item) > 3 else []
        if kind == "file":
            href = f"{rel_to_root}charts/{path}.html"
            active = current_chart_path == path
            parts.append(f"<li>{link(href, name, active)}</li>")
        else:
            sub = nav_html(children, rel_to_root, current_chart_path)
            parts.append(f'<li><button type="button" class="nav-folder" aria-haspopup="true" aria-expanded="false">{html.escape(name)}</button>{sub}</li>')
    parts.append("</ul>")
    return "\n".join(parts)


def rel_to_root_from_chart(chart_path_from_charts: str) -> str:
    """From e.g. 'game-state/state' return '../../' (file is at charts/game-state/state.html)."""
    segments = chart_path_from_charts.split("/")
    depth = len(segments)  # charts/game-state/state.html -> up 2 levels to root
    return "../" * depth if depth else ""


def main() -> None:
    os.chdir(FLOWCHARTS_ROOT)

    CHARTS_DIR.mkdir(exist_ok=True)
    (FLOWCHARTS_ROOT / "css").mkdir(exist_ok=True)

    entries = walk_charts(CHARTS_DIR)
    rel_root_index = ""  # index.html is at root
    nav_for_index = nav_html(entries, rel_root_index, None)

    # Load shared theme and templates
    theme_source = MERMAID_THEME_PATH.read_text(encoding="utf-8").strip() if MERMAID_THEME_PATH.exists() else ""
    chart_tpl = (TEMPLATES_DIR / "chart.html").read_text(encoding="utf-8")
    index_tpl = (TEMPLATES_DIR / "index.html").read_text(encoding="utf-8")

    # Write index.html
    index_html = index_tpl.replace("{{NAV_CONTENT}}", nav_for_index)
    (FLOWCHARTS_ROOT / "index.html").write_text(index_html, encoding="utf-8")
    print("Wrote index.html")

    # Collect all .mmd paths and generate HTML for each
    def collect_mmd_paths(base: Path, prefix: str) -> list[tuple[str, Path]]:
        out = []
        for name in sorted(os.listdir(base) if base.exists() else []):
            full = base / name
            if full.is_dir() and not name.startswith("."):
                out.extend(collect_mmd_paths(full, f"{prefix}{name}/"))
            elif full.suffix.lower() == ".mmd":
                stem = name[: -len(".mmd")]
                out.append((f"{prefix}{stem}", full))
        return out

    mmd_list = collect_mmd_paths(CHARTS_DIR, "")

    for path_from_charts, mmd_path in mmd_list:
        rel_to_root = rel_to_root_from_chart(path_from_charts)
        nav_content = nav_html(entries, rel_to_root, path_from_charts)

        try:
            chart_source = mmd_path.read_text(encoding="utf-8").strip()
        except OSError as e:
            print(f"Skip {mmd_path}: {e}")
            continue

        # Apply shared theme: prepend mermaid-theme.mmd and strip any init block from chart
        chart_only = INIT_BLOCK_RE.sub("", chart_source).strip()
        mermaid_source = f"{theme_source}\n{chart_only}" if theme_source else chart_only

        title = path_from_charts.split("/")[-1].replace("-", " ").replace("_", " ").title()
        mermaid_escaped = html.escape(mermaid_source)

        html_content = (
            chart_tpl.replace("{{CHART_TITLE}}", title)
            .replace("{{ROOT_REL}}", rel_to_root)
            .replace("{{NAV_CONTENT}}", nav_content)
            .replace("{{MERMAID_SOURCE}}", mermaid_escaped)
        )

        out_path = mmd_path.with_suffix(".html")
        out_path.write_text(html_content, encoding="utf-8")
        print(f"Wrote {out_path.relative_to(FLOWCHARTS_ROOT)}")

    if not mmd_list:
        print("No .mmd files found under charts/ — add some to generate chart pages.")


if __name__ == "__main__":
    main()

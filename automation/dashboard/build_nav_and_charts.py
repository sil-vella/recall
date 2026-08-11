#!/usr/bin/env python3
# dash Generate flowchart HTML from Mermaid sources
"""
Build nav from charts/ directory structure and generate HTML for each .mmd file.
Also builds plain-English guide pages from co-located .guide.md files.

Run from project root: python3 automation/dashboard/build_nav_and_charts.py
No server: all pages are static; each chart's Mermaid source is embedded in its HTML.
"""

import html
import os
import re
from pathlib import Path


# This script lives in automation/dashboard/; flowcharts assets are under Documentation/02_FlowCharts/
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
_FLOWCHARTS_CANDIDATES = (
    PROJECT_ROOT / "Documentation" / "02_FlowCharts",
    PROJECT_ROOT / "documentation" / "02_FlowCharts",
)
FLOWCHARTS_ROOT = next(
    (p for p in _FLOWCHARTS_CANDIDATES if p.is_dir()),
    _FLOWCHARTS_CANDIDATES[0],
)
CHARTS_DIR = FLOWCHARTS_ROOT / "charts"
TEMPLATES_DIR = FLOWCHARTS_ROOT / "templates"
PARTIALS_DIR = FLOWCHARTS_ROOT / "partials"
HEADER_PARTIAL_PATH = PARTIALS_DIR / "header.html"
MERMAID_THEME_PATH = FLOWCHARTS_ROOT / "mermaid-theme.mmd"

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
            def has_mmd(p):
                if p.is_file() and p.suffix.lower() == ".mmd":
                    return True
                if p.is_dir():
                    return any(has_mmd(p / x) for x in os.listdir(p))
                return False

            if has_mmd(sub):
                entries.append(
                    (
                        "dir",
                        name.replace("-", " ").replace("_", " ").title(),
                        sub_prefix.rstrip("/"),
                        children,
                    )
                )

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
            parts.append(
                f'<li><button type="button" class="nav-folder" aria-haspopup="true" '
                f'aria-expanded="false">{html.escape(name)}</button>{sub}</li>'
            )
    parts.append("</ul>")
    return "\n".join(parts)


def render_header(rel_to_root: str, nav_ul: str) -> str:
    """Fill header partial: logo href + dropdown nav (matches css/flowcharts.css)."""
    if HEADER_PARTIAL_PATH.is_file():
        tpl = HEADER_PARTIAL_PATH.read_text(encoding="utf-8")
    else:
        tpl = (
            '<header class="flowcharts-header">\n'
            '  <div class="header-inner">\n'
            '    <a class="logo" href="{{ROOT_REL}}index.html">FlowCharts</a>\n'
            '    <nav class="flowcharts-nav" aria-label="Chart index">\n'
            "{{NAV_CONTENT}}\n"
            "    </nav>\n"
            "  </div>\n"
            "</header>\n"
        )
    return tpl.replace("{{ROOT_REL}}", rel_to_root).replace("{{NAV_CONTENT}}", nav_ul)


def rel_to_root_from_chart(chart_path_from_charts: str) -> str:
    """From e.g. 'game-state/state' return '../../' (file is at charts/game-state/state.html)."""
    segments = chart_path_from_charts.split("/")
    depth = len(segments)
    return "../" * depth if depth else ""


def chart_title_from_path(path_from_charts: str) -> str:
    return path_from_charts.split("/")[-1].replace("-", " ").replace("_", " ").title()


def guide_href_for_chart(chart_html_name: str) -> str:
    """chart.html -> chart.guide.html (same directory)."""
    return chart_html_name.replace(".html", ".guide.html")


def guide_link_html(chart_html_name: str) -> str:
    guide_href = html.escape(guide_href_for_chart(chart_html_name))
    return (
        f'<p class="chart-guide-link">'
        f'<a href="{guide_href}">Plain English guide &amp; examples →</a>'
        f"</p>"
    )


def _inline_markdown(text: str) -> str:
    """Bold, inline code, and markdown links."""
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>',
        text,
    )
    return text


def markdown_to_html(source: str) -> str:
    """Convert a small markdown subset to HTML for guide pages."""
    lines = source.splitlines()
    if lines and lines[0].startswith("# "):
        lines = lines[1:]  # title rendered by template

    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]

        if line.strip() == "":
            i += 1
            continue

        if line.startswith("```"):
            fence = line.strip()
            lang = fence[3:].strip()
            i += 1
            code_lines: list[str] = []
            while i < len(lines) and not lines[i].startswith("```"):
                code_lines.append(lines[i])
                i += 1
            if i < len(lines):
                i += 1
            code = html.escape("\n".join(code_lines))
            cls = f' class="language-{html.escape(lang)}"' if lang else ""
            out.append(f"<pre><code{cls}>{code}</code></pre>")
            continue

        if re.match(r"^#{2,3} ", line):
            level = 2 if line.startswith("## ") else 3
            text = line[level + 1 :].strip()
            out.append(f"<h{level}>{_inline_markdown(text)}</h{level}>")
            i += 1
            continue

        if line.startswith("|"):
            table_rows: list[str] = []
            while i < len(lines) and lines[i].startswith("|"):
                table_rows.append(lines[i])
                i += 1
            if len(table_rows) >= 2 and re.match(r"^\|[\s\-:|]+\|$", table_rows[1]):
                header = [c.strip() for c in table_rows[0].strip("|").split("|")]
                body_rows = table_rows[2:]
                parts = ["<table><thead><tr>"]
                parts.extend(f"<th>{_inline_markdown(c)}</th>" for c in header)
                parts.append("</tr></thead><tbody>")
                for row in body_rows:
                    cells = [c.strip() for c in row.strip("|").split("|")]
                    parts.append("<tr>")
                    parts.extend(f"<td>{_inline_markdown(c)}</td>" for c in cells)
                    parts.append("</tr>")
                parts.append("</tbody></table>")
                out.append("".join(parts))
            else:
                out.append(f"<p>{_inline_markdown(line)}</p>")
            continue

        if re.match(r"^[-*] ", line):
            items: list[str] = []
            while i < len(lines) and re.match(r"^[-*] ", lines[i]):
                items.append(_inline_markdown(lines[i][2:].strip()))
                i += 1
            out.append("<ul>" + "".join(f"<li>{item}</li>" for item in items) + "</ul>")
            continue

        if re.match(r"^\d+\. ", line):
            items = []
            while i < len(lines) and re.match(r"^\d+\. ", lines[i]):
                items.append(_inline_markdown(re.sub(r"^\d+\.\s*", "", lines[i])))
                i += 1
            out.append("<ol>" + "".join(f"<li>{item}</li>" for item in items) + "</ol>")
            continue

        para_lines = [line]
        i += 1
        while i < len(lines) and lines[i].strip() and not lines[i].startswith(
            ("#", "|", "-", "*", "`")
        ) and not re.match(r"^\d+\. ", lines[i]):
            para_lines.append(lines[i])
            i += 1
        out.append(f"<p>{_inline_markdown(' '.join(para_lines))}</p>")

    return "\n".join(out)


def write_guide_html(
    path_from_charts: str,
    guide_md_path: Path,
    entries: list,
    guide_tpl: str,
) -> None:
    rel_to_root = rel_to_root_from_chart(path_from_charts)
    nav_content = nav_html(entries, rel_to_root, path_from_charts)
    title = chart_title_from_path(path_from_charts)
    chart_html_name = f"{path_from_charts.split('/')[-1]}.html"

    try:
        md_source = guide_md_path.read_text(encoding="utf-8")
    except OSError as e:
        print(f"Skip guide {guide_md_path}: {e}")
        return

    body = markdown_to_html(md_source)
    header_block = render_header(rel_to_root, nav_content)
    guide_html = (
        guide_tpl.replace("{{GUIDE_TITLE}}", html.escape(title))
        .replace("{{ROOT_REL}}", rel_to_root)
        .replace("{{HEADER}}", header_block)
        .replace("{{CHART_HREF}}", html.escape(chart_html_name))
        .replace("{{GUIDE_BODY}}", body)
    )
    out_path = guide_md_path.with_suffix(".html")
    out_path.write_text(guide_html, encoding="utf-8")
    print(f"Wrote {out_path.relative_to(FLOWCHARTS_ROOT)}")


def main() -> None:
    os.chdir(FLOWCHARTS_ROOT)

    CHARTS_DIR.mkdir(exist_ok=True)
    (FLOWCHARTS_ROOT / "css").mkdir(exist_ok=True)

    entries = walk_charts(CHARTS_DIR)
    rel_root_index = ""
    nav_for_index = nav_html(entries, rel_root_index, None)

    theme_source = (
        MERMAID_THEME_PATH.read_text(encoding="utf-8").strip()
        if MERMAID_THEME_PATH.exists()
        else ""
    )
    chart_tpl = (TEMPLATES_DIR / "chart.html").read_text(encoding="utf-8")
    guide_tpl = (TEMPLATES_DIR / "guide.html").read_text(encoding="utf-8")
    index_tpl = (TEMPLATES_DIR / "index.html").read_text(encoding="utf-8")

    header_block = render_header(rel_root_index, nav_for_index)
    index_html = index_tpl.replace("{{HEADER}}", header_block)
    (FLOWCHARTS_ROOT / "index.html").write_text(index_html, encoding="utf-8")
    print("Wrote index.html")

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

        chart_only = INIT_BLOCK_RE.sub("", chart_source).strip()
        mermaid_source = f"{theme_source}\n{chart_only}" if theme_source else chart_only

        title = chart_title_from_path(path_from_charts)
        title_esc = html.escape(title)
        mermaid_escaped = html.escape(mermaid_source)
        header_block = render_header(rel_to_root, nav_content)

        chart_html_name = f"{path_from_charts.split('/')[-1]}.html"
        guide_md_path = mmd_path.with_suffix(".guide.md")
        guide_link = guide_link_html(chart_html_name) if guide_md_path.is_file() else ""

        html_content = (
            chart_tpl.replace("{{CHART_TITLE}}", title_esc)
            .replace("{{ROOT_REL}}", rel_to_root)
            .replace("{{HEADER}}", header_block)
            .replace("{{GUIDE_LINK}}", guide_link)
            .replace("{{MERMAID_SOURCE}}", mermaid_escaped)
        )

        out_path = mmd_path.with_suffix(".html")
        out_path.write_text(html_content, encoding="utf-8")
        print(f"Wrote {out_path.relative_to(FLOWCHARTS_ROOT)}")

        if guide_md_path.is_file():
            write_guide_html(path_from_charts, guide_md_path, entries, guide_tpl)

    if not mmd_list:
        print("No .mmd files found under charts/ — add some to generate chart pages.")


if __name__ == "__main__":
    main()

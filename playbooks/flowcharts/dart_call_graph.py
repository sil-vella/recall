#!/usr/bin/env python3
"""
Generate a simple call-graph from a single Dart file (no Dart analyzer).
Parses the file with regex/heuristics to find method/function definitions
and call sites, then outputs a Mermaid flowchart.

Usage:
  python3 dart_call_graph.py <path_to.dart> [output.mmd] [--internal-only]
  From app_dev: python3 playbooks/flowcharts/dart_call_graph.py flutter_base_05/lib/path/to/file.dart
"""

import re
import sys
from pathlib import Path

KEYWORDS = {
    "if", "else", "for", "while", "do", "switch", "case", "catch", "try",
    "return", "throw", "break", "continue", "assert", "await", "yield",
    "in", "on", "is", "as", "new", "super", "this", "true", "false", "null",
    "import", "export", "part", "library", "typedef", "extension", "mixin",
    "class", "enum", "abstract", "extends", "implements", "with", "get", "set",
    "static", "final", "const", "var", "void", "async", "sync", "external",
    "factory", "operator", "required", "late", "show", "hide", "when",
}


def strip_comments(text: str) -> str:
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    lines = []
    for line in text.split('\n'):
        in_string = False
        quote = None
        i = 0
        while i < len(line):
            c = line[i]
            if not in_string:
                if c in '"\'':
                    in_string = True
                    quote = c
                    i += 1
                    continue
                if i < len(line) - 1 and line[i:i+2] == '//':
                    line = line[:i].rstrip()
                    break
            else:
                if c == '\\' and i + 1 < len(line):
                    i += 2
                    continue
                if c == quote:
                    in_string = False
                i += 1
                continue
            i += 1
        lines.append(line)
    return '\n'.join(lines)


def get_preceding_comment(raw_source: str, line_no: int, max_chars: int = 120) -> str | None:
    """
    Return the block of // comments immediately above the given line (0-based).
    Blank lines between comment and code are skipped. Result is one line, truncated.
    """
    lines = raw_source.split("\n")
    if line_no <= 0:
        return None
    comment_lines = []
    for i in range(line_no - 1, -1, -1):
        stripped = lines[i].strip()
        if not stripped:
            continue
        if stripped.startswith("//"):
            comment_lines.append(stripped[2:].strip())
            continue
        break
    comment_lines.reverse()
    if not comment_lines:
        return None
    text = " ".join(comment_lines)
    if len(text) > max_chars:
        text = text[: max_chars - 3] + "..."
    return text.strip() or None


def find_members_and_calls(source: str):
    """Returns (members, declared, edges) where edges are (caller, callee, line_no)."""
    source = strip_comments(source)
    members = set()
    declared = set()
    edges = []  # (caller, callee, line_no)

    decl_pattern = re.compile(
        r'\b(?:static\s+|override\s+|async\s+)?'
        r'(?:void|Future<[^>]+>|List<[^>]+>|Map<[^>]+>|Set<[^>]+>|'
        r'String|bool|int|double|dynamic|var|\w+)\s+'
        r'(\w+)\s*\('
    )
    constructor_pattern = re.compile(r'\b([A-Z][a-zA-Z0-9]*)\s*\(')
    method_call_pattern = re.compile(r'\.(\w+)\s*\(')
    standalone_call_pattern = re.compile(r'\b([a-zA-Z_]\w*)\s*\(')

    depth = 0
    current_member = None
    pending_member = None
    stack = []

    for line_no, line in enumerate(source.split("\n")):
        stripped = line.strip()
        if stripped.startswith("import ") or stripped.startswith("export "):
            continue

        if depth <= 1:
            for m in decl_pattern.finditer(line):
                name = m.group(1)
                if name not in KEYWORDS:
                    pending_member = name
                    members.add(name)
                    declared.add(name)
            for m in constructor_pattern.finditer(line):
                name = m.group(1)
                if name not in KEYWORDS and not line.strip().startswith("//"):
                    pending_member = name
                    members.add(name)
                    declared.add(name)

        for c in line:
            if c == "{":
                depth += 1
                if depth == 2 and pending_member is not None:
                    current_member = pending_member
                    stack.append((pending_member, depth))
                    pending_member = None
                elif stack:
                    stack.append((stack[-1][0], depth))
            elif c == "}":
                if stack and stack[-1][1] == depth:
                    stack.pop()
                depth = max(0, depth - 1)
                if stack:
                    current_member = stack[-1][0]
                else:
                    current_member = None

        if current_member is not None and depth >= 1:
            for m in method_call_pattern.finditer(line):
                callee = m.group(1)
                if callee not in KEYWORDS:
                    members.add(callee)
                    edges.append((current_member, callee, line_no))
            for m in standalone_call_pattern.finditer(line):
                callee = m.group(1)
                if callee not in KEYWORDS and callee != current_member:
                    members.add(callee)
                    edges.append((current_member, callee, line_no))

    return members, declared, edges


def escape_mermaid_id(s: str) -> str:
    return re.sub(r'[#;\[\]"]', '_', s)


def escape_edge_label(s: str, max_len: int = 60) -> str:
    """Sanitize comment for Mermaid edge label: single line, no quotes/pipes."""
    s = s.replace("\\", " ").replace('"', "'").replace("|", ",").replace("\n", " ").strip()
    s = re.sub(r'\s+', ' ', s)
    return (s[: max_len - 3] + "...") if len(s) > max_len else s


def subgraph_for_node(name: str) -> str:
    """Assign node to a subgraph by name prefix to cluster the layout."""
    if name in ("DutchGameRound", "Logger"):
        return "core"
    if name.startswith("handle") and not name.startswith("_"):
        return "public"
    if name in ("initializeRound", "moveToNextPlayer", "dispose", "updateKnownCards", "getMissedActionCount"):
        return "public"
    if name.startswith("_on") and "Timer" in name:
        return "timers"
    if name.startswith("_start") or name.startswith("_cancel") or "_Timer" in name:
        return "timers"
    if name.startswith("_handle"):
        return "handlers"
    if name.startswith("_process") or name.startswith("_execute"):
        return "process"
    if name.startswith("_end") or name.startswith("_check") and "Game" in name:
        return "game_end"
    if name.startswith("_check") or name.startswith("_validate") or name.startswith("_is"):
        return "checks"
    if name.startswith("_init") or name.startswith("_ensure") or "Computer" in name or "SameRank" in name:
        return "computer"
    if name.startswith("_get") or name.startswith("_create") or name.startswith("_generate"):
        return "helpers"
    if name.startswith("_update") or name.startswith("_set") or name.startswith("_add") or name.startswith("_clear"):
        return "state"
    if name.startswith("_move") or name.startswith("_schedule") or "_sanitize" in name or "_resolve" in name:
        return "flow"
    if name.startswith("_calculate") or name.startswith("_trim") or name.startswith("_should"):
        return "helpers"
    return "other"


def main():
    if len(sys.argv) < 2:
        print("Usage: dart_call_graph.py <file.dart> [output.mmd] [--internal-only] [--lr] [--tb] [--flowchart]", file=sys.stderr)
        sys.exit(1)
    args = sys.argv[1:]
    internal_only = "--internal-only" in args
    if internal_only:
        args.remove("--internal-only")
    use_lr = "--lr" in args
    if use_lr:
        args.remove("--lr")
    use_tb = "--tb" in args
    if use_tb:
        args.remove("--tb")
    use_flowchart = "--flowchart" in args
    if use_flowchart:
        args.remove("--flowchart")
    path = Path(args[0])
    if not path.exists():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)
    out_path = Path(args[1]) if len(args) > 1 else path.with_suffix('.mmd')

    raw_source = path.read_text(encoding="utf-8", errors="replace")
    members, declared, edges = find_members_and_calls(raw_source)

    if internal_only:
        edges = [(c, v, ln) for c, v, ln in edges if c in declared and v in declared]
        members = declared

    # Merge duplicate edges (same caller->callee): keep first line_no for comment, count for label
    merged: dict[tuple[str, str], list[int]] = {}
    for caller, callee, line_no in edges:
        key = (caller, callee)
        merged.setdefault(key, []).append(line_no)
    merged_edges = [(c, v, ln_list[0], len(ln_list)) for (c, v), ln_list in merged.items()]

    # Flowchart mode defaults to top-down (TB); otherwise respect --tb / --lr / default TD
    if use_flowchart and not use_lr:
        direction = "TB"
    else:
        direction = "TB" if use_tb else ("LR" if use_lr else "TD")
    lines = [
        "%%{init: {'flowchart': {'useMaxWidth': true}}}%%",
        f"flowchart {direction}",
    ]
    node_ids = {}
    for i, name in enumerate(sorted(members)):
        safe = escape_mermaid_id(name)
        node_ids[name] = f"N{i}" if safe != name else name

    # Flowchart mode: add Start/End and use stadium shapes for entry/exit
    entry_points: set[str] = set()
    leaf_nodes: set[str] = set()
    if use_flowchart:
        callees = {callee for _, callee, _, _ in merged_edges}
        callers = {caller for caller, _, _, _ in merged_edges}
        entry_points = members - callees  # never called by anyone in this graph
        leaf_nodes = members - callers   # never call anyone in this graph
        lines.append("  Start([Start])")
        lines.append("  End([End])")
        for name in sorted(entry_points):
            nid = node_ids.get(name, escape_mermaid_id(name))
            lines.append(f"  Start --> {nid}")
        for name in sorted(leaf_nodes):
            if name not in entry_points:  # avoid Start -> entry -> End when entry is also leaf
                nid = node_ids.get(name, escape_mermaid_id(name))
                lines.append(f"  {nid} --> End")

    # Group nodes by subgraph for clearer layout
    subgraph_order = (
        "core", "public", "timers", "handlers", "process", "game_end",
        "computer", "checks", "helpers", "state", "flow", "other",
    )
    subgraph_titles = {
        "core": "Core",
        "public": "Public API",
        "timers": "Timers",
        "handlers": "Handlers",
        "process": "Process / Execute",
        "game_end": "Game end",
        "computer": "Computer / Init",
        "checks": "Checks / Validators",
        "helpers": "Helpers",
        "state": "State updates",
        "flow": "Flow / Move",
        "other": "Other",
    }
    by_sub: dict[str, list[str]] = {sg: [] for sg in subgraph_order}
    for name in sorted(members):
        sg = subgraph_for_node(name)
        by_sub.setdefault(sg, []).append(name)
    for sg in subgraph_order:
        names = by_sub.get(sg, [])
        if not names:
            continue
        title = subgraph_titles.get(sg, sg)
        lines.append(f"  subgraph {escape_mermaid_id(sg)}[\"{title}\"]")
        for name in names:
            nid = node_ids.get(name, escape_mermaid_id(name))
            label = name.replace('"', '#quot;')
            if use_flowchart and name in (entry_points | leaf_nodes):
                lines.append(f'    {nid}([{label}])')
            else:
                lines.append(f'    {nid}["{label}"]')
        lines.append("  end")

    for caller, callee, line_no, count in merged_edges:
        cid = node_ids.get(caller, escape_mermaid_id(caller))
        vid = node_ids.get(callee, escape_mermaid_id(callee))
        comment = get_preceding_comment(raw_source, line_no)
        if comment:
            label = escape_edge_label(comment)
            if count > 1:
                label = f"{label} ({count}×)"
            lines.append(f'  {cid} -->|"{label}"| {vid}')
        else:
            if count > 1:
                lines.append(f'  {cid} -->|"{count}×"| {vid}')
            else:
                lines.append(f"  {cid} --> {vid}")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {len(members)} nodes, {len(merged_edges)} edges (from {len(edges)} calls) to {out_path}")


if __name__ == "__main__":
    main()

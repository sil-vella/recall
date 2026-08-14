# dash Discover Documentation/*.md for dashboard Docs / Case Study tabs
"""List markdown under Documentation/ for the wfrun dashboard."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

MD_SUFFIXES = frozenset({".md", ".MD", ".markdown"})
_HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
_MENU_LINK_RE = re.compile(
    r"^\s*\d+\.\s*\[([^\]]+)\]\(#([^)]+)\)\s*$"
)
CASE_STUDY_NAME_RE = re.compile(r"case[_-]?study", re.IGNORECASE)


@dataclass(frozen=True)
class DocEntry:
    id: str
    group: str
    title: str
    rel_path: str

    def to_dict(self) -> dict[str, object]:
        return {
            "id": self.id,
            "group": self.group,
            "title": self.title,
            "path": self.rel_path,
        }


@dataclass(frozen=True)
class DocSection:
    id: str
    title: str
    level: int

    def to_dict(self) -> dict[str, object]:
        return {"id": self.id, "title": self.title, "level": self.level}


def documentation_root(project_root: Path) -> Path:
    return (project_root / "Documentation").resolve()


def github_slug(text: str) -> str:
    """Approximate GitHub heading anchors (em-dash → empty so spaces become --)."""
    s = text.strip().lower()
    out: list[str] = []
    for ch in s:
        if ch.isalnum() or ch in " -_":
            out.append(ch)
        # em/en dash dropped; surrounding spaces become -- after space→hyphen
    slug = "".join(out).replace(" ", "-")
    return slug.strip("-")


def extract_sections(markdown: str) -> list[DocSection]:
    """Prefer explicit ## Menu numbered links; else all ##…###### headings."""
    menu: list[DocSection] = []
    in_menu = False
    for line in markdown.splitlines():
        if re.match(r"^##\s+Menu\s*$", line.strip(), re.IGNORECASE):
            in_menu = True
            continue
        if in_menu:
            if line.startswith("## "):
                break
            m = _MENU_LINK_RE.match(line)
            if m:
                menu.append(
                    DocSection(id=m.group(2).strip(), title=m.group(1).strip(), level=2)
                )
            continue

    if menu:
        return menu

    sections: list[DocSection] = []
    for line in markdown.splitlines():
        m = _HEADING_RE.match(line)
        if not m:
            continue
        level = len(m.group(1))
        if level < 2:
            continue
        title = m.group(2).strip()
        if title.lower() == "menu":
            continue
        sections.append(DocSection(id=github_slug(title), title=title, level=level))
    return sections


def _title_from_path(path: Path) -> str:
    stem = path.stem
    stem = re.sub(r"^\d+[_\-\s]*", "", stem)
    return stem.replace("-", " ").replace("_", " ").strip() or path.name


def _is_case_study(path: Path) -> bool:
    return bool(CASE_STUDY_NAME_RE.search(path.name))


def discover_docs(project_root: Path) -> list[DocEntry]:
    root = documentation_root(project_root)
    if not root.is_dir():
        return []

    entries: list[DocEntry] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in MD_SUFFIXES:
            continue
        if _is_case_study(path):
            continue
        rel = path.relative_to(root).as_posix()
        parts = Path(rel).parts
        group = parts[0] if len(parts) > 1 else "(root)"
        entries.append(
            DocEntry(
                id=rel,
                group=group,
                title=_title_from_path(path),
                rel_path=rel,
            )
        )
    return entries


def discover_case_studies(project_root: Path) -> list[DocEntry]:
    root = documentation_root(project_root)
    if not root.is_dir():
        return []

    entries: list[DocEntry] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in MD_SUFFIXES:
            continue
        if not _is_case_study(path):
            continue
        rel = path.relative_to(root).as_posix()
        parts = Path(rel).parts
        group = parts[0] if len(parts) > 1 else "(root)"
        entries.append(
            DocEntry(
                id=rel,
                group=group,
                title=_title_from_path(path),
                rel_path=rel,
            )
        )
    return entries


def resolve_doc_path(project_root: Path, rel_path: str) -> Path | None:
    """Resolve a Documentation-relative path; reject escapes."""
    rel = (rel_path or "").strip().replace("\\", "/")
    if not rel or rel.startswith("/") or ".." in rel.split("/"):
        return None
    root = documentation_root(project_root)
    candidate = (root / rel).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    if not candidate.is_file() or candidate.suffix not in MD_SUFFIXES:
        return None
    return candidate


def read_doc(project_root: Path, rel_path: str) -> dict[str, object] | None:
    path = resolve_doc_path(project_root, rel_path)
    if path is None:
        return None
    root = documentation_root(project_root)
    text = path.read_text(encoding="utf-8", errors="replace")
    rel = path.relative_to(root).as_posix()
    return {
        "path": rel,
        "title": _title_from_path(path),
        "markdown": text,
        "sections": [s.to_dict() for s in extract_sections(text)],
        "is_case_study": _is_case_study(path),
    }

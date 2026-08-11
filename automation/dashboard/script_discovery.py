# dash Discover runnable automation scripts for dashboard
"""Discover automation scripts using the same rules as wfrun."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

RUNNABLE_SUFFIXES = frozenset({".sh", ".py", ".yml", ".yaml"})
_DASH_DESC_RE = re.compile(r"^\s*#\s*dash\s+(.+)$")


@dataclass(frozen=True)
class ScriptEntry:
    id: str
    path: Path
    profile: str
    kind: str
    runnable: bool
    group: str
    description: str

    def to_dict(self) -> dict[str, object]:
        return {
            "id": self.id,
            "path": str(self.path),
            "profile": self.profile,
            "kind": self.kind,
            "runnable": self.runnable,
            "group": self.group,
            "description": self.description,
        }


def _profile_for_rel(rel: str) -> str:
    if rel.startswith("automation/frontend/"):
        return "frontend"
    return "backend"


def _group_for_rel(rel: str) -> str:
    parts = rel.split("/")
    if len(parts) >= 3:
        return parts[1]
    return "other"


def _kind_for_path(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".sh":
        return "shell"
    if suffix == ".py":
        return "python"
    if suffix in {".yml", ".yaml"}:
        return "ansible"
    if os.access(path, os.X_OK):
        return "executable"
    return "unsupported"


def _is_runnable(path: Path) -> bool:
    suffix = path.suffix.lower()
    if suffix in RUNNABLE_SUFFIXES:
        return True
    return os.access(path, os.X_OK)


def _read_dash_description(path: Path) -> str:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()[:40]
    except OSError:
        return ""
    for line in lines:
        match = _DASH_DESC_RE.match(line)
        if match:
            return match.group(1).strip()
    return ""


def _load_excluded_paths(root: Path) -> set[str]:
    exclude_file = root / "automation" / "wfrun_excluded_scripts.txt"
    if not exclude_file.is_file():
        return set()

    excluded: set[str] = set()
    for raw in exclude_file.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        line = line.removeprefix("automation/")
        excluded.add(line)
    return excluded


def _should_exclude(root: Path, path: Path, excluded: set[str]) -> bool:
    rel_automation = path.relative_to(root / "automation").as_posix()

    if rel_automation in excluded:
        return True
    if path.name == "__init__.py":
        return True
    if path.name.startswith("wfrun_") and path.name.endswith("_env.sh"):
        return True
    if not _is_runnable(path):
        return True
    return False


def discover_scripts(root: Path) -> list[ScriptEntry]:
    automation = root / "automation"
    if not automation.is_dir():
        return []

    excluded = _load_excluded_paths(root)
    found: list[Path] = []
    for dirpath, _dirnames, filenames in os.walk(automation):
        rel_dir = Path(dirpath).relative_to(automation)
        depth = 0 if rel_dir.as_posix() == "." else len(rel_dir.parts)
        if depth < 1:
            continue
        for name in filenames:
            path = Path(dirpath) / name
            if not path.is_file():
                continue
            if _should_exclude(root, path, excluded):
                continue
            found.append(path)

    entries: list[ScriptEntry] = []
    for path in sorted(found):
        rel = path.relative_to(root).as_posix()
        entries.append(
            ScriptEntry(
                id=rel,
                path=path.resolve(),
                profile=_profile_for_rel(rel),
                kind=_kind_for_path(path),
                runnable=_is_runnable(path),
                group=_group_for_rel(rel),
                description=_read_dash_description(path),
            )
        )
    return entries


def resolve_script(root: Path, script_id: str, entries: list[ScriptEntry] | None = None) -> ScriptEntry:
    normalized = script_id.strip().lstrip("/")
    if ".." in normalized.split("/"):
        raise ValueError("Invalid script path")

    catalog = entries if entries is not None else discover_scripts(root)
    for entry in catalog:
        if entry.id == normalized:
            if not entry.path.is_file():
                raise ValueError("Script file not found")
            if not entry.runnable:
                raise ValueError(f"Unsupported script type: {entry.id}")
            return entry
    raise ValueError("Script not in catalog")


def build_command(script_path: Path) -> list[str]:
    suffix = script_path.suffix.lower()
    if suffix == ".sh":
        return ["bash", str(script_path)]
    if suffix == ".py":
        return ["python3", str(script_path)]
    if suffix in {".yml", ".yaml"}:
        return ["ansible-playbook", str(script_path)]
    if os.access(script_path, os.X_OK):
        return [str(script_path)]
    raise ValueError(f"Unsupported script type: {script_path}")

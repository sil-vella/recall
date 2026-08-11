# dash Write dashboard script runs to timestamped log files
"""Persist dashboard script terminal output to timestamped log files."""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path

LOGS_DIR = Path(__file__).resolve().parent / "logs"


def _safe_script_name(entry_id: str) -> str:
    name = Path(entry_id).name
    safe = re.sub(r"[^\w.\-]", "_", name)
    return safe or "script"


def log_path_for_script(entry_id: str, now: datetime | None = None) -> Path:
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    moment = now or datetime.now()
    timestamp = moment.strftime("%Y%m%d-%H%M%S")
    script_name = _safe_script_name(entry_id)
    return LOGS_DIR / f"{timestamp}-{script_name}.log"


class RunLog:
    def __init__(self, path: Path, script_id: str, cmd: list[str], mode: str) -> None:
        self.path = path
        self._file = path.open("wb")
        self._closed = False
        started = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        header = (
            f"# dutch dashboard run log\n"
            f"# script: {script_id}\n"
            f"# mode: {mode}\n"
            f"# started: {started}\n"
            f"# command: {' '.join(cmd)}\n"
            f"\n"
        )
        self._file.write(header.encode("utf-8"))

    def write(self, data: bytes) -> None:
        if self._closed:
            return
        self._file.write(data)
        self._file.flush()

    def close(self, exit_code: int | None = None) -> None:
        if self._closed:
            return
        self._closed = True
        if exit_code is None:
            footer = "\n\n--- stopped ---\n"
        else:
            footer = f"\n\n--- exit {exit_code} ---\n"
        self._file.write(footer.encode("utf-8"))
        self._file.close()

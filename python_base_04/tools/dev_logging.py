"""Local Flask console logging (stderr). Use ``dev_log(..., LOGGING_SWITCH)`` per module."""

from __future__ import annotations

import logging
import os
import sys
from datetime import datetime
from pathlib import Path


class _GlobalAppendHandler(logging.Handler):
    """Append each formatted log line to ``WFGLOBALOG_GLOBAL_LOG`` (IDE-safe without ``tail``)."""

    def __init__(self, global_path: str, source_tag: str, line_fmt: logging.Formatter) -> None:
        super().__init__()
        self._global_path = global_path
        self._source_tag = source_tag
        self._line_fmt = line_fmt

    def emit(self, record: logging.LogRecord) -> None:
        try:
            line = self._line_fmt.format(record)
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(self._global_path, "a", encoding="utf-8") as f:
                f.write(f"{ts} [{self._source_tag}] {line}\n")
                f.flush()
        except OSError:
            pass


class _FlushingFileHandler(logging.FileHandler):
    """FileHandler that flushes after each record so ``tail -F`` sees lines immediately."""

    def emit(self, record: logging.LogRecord) -> None:
        super().emit(record)
        self.flush()


def _wf_line_formatter() -> logging.Formatter:
    return logging.Formatter("[python] %(levelname)s %(name)s: %(message)s")


def _wf_global_mirror_installed(root: logging.Logger) -> bool:
    return any(getattr(h, "_wf_global_append", False) for h in root.handlers)


def _wf_install_global_mirror(root: logging.Logger, level: int) -> None:
    gp = (os.environ.get("WFGLOBALOG_GLOBAL_LOG") or "").strip()
    st = (os.environ.get("WFGLOBALOG_SOURCE") or "").strip()
    if not gp or not st or _wf_global_mirror_installed(root):
        return
    try:
        Path(gp).parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return
    gh = _GlobalAppendHandler(gp, st, _wf_line_formatter())
    gh._wf_global_append = True  # type: ignore[attr-defined]
    gh.setLevel(level)
    root.addHandler(gh)


def configure_dev_logging() -> None:
    """Attach a single stderr handler with ``[python]`` prefix. Honors ``APP_LOG_LEVEL``."""
    level_name = (os.environ.get("APP_LOG_LEVEL") or "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    root = logging.getLogger()
    line_fmt = _wf_line_formatter()
    if not root.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(line_fmt)
        root.addHandler(handler)
        capture = (os.environ.get("WFGLOBALOG_CAPTURE_FILE") or "").strip()
        if capture:
            try:
                p = Path(capture)
                p.parent.mkdir(parents=True, exist_ok=True)
                fh = _FlushingFileHandler(capture, encoding="utf-8")
                fh.setFormatter(line_fmt)
                fh.setLevel(level)
                root.addHandler(fh)
            except OSError:
                pass
    _wf_install_global_mirror(root, level)
    root.setLevel(level)
    for noisy in ("werkzeug", "urllib3", "httpx"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def dev_log(switch: bool, logger: logging.Logger, level: int, msg: str, *args: object) -> None:
    """Emit ``logger.log`` only when ``switch`` is True."""
    if switch:
        logger.log(level, msg, *args)

"""Local Flask console logging (stderr). Use ``dev_log(..., LOGGING_SWITCH)`` per module."""

from __future__ import annotations

import logging
import os
import sys


def configure_dev_logging() -> None:
    """Attach a single stderr handler with ``[python]`` prefix. Honors ``APP_LOG_LEVEL``."""
    level_name = (os.environ.get("APP_LOG_LEVEL") or "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    root = logging.getLogger()
    if not root.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(
            logging.Formatter("[python] %(levelname)s %(name)s: %(message)s")
        )
        root.addHandler(handler)
    root.setLevel(level)
    for noisy in ("werkzeug", "urllib3", "httpx"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def dev_log(switch: bool, logger: logging.Logger, level: int, msg: str, *args: object) -> None:
    """Emit ``logger.log`` only when ``switch`` is True."""
    if switch:
        logger.log(level, msg, *args)

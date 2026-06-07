"""Gunicorn production configuration for VPS Docker deployment."""

import logging
import os
import sys


def _int_env(name: str, default: int) -> int:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


bind = "0.0.0.0:5001"
workers = _int_env("GUNICORN_WORKERS", 2)
worker_class = "gthread"
threads = _int_env("GUNICORN_THREADS", 4)
timeout = _int_env("GUNICORN_TIMEOUT", 60)
graceful_timeout = 30
keepalive = 5
max_requests = 1000
max_requests_jitter = 100
preload_app = False

accesslog = "-"
errorlog = "-"
loglevel = "info"
capture_output = True

# %(D)s = request duration in microseconds
access_log_format = (
    '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s '
    '"%(f)s" "%(a)s" %(D)s'
)


def on_starting(_server):
    """Configure stdlib logging for slow-request warnings from app.py."""
    root = logging.getLogger()
    if not root.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
        root.addHandler(handler)
    root.setLevel(logging.INFO)

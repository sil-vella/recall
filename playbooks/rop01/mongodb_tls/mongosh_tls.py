"""TLS CLI args for mongosh inside dutch_external_app_mongodb on prod VPS."""

from __future__ import annotations

import os

IN_CONTAINER_CA = "/etc/mongo-tls/ca.pem"
IN_CONTAINER_TLS_ARGS = ("--tls", f"--tlsCAFile={IN_CONTAINER_CA}")


def mongosh_tls_args(*, enabled: bool | None = None) -> list[str]:
    """Return mongosh TLS flags for in-container exec on prod (requireTLS)."""
    if enabled is False:
        return []
    if enabled is True:
        return list(IN_CONTAINER_TLS_ARGS)
    if os.environ.get("MONGO_TLS_ENABLED", "auto") == "0":
        return []
    if os.environ.get("MONGO_TLS_ENABLED", "auto") == "1":
        return list(IN_CONTAINER_TLS_ARGS)
    # Prod VPS playbooks target requireTLS Mongo; default on for rop01 scripts.
    return list(IN_CONTAINER_TLS_ARGS)


def mongosh_tls_shell_prefix(*, enabled: bool | None = None) -> str:
    args = mongosh_tls_args(enabled=enabled)
    return " ".join(args)

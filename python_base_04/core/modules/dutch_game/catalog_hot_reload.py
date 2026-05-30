"""
In-process reload of declarative Dutch catalogs from disk (no Flask restart).

Re-reads JSON, rebuilds module-level maps/revisions, and refreshes aliased
imports in ``tier_rank_level_matcher`` / ``wins_level_rank_matcher``.
"""

from __future__ import annotations

import threading
from typing import Any, Dict

from . import consumables_catalog as cc
from . import table_tiers_catalog as ttc

_reload_lock = threading.Lock()


def reload_all_catalogs() -> Dict[str, Any]:
    """
    Reload table tiers + consumables from their JSON files into process memory.

    Does **not** restart the WSGI worker or Flask app — only replaces cached catalog data.
    """
    with _reload_lock:
        table_result = ttc.reload_from_disk()
        consumables_result = cc.reload_from_disk()
    return {
        "success": True,
        "table_tiers": table_result,
        "consumables_catalog": consumables_result,
    }

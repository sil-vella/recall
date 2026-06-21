"""
In-process reload of declarative Dutch catalogs from disk (no Flask restart).

Re-reads JSON, rebuilds module-level maps/revisions, and refreshes aliased
imports in ``tier_rank_level_matcher`` / ``wins_level_rank_matcher``.
"""

from __future__ import annotations

import threading
from typing import Any, Dict

from . import consumables_catalog as cc
from . import gameplay_profiles_catalog as gpc
from . import table_tiers_catalog as ttc
from .utils import redis_read_cache as read_cache

_reload_lock = threading.Lock()


def reload_all_catalogs(app_manager=None) -> Dict[str, Any]:
    """
    Reload table tiers + consumables from their JSON files into process memory.

    Does **not** restart the WSGI worker or Flask app — only replaces cached catalog data.
    """
    with _reload_lock:
        profiles_result = gpc.reload_from_disk()
        table_result = ttc.reload_from_disk()
        consumables_result = cc.reload_from_disk()
    if app_manager is not None:
        read_cache.delete_prefix(app_manager, "catalog:")
    return {
        "success": True,
        "gameplay_profiles": profiles_result,
        "table_tiers": table_result,
        "consumables_catalog": consumables_result,
    }

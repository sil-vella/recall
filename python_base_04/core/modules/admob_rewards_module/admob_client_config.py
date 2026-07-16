"""Client-facing AdMob config payload for init-config / get-init-data."""

from __future__ import annotations

import hashlib
import json
from typing import Any, Dict

from utils.config.config import Config
from tools.dev_logger import customlog

LOGGING_SWITCH = True


def _platform_units(
    *,
    top: str,
    bottom: str,
    interstitial: str,
    rewarded: str,
) -> Dict[str, str]:
    return {
        "top_banner": top,
        "bottom_banner": bottom,
        "interstitial": interstitial,
        "rewarded": rewarded,
    }


def build_client_admob_payload() -> Dict[str, Any]:
    """Non-secret AdMob unit IDs and rewarded UI knobs for Flutter (per platform)."""
    payload: Dict[str, Any] = {
        "android": _platform_units(
            top=Config.ADMOBS_ANDROID_TOP_BANNER01,
            bottom=Config.ADMOBS_ANDROID_BOTTOM_BANNER01,
            interstitial=Config.ADMOBS_ANDROID_INTERSTITIAL01,
            rewarded=Config.ADMOBS_ANDROID_REWARDED01,
        ),
        "ios": _platform_units(
            top=Config.ADMOBS_IOS_TOP_BANNER01,
            bottom=Config.ADMOBS_IOS_BOTTOM_BANNER01,
            interstitial=Config.ADMOBS_IOS_INTERSTITIAL01,
            rewarded=Config.ADMOBS_IOS_REWARDED01,
        ),
        "rewarded_coins_per_claim": Config.ADMOB_REWARDED_COINS_PER_CLAIM,
        "rewarded_daily_cap": Config.ADMOB_REWARDED_DAILY_CAP,
    }
    if LOGGING_SWITCH:
        customlog(
            "admob_client_config: build payload "
            f"android_rewarded={payload['android']['rewarded']} "
            f"ios_rewarded={payload['ios']['rewarded']} "
            f"coins={payload['rewarded_coins_per_claim']}"
        )
    return payload


def admob_config_revision() -> str:
    """SHA256 prefix of canonical JSON — auto-bumps when any env value changes."""
    canonical = json.dumps(build_client_admob_payload(), sort_keys=True, separators=(",", ":"))
    rev = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]
    if LOGGING_SWITCH:
        customlog(f"admob_client_config: revision={rev}")
    return rev

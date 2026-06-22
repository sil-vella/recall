"""
Apple App Store Server API + StoreKit 2 JWS verification for iOS IAP.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from utils.config.config import Config

_APPLE_ROOT_CERTS_SUBDIR = Path("assets") / "apple_root_certs"


def _app_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _resolve_root_certs_dir() -> Path:
    configured = (Config.APPLE_ROOT_CERTS_DIR or "").strip()
    if configured:
        return Path(configured)
    return _app_root() / _APPLE_ROOT_CERTS_SUBDIR


def _load_private_key() -> Optional[bytes]:
    inline = (Config.APPLE_IAP_PRIVATE_KEY or "").strip()
    if inline:
        return inline.encode("utf-8")
    key_path = (Config.APPLE_IAP_PRIVATE_KEY_FILE or "").strip()
    if not key_path:
        secret_path = read_secret_file("apple_iap_private_key")
        if secret_path:
            return secret_path.encode("utf-8")
        key_path = "/app/secrets/apple-iap-key.p8"
    if os.path.isfile(key_path):
        return Path(key_path).read_bytes()
    return None


def read_secret_file(secret_name: str) -> Optional[str]:
    """Read optional secret file (mirrors config helper paths)."""
    paths = [
        f"/run/secrets/{secret_name}",
        f"/app/secrets/{secret_name}",
        f"./secrets/{secret_name}",
    ]
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if content:
                    return content
        except Exception:
            continue
    return None


def _load_root_certificates() -> List[bytes]:
    cert_dir = _resolve_root_certs_dir()
    certs: List[bytes] = []
    if cert_dir.is_dir():
        for path in sorted(cert_dir.glob("*.cer")):
            try:
                certs.append(path.read_bytes())
            except Exception:
                continue
    return certs


def _parse_environment():
    from appstoreserverlibrary.models.Environment import Environment

    raw = (Config.APPLE_APP_STORE_ENVIRONMENT or "Sandbox").strip().lower()
    if raw in ("production", "prod"):
        return Environment.PRODUCTION
    return Environment.SANDBOX


def apple_billing_configured() -> bool:
    issuer = (Config.APPLE_IAP_ISSUER_ID or "").strip()
    key_id = (Config.APPLE_IAP_KEY_ID or "").strip()
    bundle = (Config.APPLE_BUNDLE_ID or "").strip()
    return bool(issuer and key_id and bundle and _load_private_key() and _load_root_certificates())


@lru_cache(maxsize=1)
def _get_signed_data_verifier():
    from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier

    root_certs = _load_root_certificates()
    if not root_certs:
        return None
    bundle_id = (Config.APPLE_BUNDLE_ID or "").strip()
    if not bundle_id:
        return None
    environment = _parse_environment()
    app_apple_id: Optional[int] = None
    try:
        app_id_raw = (Config.APPLE_APP_ID or "").strip()
        if app_id_raw:
            app_apple_id = int(app_id_raw)
    except (TypeError, ValueError):
        app_apple_id = None
    from appstoreserverlibrary.models.Environment import Environment

    if environment == Environment.PRODUCTION and app_apple_id is None:
        return None
    return SignedDataVerifier(
        root_certs,
        True,
        environment,
        bundle_id,
        app_apple_id,
    )


@lru_cache(maxsize=1)
def _get_api_client():
    from appstoreserverlibrary.api_client import AppStoreServerAPIClient

    private_key = _load_private_key()
    issuer_id = (Config.APPLE_IAP_ISSUER_ID or "").strip()
    key_id = (Config.APPLE_IAP_KEY_ID or "").strip()
    bundle_id = (Config.APPLE_BUNDLE_ID or "").strip()
    if not private_key or not issuer_id or not key_id or not bundle_id:
        return None
    return AppStoreServerAPIClient(
        private_key,
        key_id,
        issuer_id,
        bundle_id,
        _parse_environment(),
    )


def _ms_to_iso(ms: Optional[int]) -> str:
    if not ms:
        return ""
    try:
        return datetime.fromtimestamp(int(ms) / 1000.0, tz=timezone.utc).isoformat()
    except Exception:
        return ""


def _normalize_transaction_payload(decoded: Any) -> Dict[str, Any]:
    transaction_id = str(getattr(decoded, "transactionId", None) or "").strip()
    original_transaction_id = str(getattr(decoded, "originalTransactionId", None) or transaction_id).strip()
    product_id = str(getattr(decoded, "productId", None) or "").strip()
    bundle_id = str(getattr(decoded, "bundleId", None) or "").strip()
    environment = str(getattr(decoded, "environment", None) or "").strip()
    expires_ms = getattr(decoded, "expiresDate", None)
    revocation_ms = getattr(decoded, "revocationDate", None)
    purchase_ms = getattr(decoded, "purchaseDate", None)
    return {
        "transaction_id": transaction_id,
        "original_transaction_id": original_transaction_id,
        "product_id": product_id,
        "bundle_id": bundle_id,
        "environment": environment,
        "expires_at": _ms_to_iso(expires_ms),
        "revoked_at": _ms_to_iso(revocation_ms),
        "purchase_at": _ms_to_iso(purchase_ms),
        "expires_ms": int(expires_ms) if expires_ms else None,
        "revoked_ms": int(revocation_ms) if revocation_ms else None,
    }


def verify_signed_transaction(signed_transaction: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Verify StoreKit 2 JWS from device. Returns (payload, error_message)."""
    signed = (signed_transaction or "").strip()
    if not signed:
        return None, "signed_transaction is required"
    verifier = _get_signed_data_verifier()
    if verifier is None:
        return None, "Apple IAP verification is not configured"
    try:
        from appstoreserverlibrary.signed_data_verifier import VerificationException

        decoded = verifier.verify_and_decode_signed_transaction(signed)
        return _normalize_transaction_payload(decoded), None
    except VerificationException as e:
        return None, f"Invalid signed transaction: {e}"
    except Exception as e:
        return None, f"Transaction verification failed: {e}"


def fetch_transaction_by_id(transaction_id: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Fallback: App Store Server API lookup by transaction id."""
    tid = (transaction_id or "").strip()
    if not tid:
        return None, "transaction_id is required"
    client = _get_api_client()
    if client is None:
        return None, "Apple IAP API client is not configured"
    try:
        from appstoreserverlibrary.api_client import APIException

        response = client.get_transaction_info(tid)
        signed = getattr(response, "signedTransactionInfo", None) or ""
        if not signed:
            return None, "Transaction not found"
        return verify_signed_transaction(signed)
    except APIException as e:
        return None, f"Apple API error: {e}"
    except Exception as e:
        return None, f"Transaction lookup failed: {e}"


def resolve_transaction(
    *,
    signed_transaction: str = "",
    transaction_id: str = "",
    expected_product_id: str = "",
) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Verify JWS or fetch by transaction id; optionally enforce product_id."""
    payload: Optional[Dict[str, Any]] = None
    err: Optional[str] = None

    signed = (signed_transaction or "").strip()
    tid = (transaction_id or "").strip()

    if signed:
        payload, err = verify_signed_transaction(signed)
    elif tid:
        payload, err = fetch_transaction_by_id(tid)
    else:
        return None, "signed_transaction or transaction_id is required"

    if err or not payload:
        return payload, err

    expected = (expected_product_id or "").strip()
    actual = (payload.get("product_id") or "").strip()
    if expected and actual and expected != actual:
        return None, "product_id does not match verified transaction"

    bundle_expected = (Config.APPLE_BUNDLE_ID or "").strip()
    bundle_actual = (payload.get("bundle_id") or "").strip()
    if bundle_expected and bundle_actual and bundle_expected != bundle_actual:
        return None, "bundle_id does not match app configuration"

    if payload.get("revoked_ms"):
        return None, "Transaction has been revoked"

    return payload, None


def subscription_is_active(payload: Dict[str, Any]) -> bool:
    """True when subscription expires in the future and not revoked."""
    if payload.get("revoked_ms"):
        return False
    expires_ms = payload.get("expires_ms")
    if not expires_ms:
        return False
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    return int(expires_ms) > now_ms

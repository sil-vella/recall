#!/usr/bin/env python3
"""Minimal JWT create via OpenSSL CLI — no pip crypto packages.

Supports RS256 (Google service accounts) and ES256 (App Store Connect .p8).
Requires `openssl` on PATH (macOS/Linux usually have it).
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any


def b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _run_openssl(args: list[str], *, data: bytes | None = None) -> bytes:
    try:
        proc = subprocess.run(
            ["openssl", *args],
            input=data,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(
            "openssl not found on PATH — required for Play/App Store JWT (no pip crypto)"
        ) from exc
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"openssl {' '.join(args[:3])}… failed: {err[:400]}")
    return proc.stdout


def _write_temp_pem(pem: str) -> Path:
    fd, name = tempfile.mkstemp(prefix="wf_jwt_", suffix=".pem")
    path = Path(name)
    try:
        os.write(fd, pem.strip().encode("utf-8") + b"\n")
    finally:
        os.close(fd)
    return path


def _der_ecdsa_to_jose(der: bytes, *, size: int = 32) -> bytes:
    """Convert OpenSSL ECDSA DER signature to JWT raw R||S (P-256 → 64 bytes)."""
    if not der or der[0] != 0x30:
        raise RuntimeError("Unexpected ECDSA signature (not DER SEQUENCE)")
    # SEQUENCE length
    idx = 1
    if der[idx] & 0x80:
        n = der[idx] & 0x7F
        idx += 1 + n
    else:
        idx += 1

    def read_int(i: int) -> tuple[bytes, int]:
        if der[i] != 0x02:
            raise RuntimeError("Unexpected ECDSA DER INTEGER")
        i += 1
        ln = der[i]
        i += 1
        val = der[i : i + ln]
        i += ln
        # DER may add a leading 0x00 so the high bit is clear
        if len(val) > size and val[0] == 0x00:
            val = val[1:]
        if len(val) > size:
            val = val[-size:]
        return val.rjust(size, b"\x00"), i

    r, idx = read_int(idx)
    s, _ = read_int(idx)
    return r + s


def sign_digest(alg: str, signing_input: bytes, private_key_pem: str) -> bytes:
    key_path = _write_temp_pem(private_key_pem)
    try:
        if alg == "RS256":
            return _run_openssl(
                ["dgst", "-sha256", "-sign", str(key_path)],
                data=signing_input,
            )
        if alg == "ES256":
            der = _run_openssl(
                ["dgst", "-sha256", "-sign", str(key_path)],
                data=signing_input,
            )
            return _der_ecdsa_to_jose(der, size=32)
        raise RuntimeError(f"Unsupported JWT alg: {alg}")
    finally:
        try:
            key_path.unlink(missing_ok=True)
        except OSError:
            pass


def encode_jwt(
    claims: dict[str, Any],
    *,
    private_key_pem: str,
    algorithm: str,
    headers: dict[str, Any] | None = None,
) -> str:
    alg = algorithm.upper().strip()
    hdr = {"alg": alg, "typ": "JWT"}
    if headers:
        hdr.update(headers)
    hdr.pop("alg", None)
    hdr["alg"] = alg
    header_b64 = b64url(json.dumps(hdr, separators=(",", ":")).encode("utf-8"))
    payload_b64 = b64url(json.dumps(claims, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    sig = sign_digest(alg, signing_input, private_key_pem)
    return f"{header_b64}.{payload_b64}.{b64url(sig)}"

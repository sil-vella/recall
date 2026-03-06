# Auth Logic (Python)

How JWT auth and “revoked” work for `/userauth/` routes (e.g. user search, invite-player).

---

## 1. Request flow

1. **Route prefix** (`app_manager.py` `authenticate_request`):
   - `/userauth/*` → require **JWT**.
   - `/service/*` → require **X-Service-Key** (Dart backend; no JWT, no revoke check).
   - `/public/*` → no auth.

2. **JWT path** (for `/userauth/`):
   - Read `Authorization: Bearer <token>`.
   - Call `jwt_manager.verify_token(token, TokenType.ACCESS)` (no `skip_revoke`).
   - If that returns `None` → **401** (Invalid or expired token).
   - Else set `request.user_id` (and payload) and continue to the route.

So **every** `/userauth/` request is gated by `verify_token`; if it returns `None`, you get 401 before any handler (e.g. user search) runs.

---

## 2. What `verify_token` does

(`jwt_manager.py`)

1. **Decode** JWT (signature + `exp`).
2. **Revoke check** (unless `skip_revoke=True`):
   - `_is_token_revoked(token)`:
     - Decode again to get `type` (e.g. `"access"`).
     - `is_valid = redis_manager.is_token_valid(token_type, token)`:
       - Key: `token:{token_type}:{raw_token}`.
       - **`is_valid = redis.exists(token_key)`** (key must exist in Redis).
     - Return **`not is_valid`** → “revoked” = “Redis says not valid”.
3. **Fingerprint** (optional): if token has `fingerprint`, compare with current request (IP + User-Agent); server-to-server (User-Agent with `Dart`) skips this.
4. **Claims** (e.g. `expected_type`).
5. If any step fails → return `None` → 401.

So: **valid** = decode OK + **Redis key exists** + fingerprint/claims OK.  
**“Token is revoked”** = decode OK but **Redis key missing** (or Redis error).

---

## 3. When is the token key in Redis?

- **On create**: `create_token` (and thus `create_access_token` / `create_refresh_token`) calls `_store_token`:
  - `redis_manager.store_token(token_type, token, expire=ttl)`.
  - TTL = same as JWT `exp` (e.g. `Config.JWT_ACCESS_TOKEN_EXPIRES`, default **3600** s = 1 hour).
- **On refresh** (`/public/refresh`): new access + refresh tokens are created (and stored); **only the old refresh token** is revoked. Old access token is **not** revoked; its key stays until TTL.
- **On logout**: tokens can be revoked (removed from Redis).

So a token is “valid” in Redis only if:
- It was stored at issue (login/refresh), and
- TTL has not elapsed, and
- It wasn’t explicitly revoked (e.g. logout).

---

## 4. Why you see “Token is revoked” (Redis check result: False)

So **“Token is revoked”** here means **“Redis says this token is not valid”** (key missing or error). Common causes:

| Cause | Explanation |
|-------|-------------|
| **Redis key TTL expired** | Access token stored with e.g. 1h TTL. After 1h the key is gone; client may still send the same token from storage → decode OK, Redis says no → “revoked”. |
| **Redis down / wrong instance** | At request time Redis is unreachable or different (e.g. another host/port). `_ensure_connection()` fails or `exists()` errors → `is_token_valid` returns False → “revoked”. |
| **Token never stored** | At login/refresh, `store_token` failed (e.g. Redis down, exception). Token was never written → later request: decode OK, key missing → “revoked”. |
| **Redis flushed / restarted** | All keys lost; existing tokens still decode but keys are gone → “revoked”. |

So the auth logic is: **valid = JWT valid + key present in Redis**. No key (or Redis failure) is treated as revoked and causes 401 before your handler runs.

---

## 5. Config and code references

- **JWT TTL**: `Config.JWT_ACCESS_TOKEN_EXPIRES` (default 3600), `Config.JWT_REFRESH_TOKEN_EXPIRES` (default 604800).
- **Auth middleware**: `app_manager.py` → `authenticate_request` (before_request).
- **Verify**: `jwt_manager.verify_token(token, TokenType.ACCESS)` (no `skip_revoke` for `/userauth/`).
- **Revoke check**: `jwt_manager._is_token_revoked` → `redis_manager.is_token_valid` → `redis.exists(token_key)`.
- **Store on issue**: `jwt_manager._store_token` → `redis_manager.store_token` (same TTL as JWT exp).

---

## 6. Practical checks if 401 happens on user search

1. **Redis**: Same instance as at login? Correct host/port (e.g. local `REDIS_PORT=6380` vs Docker). Run Redis and retry.
2. **TTL**: If the token is old (e.g. > 1h since login and no refresh), Redis key may have expired; log in again or ensure refresh is used and the new access token is sent.
3. **Logs**: “JWT: Token decoded successfully” then “Token is revoked” + “Redis check result: False” → decode OK, Redis says no (key missing or connection/error). Fix Redis or re-issue token.

# Session expired / “Please log in again” investigation

**Status**: In Progress  
**Created**: 2026-05-01  
**Last Updated**: 2026-05-01

## Objective

Understand when and why users see **“Session expired. Please log in again.”** (or similar) messaging, confirm whether it aligns with **expired access tokens**, **expired refresh tokens**, **Redis/session TTL**, or **401 handling**, and document gaps between intended UX and actual behavior (e.g. spurious prompts, missing refresh, or unclear API errors).

## Context (known touchpoints)

Preliminary search surfaced these locations; treat as starting points, not exhaustive proof.

| Area | Path | Notes |
|------|------|--------|
| Flutter user-facing strings | `flutter_base_05/lib/core/managers/auth_manager.dart` | `Session expired. Please log in again.`, inactivity variant, refresh failures |
| Flutter API layer | `flutter_base_05/lib/modules/connections_api_module/connections_api_module.dart` | Default JSON `message` for session/expired-style responses |
| Flutter login / navigation | `flutter_base_05/lib/modules/login_module/login_module.dart` | Navigates to account with `refresh_token_expired`, `token_refresh_failed`, `auth_error` and related copy |
| Game helpers | `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart` | Treats `session expired` / `please log in again` substrings as expected in some pre-login flows |
| Python API | `python_base_04/core/managers/app_manager.py` | Messages like “Please login again…” / “Please login again.” on auth paths |
| Docs | `Documentation/Dutch_game/AUTH_LOGIC.md`, `Documentation/User_Registration/USER_REGISTRATION.md` | Historical notes on TTL / Android “Session expired…” |

## Implementation / investigation steps

- [ ] **Map the message to call path**: From UI or logs, identify whether the string comes from `AuthManager`, `ConnectionsApiModule` response parsing, WebSocket auth, or server JSON `message`.
- [ ] **Trace access token lifecycle**: Login → storage → attach to requests; confirm refresh runs before marking session dead on 401.
- [ ] **Trace refresh token lifecycle**: When refresh fails or returns “expired”, confirm `login_module` / `AuthManager` behavior (clear tokens, navigate, snack/dialog).
- [ ] **Align with backend**: In `python_base_04`, find JWT validation, Redis session TTL, and exact HTTP status + body when access vs refresh is invalid; compare to what Flutter treats as “session expired”.
- [ ] **Reproduce**: Idle until access expiry; force refresh expiry; revoke server-side session; document which user-visible message appears in each case.
- [ ] **False positives**: Check `dutch_game_helpers` and any guest/anonymous paths where “session expired” substring is intentionally ignored vs surfaced to the user.
- [ ] **UX decision**: After root cause(s) are clear, decide if copy, retry logic, silent refresh, or backoff needs change (may spawn a separate implementation plan).

## Current progress

- Repo-wide grep completed; initial file list captured in **Context** above.
- No runtime reproduction or backend trace documented yet.

## Next steps

1. Reproduce with logging enabled on Flutter (`AuthManager`, `ConnectionsApiModule`) and note HTTP status + response body from failing request.
2. Match failing request to Python route / middleware and JWT/redis checks in `python_base_04`.
3. Update this plan with **root cause** and **recommended fix** (or link a follow-up implementation plan).

## Files modified

- _(none yet — investigation plan only)_

## Notes

- Distinguish **access JWT expiry** (often short, refreshable) from **refresh token expiry** or **server session eviction** (user must log in again).
- If the message appears **without** token expiry (e.g. network error mapped to 401), note it explicitly for a separate bug fix.

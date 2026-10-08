# Marketing — token refresh scripts (per platform)

**Status**: In Progress  
**Created**: 2026-08-10  
**Last Updated**: 2026-08-25

## Objective

Keep Facebook / YouTube / TikTok (and AdMob) credentials usable without manual token paste on every expiry. Access tokens auto-refresh; rotated refresh tokens / extended Page tokens are written back to `WFRUN_ENV_FILE`.

## Context

- **YouTube / AdMob / TikTok** already refresh *access* tokens from a stored *refresh* token. `invalid_grant` means the **refresh token itself** was revoked/expired — browser OAuth is required (`*_oauth_get_refresh_token.py`). Auto-renew cannot invent a new refresh token.
- **Facebook** Page tokens: auto-`fb_exchange_token` when debug shows near expiry / invalid (needs `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET`).
- Silent persist of rotated secrets: `publish_common.persist_env_key` / `revenue_common.persist_env_key`.

## Implementation Steps

### Done
- [x] Document required env keys (FB/YT/TT in samples + dashboard doc)
- [x] YouTube / TikTok / Facebook interactive validate+OAuth runners
- [x] Shared `token_renewal.py` (FB extend + YT/TT refresh + persist)
- [x] Wire publish / metrics / dashboard playlist refresh through `token_renewal`
- [x] AdMob refresh via `revenue_common.google_oauth_access_token` (persist rotated refresh)
- [x] `ensure_platform_tokens.py` wfrun runner + preflight before Marketing publish
- [x] Cron preflight via `ensure_marketing_tokens` (alert + abort on re-auth required)
- [x] `deploy_rop01_marketing.sh` syncs YT + FB Page + FB User tokens to rop

### Later
- [ ] TikTok Production Live + swap client credentials when approved
- [ ] Operator re-auth after current `invalid_grant` on YT + AdMob

## Current Progress

Auto-renew path is wired. **Current dashboard errors** (`invalid_grant` on AdMob + YouTube) require one-time browser re-auth; after that, silent refresh/persist should keep them alive.

## Next Steps

1. Re-run `youtube_oauth_get_refresh_token.py` (Brand Account) → write `YOUTUBE_REFRESH_TOKEN`.
2. Re-run `admob_oauth_get_refresh_token.py` → write `ADMOB_REFRESH_TOKEN`.
3. Optionally `ensure_platform_tokens.py` to verify FB/YT/TT.

## Files Modified

- `automation/marketing/token_renewal.py`
- `automation/marketing/ensure_platform_tokens.py`
- `automation/marketing/publish_common.py`
- `automation/marketing/facebook_publish_post.py`
- `automation/marketing/facebook_post_metrics.py`
- `automation/marketing/youtube_publish_video.py`
- `automation/marketing/youtube_post_metrics.py`
- `automation/marketing/tiktok_publish_video.py`
- `automation/revenue/revenue_common.py`
- `automation/revenue/admob_revenue.py`
- `automation/dashboard/serve.py`
- `automation/wfrun_excluded_scripts.txt`
- `Documentation/01_Active_Plans/marketing-token-refresh.md`

## Notes

- Never log full tokens; never commit `.env.local`.
- TikTok often rotates `refresh_token` on each refresh — must persist or the next run dies.
- Google rarely rotates refresh tokens; `invalid_grant` almost always means revoked consent / password change / unused 6 months (testing apps).

## Task Manager

Own Ops card **Marketing token refresh**, not App Dev.

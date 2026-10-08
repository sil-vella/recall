# wfrun Dashboard GUI

**Status**: Live  
**Created**: 2026-07-11  
**Last Updated**: 2026-08-31

## Objective

Browser alternative to the wfrun CLI numbered menu. **Shared code** lives in [`00Utilities/wf_dashboard`](../../../wf_dashboard/) (`dashboard/` + `marketing/`). Product repos keep only `automation/dashboard/data/` (+ `logs/`). Launch with **`dashup`** (not `wfrun`).

## Dashboard tabs

| Tab | Role |
|-----|------|
| **Scripts** (default) | Grouped `# dash` runners + xterm.js PTY (from `$WFRUN_ROOT/automation`) |
| **Task Manager** | Iframe from `TASK_MANAGER_*` env (`embed=1`) |
| **Marketing** | Compose + **Publish** to selected FB/YT/TT only; drafts + publish results in `$WFRUN_ROOT/automation/dashboard/data/`; **Ad campaigns** subtab (Facebook Ads Manager list + campaign insights CSV) |
| **Revenue** | Estimated (+ settled) revenue from AdMob, Google Play GCS exports, App Store Connect; **Downloads** subtab for Play installs + ASC download units (modules under `$WFRUN_ROOT/automation/revenue`) |
| **Documentation** | Scripts-style menu of `Documentation/` dirs + markdown files (case study files excluded) |
| **Case Study** | HTML case studies only (`*case*study*.html`); iframe embed; Overview / Technical in-page |

## Usage

```bash
python3 -m pip install -r ~/Documents/Work/00Utilities/wf_dashboard/requirements.txt
dashup   # pick product → shared serve.py + that repo’s .env.local
```

`dashup` scans `~/Documents/Work` for `app_dev*` with `STANDALONE_DASHBOARD=true` in `.env.local`, prompts by `REPO_BRAND`, then runs `wf_dashboard/dashboard/serve.py` with:

| Env | Value |
|-----|--------|
| `WFRUN_ROOT` | selected product root |
| `WFRUN_ENV_FILE` | `$WFRUN_ROOT/.env.local` |
| `WFRUN_MODE` | `local` |
| `WF_DASHBOARD_ROOT` | `…/00Utilities/wf_dashboard` |

Wrapper: `00Utilities/scripts/00_workflow/shell_commands/dashup` (symlink `~/bin/dashup`). Override scan root with `DASHUP_WORK_ROOT`.

Opt-in flag in `.env.local` / `.env.prod`:

```bash
STANDALONE_DASHBOARD=true
REPO_BRAND=my_product
```

Server binds `127.0.0.1:8765` by default (`WFRUN_DASHBOARD_PORT` / `WFRUN_DASHBOARD_HOST`). Scripts can run concurrently, including **multiple tabs of the same script**. **Run script** on a live tab opens a new tab instead of stopping the current PTY; **Stop** applies to the active tab only.

---

## Facebook / Meta app (Page posting)

Marketing will post to a **Facebook Page** via the Graph API (not a personal profile wall). Secrets live only in `.env.local` / `.env.prod` — never commit them.

### Env keys

```bash
FACEBOOK_APP_ID=...
FACEBOOK_APP_SECRET=...
FACEBOOK_PAGE_ID=...
FACEBOOK_PAGE_ACCESS_TOKEN=...   # long-lived Page token (not User)
```

### 1. Create the Meta app

1. [developers.facebook.com](https://developers.facebook.com/) → create app.
2. Use case: **Manage everything on your Page** (Content management / Pages).
3. **Facebook Login** may be greyed out when that Pages use case is selected — that is OK. Graph API Explorer is enough for app-admin testing.
4. Connect a **Business** portfolio if prompted (unverified is fine while developing).
5. **Create app** → **App settings → Basic** → copy **App ID** and **App Secret** into `.env.local`.

### 2. Permissions (Pages use case)

In the app dashboard, under **Manage everything on your Page**, ensure you can request at least:

- `pages_show_list`
- `pages_manage_posts`
- `pages_read_engagement`
- `pages_manage_metadata` (often needed)
- `read_insights` — **required for impressions / reach / Insights charts** on the Marketing metrics panel (also need Page **ANALYZE** task for the user who minted the token)

`publish_video` only if you will upload video to the Page.

### 3. Mint a User token (Graph API Explorer)

1. Open [Graph API Explorer](https://developers.facebook.com/tools/explorer/).
2. Select **your** Meta app (not the generic “Graph API Explorer” app).
3. Log in as the Facebook user who has **Full access / Admin** on the target Page (same person as in Meta Business Suite → Page access).
4. **Get User Access Token** with the page permissions above (Explorer may only offer `pages_show_list` until the use case unlocks the rest — generate with what is available, then fix scopes in the app if needed).
5. Confirm identity: `GET /me?fields=id,name`.

### 4. Resolve Page ID + Page token

**Classic path** (classic Pages listed on the user):

```text
GET /me/accounts?limit=100
```

Each Page entry includes `id` and `access_token`.

**Business-owned Page quirk:** `/me/accounts` often **omits** Pages that live mainly as Business assets. If the Page is missing:

1. Copy the Page ID from Business Suite → Accounts → Pages → (Page) / Page settings.
2. With the **User** token still in Explorer:

```text
GET /{PAGE_ID}?fields=id,name,access_token
```

3. Use that response’s `access_token` as the **Page** token (paste it into Explorer’s Access Token field).

Optional Business routes when you have `business_management`:

```text
GET /me/businesses
GET /{BUSINESS_ID}/owned_pages?fields=id,name,access_token
```

### 5. Verify token type before posting

1. Paste the candidate token into [Access Token Debugger](https://developers.facebook.com/tools/debug/accesstoken/).
2. Confirm:
   - **Type:** `Page` (not User)
   - **Page / Profile ID:** your target Page
   - **Scopes:** include `pages_manage_posts` (and related)
   - **Valid:** True
3. Click **Extend Access Token** and copy the **new long-lived** token (green result). Short-lived Explorer tokens die in ~1–2 hours; the extended Page token lasts much longer (Debugger shows an expiry date). Meta does **not** auto-refresh the value stored in `.env.local` — when it expires or you revoke the app / change password, regenerate + extend again (see [marketing-token-refresh.md](../01_Active_Plans/marketing-token-refresh.md)).

### 6. Smoke-test publish

In Explorer, Access Token = **Page** token:

```text
POST /{PAGE_ID}/feed
```

Param: `message` = a short test string. Success looks like `{ "id": "{PAGE_ID}_..." }` and the post appears on the Page.

Save to `.env.local`:

```bash
FACEBOOK_PAGE_ID={PAGE_ID}
FACEBOOK_PAGE_ACCESS_TOKEN={extended page token}
```

### Gotchas (from setup)

| Symptom | Likely cause |
|---------|----------------|
| `/me/accounts` empty / wrong Pages | Wrong Facebook login vs Page Admin in Business Suite |
| Target Page missing from `/me/accounts` | Business-owned Page — use `GET /{page-id}?fields=access_token` |
| `#200` / cannot post | Access Token field still has a **User** token — Debugger must say **Type: Page** |
| Login use case greyed out | Normal with **Manage everything on your Page**; Explorer + app admin is enough for now |
| Pending email invite in Business Suite | Separate person entry until accepted — use the Active Full-access Facebook user |

### Out of scope (for now)

- TikTok Production Live swap (keep Sandbox until approved)
- YouTube Studio-only features (related video pill, etc.)

### Publish runners (`00Utilities/wf_dashboard/marketing/`)

| Script | Role |
|--------|------|
| `facebook_publish_post.py` | Page feed / link / photo / video; caption = title + `\n` + description |
| `youtube_publish_video.py` | Resumable `videos.insert` + optional `playlistItems.insert` |
| `tiktok_publish_video.py` | Direct Post FILE_UPLOAD; caption = title + `\n` + description |
| `publish_common.py` | Shared caption merge + env helpers |

Dashboard **Publish** (`POST /api/marketing/posts` multipart): saves draft + media, then runs **only** the platforms checked on that post.

Caption rules: YouTube uses title and description separately; Facebook and TikTok merge `title\ndescription` (hashtags appended).

### Token refresh runners (`wf_dashboard/marketing/` via product shims)

| Script | Role |
|--------|------|
| `facebook_oauth_get_tokens.py` | Browser OAuth → User + Page tokens (+ Ads scopes) |
| `facebook_validate_page_token.py` | `debug_token` + Page smoke; optional extend/remint |
| `youtube_oauth_get_refresh_token.py` | One-time Brand Account OAuth → refresh token |
| `youtube_refresh_access_token.py` | Refresh access token (~1h) from refresh token |
| `tiktok_oauth_get_refresh_token.py` | One-time Login Kit → refresh token |
| `tiktok_refresh_access_token.py` | Refresh access token (~24h); may rotate refresh token |

```text
dashup → Scripts → marketing → facebook_oauth_get_tokens.py
dashup → Scripts → marketing → youtube_refresh_access_token.py
dashup → Scripts → marketing → tiktok_refresh_access_token.py
```

These prompt to write rotated/new tokens into `WFRUN_ENV_FILE` when needed (default Yes).

### YouTube (Desktop OAuth)

Env keys (never commit):

```bash
YOUTUBE_CLIENT_ID=...
YOUTUBE_CLIENT_SECRET=...
YOUTUBE_REFRESH_TOKEN=...   # from one-time browser auth (Brand Account if used)
YOUTUBE_CHANNEL_ID=...      # e.g. from channels.list?mine=true
YOUTUBE_CATEGORY_ID=20      # Gaming — used on videos.insert (fallback 22)
```

One-time refresh token (after Cloud Console Desktop client + scopes + test user):

Scopes used by the OAuth script: `youtube.upload` + `youtube.force-ssl` (force-ssl is required to add videos to playlists after upload; upload alone cannot set playlist). Re-run OAuth after scope changes.

```text
wfrun → automation/marketing/youtube_oauth_get_refresh_token.py
```

After browser consent the script prompts to write `YOUTUBE_REFRESH_TOKEN` into `WFRUN_ENV_FILE` (default Yes). Sign in as the channel owner / Brand Account. Re-run if you change scopes (old refresh tokens keep the previous scope set).

---

## Revenue tab (Play · App Store · AdMob)

Official surfaces (not Play Developer Reporting API — that is vitals only):

| Source | Estimated | Settled |
|--------|-----------|---------|
| **AdMob** | `networkReport:generate` metric `ESTIMATED_EARNINGS` (micros) | n/a via report scope |
| **Google Play** | GCS `sales/salesreport_YYYYMM.zip` | GCS `earnings/earnings_YYYYMM.zip` |
| **Downloads (Play)** | GCS `stats/installs/installs_<package>_YYYYMM_overview.csv` (Daily User Installs) | — |
| **Downloads (App Store)** | `salesReports` product types `1` / `1-B` / `F1` / `1F` units | — |
| **App Store** | `GET /v1/salesReports` (SALES SUMMARY) | `GET /v1/financeReports` (FINANCIAL, Finance role) |

### Env keys

```bash
ADMOB_PUBLISHER_ID=pub-...
ADMOB_CLIENT_ID=...
ADMOB_CLIENT_SECRET=...
ADMOB_REFRESH_TOKEN=...   # wfrun → automation/revenue/admob_oauth_get_refresh_token.py

PLAY_GCS_BUCKET=pubsite_prod_rev_...   # Play Console → Download reports → Copy Cloud Storage URI
PLAY_SERVICE_ACCOUNT_JSON=/absolute/path/to/sa.json
PLAY_PACKAGE_NAME=com.example.app      # optional filter

ASC_ISSUER_ID=...
ASC_KEY_ID=...
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_XXX.p8
ASC_VENDOR_NUMBER=...
ASC_APP_APPLE_ID=...                   # optional filter
```

### Setup notes

1. **AdMob** — Google Cloud project with AdMob API enabled; Desktop OAuth client; scope `admob.report`. Run the OAuth script via wfrun once.
2. **Play** — Create a service account, download JSON key, add the SA email as a Play Console user with access to financial reports. Copy the `pubsite_prod_rev_…` bucket id. Scope used: `devstorage.read_only`.
3. **App Store Connect** — Users and Access → Integrations → App Store Connect API key. Sales reports need Sales/Admin; Finance reports need Finance (or Admin / Account Holder). Vendor number from Payments and Financial Reports.

Dashboard APIs: `GET /api/revenue/summary`, `GET /api/revenue/series` (`sources`, `kind=estimated|settled`, `from`, `to`).

Play / App Store JWT signing uses **OpenSSL on PATH** (`automation/revenue/jwt_openssl.py`) — no extra pip crypto packages beyond the dashboard’s existing `aiohttp` requirement.

---

## Implementation notes (dashboard core)

- CLI `wfrun` wrapper unchanged — GUI is one more script in the menu.
- Discovery: `script_discovery.py` + `wfrun_excluded_scripts.txt`.
- Docs discovery: `docs_discovery.py` — `GET /api/docs`, `GET /api/case-studies`, `GET /api/docs/content?path=…`.
- Frontend env: `env_for_script.py` merges dart-defines for Flutter runners.
- Marketing API: `GET/POST /api/marketing/posts`, `GET /api/marketing/posts/{id}`, `GET /api/marketing/posts/{id}/metrics/facebook`, `GET /api/marketing/platform-posts?platform=…`, `GET /api/marketing/metrics/facebook?object_id=…`, `GET /api/marketing/youtube/playlists`.
- Facebook metrics: engagement via Page token; lifetime Insights need `read_insights` (see permissions above).
- Marketing sub-tabs: **Saved** (local drafts) vs **Platform posts** (remote Page posts; FB live, YT/TT later).
- Revenue API: `GET /api/revenue/summary`, `GET /api/revenue/series`, `GET /api/downloads/series` — see § Revenue above.
- [dashboard-revenue-tab.md](../01_Active_Plans/dashboard-revenue-tab.md) — Revenue tab plan

## Related

- [dashboard-main-tabs.md](../01_Active_Plans/dashboard-main-tabs.md) — tabs / Marketing / Docs / Case Study UI
- [dashboard-revenue-tab.md](../01_Active_Plans/dashboard-revenue-tab.md) — Revenue tab (Play / ASC / AdMob)
- [marketing-post-metrics.md](../01_Active_Plans/marketing-post-metrics.md) — post detail metrics (FB → YT → TT)
- [marketing-token-refresh.md](../01_Active_Plans/marketing-token-refresh.md) — per-platform token refresh scripts
- [task-manager.md](task-manager.md) — Task Manager iframe + API
- [wfrun.md](wfrun.md) — CLI wrapper

# rop01 cron — social auto-post from video folders

**Status**: In Progress  
**Created**: 2026-08-11  
**Last Updated**: 2026-08-11

## Hostinger storage — decided

**Cron poster lives on rop01.** Hostinger holds queues + logs (SSH/SFTP `mixta_mt`).  
**Local upload** (Mac / wfrun) fills the queue.

| Role | Path |
|------|------|
| Per-product video queue | `/home/u877877481/rop01/marketing/<product>/videos/` |
| Script run logs | `/home/u877877481/rop01/marketing/logs/` |
| Product name | folder under `marketing/` (= `REPO_BRAND` for that product install) |

## Scripts

| Script | Where | wfrun |
|--------|-------|-------|
| `upload_queue_to_hostinger.py` | Mac | listed |
| `cron_social_auto_post.py` | rop01 cron | **excluded** |

### Cron access (locked)

rop01 uses **SSH/SFTP `mixta_mt`**: list/pull video dir to a temp dir → publish via existing FB/YT/TT helpers → on success remote-delete `video_***` + write rotation log. Not a local Hostinger mirror.

### Cron behavior

1. List products under `marketing/` (exclude `logs/`), alpha sort.
2. Newest `logs/<YYYYMMDDTHHMMSS>_<product>.log` → last product; pick **next** (wrap).
3. First `video_***` by index; if none → `empty_queue` log, advance (same run).
4. Pull folder; read `post_data.json`; latest `00renders/render_00*.mp4`.
5. Publish selected platforms (default **facebook + youtube**; TikTok stripped until audit).
6. **All selected platforms must succeed** → delete remote `video_***`, write success log, prune to **last 3** rotation logs.
7. **Any publish failure** → no rotation log, no delete.

```bash
# on rop01
python3 /opt/marketing/scripts/cron_social_auto_post.py --env-file /opt/marketing/env/.env
python3 /opt/marketing/scripts/cron_social_auto_post.py --dry-run --env-file /opt/marketing/env/.env
```

**Install path (rop01):** `/opt/marketing/{scripts,env,logs}/` — scripts + FB/YT/TT helpers; tokens in `env/.env` (mode 600); crontab stdout → `logs/`.
### `post_data.json` (Marketing dash contract)

Same shape as dashboard compose `buildPayload()` (media is the latest `00renders/render_00*.mp4`, not a field here):

```json
{
  "platforms": ["facebook", "youtube", "tiktok"],
  "title": "…",
  "description": "…",
  "hashtags": ["Tag"],
  "facebook": {
    "post_type": "feed",
    "link": "",
    "schedule_at": null,
    "publish_mode": "now"
  },
  "youtube": {
    "privacy": "private",
    "tags": ["Tag"],
    "publish_at": null,
    "playlist_id": null,
    "playlist_title": null
  },
  "tiktok": {
    "privacy_level": "SELF_ONLY",
    "disable_comment": false,
    "disable_duet": false,
    "disable_stitch": false,
    "schedule_at": null
  }
}
```

Empty `{}` still works (all platforms; title = folder name). Template filled on arcori `video_004` (local + Hostinger).

## Implementation Steps

- [x] Hostinger roots + product rotation / empty / fail / delete rules
- [x] Upload runner `upload_queue_to_hostinger.py`
- [x] Hostinger access from rop01 = SSH `mixta_mt` pull
- [x] Cron runner `cron_social_auto_post.py` (excluded from wfrun)
- [x] Full success = all selected platforms ok
- [x] Install cron on rop01 — `/etc/cron.d/marketing-social` daily **13:00 Europe/Amsterdam** (`CRON_TZ`)
- [ ] Smoke-test dry-run then live on one video
- [ ] Fill real `post_data.json` on queued videos (currently `{}` in sample campaigns)
- [ ] Document operator runbook

## Current Progress

- Cron orchestrator at `/opt/marketing/scripts/` on rop01; env at `/opt/marketing/env/.env`.
- Crontab: `/etc/cron.d/marketing-social` → 13:00 Amsterdam → log `/opt/marketing/logs/cron_social.log`.
- Reuses `facebook_publish_post` / `youtube_publish_video` (TikTok publish disabled in cron until app audit).
- **Token preflight** before publish: `ensure_marketing_tokens(facebook,youtube)`. On failure → alert email, exit 2, queue untouched.
- **Deploy tokens** from Mac: `automation/marketing/deploy_rop01_marketing.sh` syncs `YOUTUBE_REFRESH_TOKEN`, `FACEBOOK_PAGE_ACCESS_TOKEN`, `FACEBOOK_USER_ACCESS_TOKEN` → rop env.

## Next Steps

1. Live smoke when ready (YT private / TT SELF_ONLY still set on video_004).
2. Document operator runbook.
## Files Modified

- `automation/marketing/cron_social_auto_post.py`
- `automation/marketing/upload_queue_to_hostinger.py` (restored on template)
- `automation/wfrun_excluded_scripts.txt`
- `Documentation/01_Active_Plans/rop01-cron-social-auto-post.md`
- `Documentation/01_Active_Plans/00_MASTER_PLAN.md`

## Notes

- Never log tokens. Cron uses `--env-file` / exported prod env on rop01.
- TikTok cron publish disabled (`DISABLED_PLATFORMS`) until Production Live / audit — was blocking rotation and re-posting FB/YT duplicates daily.
- Partial platform success still counts as **failure** for delete/rotation (manual cleanup if needed).
- Upload script + Hostinger verify already done for arcori (`video_004`…`008`).

## Case study

n/a — ops/marketing pipeline.

## Task Manager

Own Ops card **rop01 cron — social auto-post**, not App Dev.

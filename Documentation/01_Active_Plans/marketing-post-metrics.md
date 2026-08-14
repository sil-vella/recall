# Marketing dashboard — post metrics (FB → YT → TT)

**Status**: In Progress  
**Created**: 2026-08-14  
**Last Updated**: 2026-08-14

## Objective

Show live post metrics on Marketing, and browse **all** remote platform posts (not only GUI-saved drafts), filtered by platform.

## Implementation Steps

- [x] Facebook: `facebook_post_metrics.py` — engagement summaries + **full** lifetime Insights (batched; partial skip on deprecated metrics) when permitted
- [x] API: `GET /api/marketing/posts/{id}/metrics/facebook` (saved drafts)
- [x] Marketing detail UI: Metrics panel + Refresh (FB)
- [x] Document `read_insights` for full FB Insights
- [x] Marketing sub-tabs: **Saved** (GUI) vs **Platform posts** (remote)
- [x] API: `GET /api/marketing/platform-posts?platform=facebook` (+ paging)
- [x] API: `GET /api/marketing/metrics/facebook?object_id=…` for remote posts
- [x] YouTube platform list (`playlistItems` on uploads) + `videos.list?part=statistics` on detail
- [x] API: `GET /api/marketing/platform-posts?platform=youtube` (+ paging)
- [x] API: `GET /api/marketing/metrics/youtube?object_id=…` + saved-post metrics route
- [ ] TikTok platform list after `video.list` (+ re-auth)

## Current Progress

- **Saved** — drafts/publishes from the dashboard + FB/YT metrics on detail when that platform published.
- **Platform posts** — Facebook + YouTube lists (**5 per page**, platform filter + Load more). List is lightweight (no engagement/stats). Open a row → detail loads live metrics. TikTok filter returns “not wired yet” (501).

## Next Steps

1. TikTok platform browser + metrics after `video.list`.

## Files Modified

- `automation/marketing/facebook_post_metrics.py`
- `automation/marketing/youtube_post_metrics.py`
- `automation/dashboard/serve.py`
- `automation/dashboard/static/index.html`
- `automation/dashboard/static/marketing.js`
- `automation/dashboard/static/style.css`
- `automation/wfrun_excluded_scripts.txt`
- `Documentation/01_Active_Plans/marketing-post-metrics.md`
- `Documentation/01_Active_Plans/00_MASTER_PLAN.md`
- `Documentation/00_System_Wide/wfrun-dashboard-gui.md`
- `Documentation/01_Active_Plans/02_CASE_STUDY.md`

## Notes

- Saved list stays local JSON; Platform posts hit live APIs.
- Never log tokens. Metrics are fetched live.
- YouTube uses the same OAuth refresh credentials as publish (`YOUTUBE_*`).
- Task Manager: n/a for this template repo — track in this plan only.

## Case study

[02_CASE_STUDY.md](02_CASE_STUDY.md) §15 — Marketing metrics + platform posts browser (FB first).

## Task Manager

n/a for this template repo — track progress in this plan only.

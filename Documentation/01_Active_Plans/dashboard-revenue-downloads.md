# Dashboard — Revenue → Downloads subtab

**Status**: Completed  
**Created**: 2026-08-18  
**Last Updated**: 2026-08-18

## Objective

Add a **Downloads** subtab under Revenue (not Marketing) showing per-store install/download counts for Play and App Store, using the same store credentials as revenue.

## Implementation Steps

- [x] Play: read GCS `stats/installs/installs_<package>_YYYYMM_overview.csv` (Daily User Installs)
- [x] App Store: salesReports free/paid app download units (product types `1` / `1-B` / `F1` / `1F`)
- [x] `collect_downloads` + `GET /api/downloads/series`
- [x] Ledger: `last_downloads_load` + `download_filters`; `active_subtab` includes `downloads` (do not mix into revenue money entries)
- [x] UI: Downloads subtab (Play / App Store, date range, units table + totals)
- [x] Port to Dutch + Arcori

## Current Progress

Downloads subtab live under Revenue in template, Dutch, and Arcori. Play smoke-test OK (overview CSVs).

## Next Steps

1. Restart dashboard and Refresh Downloads (ASC daily loop can take a while for wide ranges).

## Files Modified

- `Documentation/01_Active_Plans/dashboard-revenue-downloads.md`
- `Documentation/01_Active_Plans/dashboard-revenue-tab.md`
- `Documentation/00_System_Wide/wfrun-dashboard-gui.md` (if touched)
- `automation/revenue/play_revenue.py`
- `automation/revenue/appstore_revenue.py`
- `automation/revenue/fetch_downloads.py`
- `automation/revenue/revenue_common.py`
- `automation/dashboard/serve.py`
- `automation/dashboard/static/index.html`
- `automation/dashboard/static/revenue.js`

## Notes

- Downloads live under Revenue because data comes from Play GCS / ASC sales — same pipelines as money, not the social Marketing desk.
- Play overview CSVs are often UTF-16.
- All-time revenue KPIs stay money-only; Downloads has its own cached last load.

## Case study

n/a — ops dashboard surface; product case study unchanged.

## Task Manager

Own Ops card **Dashboard Revenue tab** (same workstream as [dashboard-revenue-tab.md](dashboard-revenue-tab.md)), not App Dev.

# Dashboard — Revenue tab (Play · App Store · AdMob)

**Status**: Mostly done  
**Created**: 2026-08-14  
**Last Updated**: 2026-08-15

## Objective

Add a **Revenue** tab to the wfrun dashboard that shows estimated (and settled) revenue from Google Play, App Store Connect, and AdMob using official reporting surfaces.

## Implementation Steps

- [x] Document APIs + env keys (this plan + `wfrun-dashboard-gui.md` + `.env.*.sample`)
- [x] Helpers: AdMob network report (`ESTIMATED_EARNINGS`)
- [x] Helpers: Play GCS estimated sales CSV
- [x] Helpers: App Store Connect `salesReports`
- [x] Normalize series + dash `GET /api/revenue/*` + Revenue tab UI
- [x] AdMob OAuth setup script; document Play SA/bucket + ASC JWT
- [x] Settled: Play earnings zip + ASC `financeReports` + Settled sub-view
- [x] Revenue / Expense sub-tabs; persisted KPI cards; expense form + ledger JSON
- [x] Full tab persistence in `revenue_ledger.json` (filters, last_load table, KPIs, expenses); all-time = tracked coverage

## Current Progress

v1 estimated + settled wired; Revenue/Expense sub-tabs with persisted all-time + month KPIs and local expense ledger.

## Next Steps

1. Fill env credentials and smoke-test each source.
2. Optional: AdMob mediation report if third-party mediation matters.

## Files Modified

- `Documentation/01_Active_Plans/dashboard-revenue-tab.md`
- `Documentation/01_Active_Plans/00_MASTER_PLAN.md`
- `Documentation/00_System_Wide/wfrun-dashboard-gui.md`
- `.env.local.sample` / `.env.prod.sample`
- `automation/revenue/*`
- `automation/dashboard/serve.py`
- `automation/dashboard/static/*`
- `automation/dashboard/requirements.txt`
- `automation/wfrun_excluded_scripts.txt`

## Notes

- Play **Developer Reporting API** is vitals-only — financials come from the private GCS bucket CSVs.
- Estimated ≠ bank payout. Settled lags (~monthly).
- Never log tokens / `.p8` / service-account JSON.
- Play/ASC JWTs: OpenSSL CLI via `jwt_openssl.py` (no PyJWT pip dep).
- Task Manager: n/a for this template repo — track in this plan only.

## Case study

n/a for template narrative HTML unless productizing later.

## Task Manager

n/a for this template repo — track progress in this plan only.

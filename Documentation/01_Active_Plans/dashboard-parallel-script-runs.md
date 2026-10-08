# Dashboard: parallel runs of the same script

**Status**: Completed  
**Created**: 2026-08-20  
**Last Updated**: 2026-08-20

## Objective

Port the template Scripts-tab behavior: re-running a live runner opens a **new terminal tab** instead of stopping the existing PTY. Also add DOOGEE Note 58 (`NOTE58000000021664`) next to OnePlus on `launch_android.sh`.

## Implementation Steps
- [x] Key server PTY sessions by uuid, not script id
- [x] On **Run script** while the active tab is running: spawn a new tab and start there
- [x] Stop / close still apply only to the active tab
- [x] Distinct log files when two runs start in the same second
- [x] `launch_android.sh` device 2 = DOOGEE Note 58 (`note58` / `doogee`)

## Current Progress

Ported from the template (`dashboard-parallel-script-runs.md`).

## Next Steps

None for this behavior. Restart the dashboard so `serve.py` is picked up.

## Files Modified
- `automation/dashboard/serve.py`
- `automation/dashboard/run_log.py`
- `automation/dashboard/static/app.js`
- `automation/dashboard/static/index.html`
- `automation/dashboard/static/style.css`
- `automation/frontend/launch_android.sh`
- `Documentation/01_Active_Plans/00_MASTER_PLAN.md`
- `Documentation/01_Active_Plans/case-study-dutch-card-game.html`
- `Documentation/01_Active_Plans/dashboard-parallel-script-runs.md`

## Notes

- Idle / exited tabs still reuse on Run. Only a **running** tab forces a new instance.
- Stop is per-tab.

## Case study

Brief ops mention in [case-study-dutch-card-game.html](case-study-dutch-card-game.html) Technical; full Scripts PTY narrative stays on the template ops case study.

## Task Manager

Skipped — `TASK_MANAGER_*` / `TM_USERNAME` / `TM_PASSWORD` not set in this repo’s `.env.local`.

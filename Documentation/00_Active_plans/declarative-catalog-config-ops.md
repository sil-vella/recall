# Declarative catalog JSON — ops & reload strategy

**Status**: Planned (not started)  
**Created**: 2026-05-28  
**Last Updated**: 2026-05-28

## Objective

Make updates to Dutch declarative configs safe and predictable without unnecessary player disruption, and avoid assuming that mounting JSON or splitting containers removes the need for process reload.

**Related (done elsewhere):** Cosmetic media 404s fixed via nginx proxy + Flask `app_media` volume mount — not part of this plan.

## Problem

| Area | Behavior today |
|------|----------------|
| Flask catalogs | JSON under `python_base_04/core/modules/dutch_game/config/` loaded **once at import** into module globals (`_CANONICAL_DOC` in `consumables_catalog.py`, `progression_catalog.py`, `achievements_catalog.py`, `table_tiers_catalog.py`) |
| Deploy | Baked into `dutch_flask_app` image via `COPY core/`; optional env paths (`DUTCH_*_PATH`) still read at import only |
| Restart impact | `docker compose` restart Flask → short API blip; **in-progress WS games** run on Dart and are not torn down, but shop / `get-user-stats` / match-start coin deduct can fail briefly |
| Dart WS | Own copies / in-memory stores for `table_tiers.json`, `ProgressionConfigStore` (synced from Python); progression/table-tier rule changes may need **Dart restart** too |
| Clients | Revision hashes on `get-user-stats`; apps refresh catalog on next stats call after server reload |

Mounting `config/` into the container **does not** hot-reload; a Flask/Gunicorn restart is still required until code loads catalogs lazily or exposes a reload hook.

## Options (pick one track)

### A — Keep current model (minimal)

- Edit JSON in repo → rebuild/push Flask image → deploy (`06` + `08`) → restart `dutch_flask-external`
- Use quiet window for economy/progression changes; Flask-only restart for consumables/achievements-only changes
- Keep Dart `table_tiers` / progression files in sync when those JSONs change; restart Dart if WS rules must update immediately

### B — Ops convenience (no new service)

- Bind-mount host config into Flask at `/app/core/modules/dutch_game/config` (or use `DUTCH_*_PATH`)
- Still restart Flask after JSON edits; avoids full image rebuild for catalog-only tweaks
- Document which configs require Dart restart

### C — Catalog service (larger)

- Small read-only service serving JSON + revision hashes; Flask/Dart cache by revision
- Rolling deploy or reload-on-read on catalog pod only; narrow blast radius vs monolithic Flask restart
- Requires refactor away from import-time `CONSUMABLES_CATALOG_*` constants

### D — Code: lazy load / admin reload (medium, in-process)

- Load JSON per request or on revision file change; optional `POST /admin/reload-catalogs` (authenticated)
- Stays in Flask; no extra container; still brief worker reload if using gunicorn HUP

## Implementation steps

- [ ] Decide track (A–D) with product/ops constraints (how often catalogs change)
- [ ] Document restart matrix (Flask only vs Flask + Dart) per config file
- [ ] If B: add compose volume + host path convention on VPS
- [ ] If C/D: design revision contract (already used by `get-user-stats`) and migration order (consumables first — Flask-only)
- [ ] Update `playbooks/rop01/00_documentation_and_instructions.md` with deploy checklist

## Config files reference

| File | Primary consumer | Dart restart? |
|------|------------------|---------------|
| `consumables_catalog.json` | Flask shop / purchases | No |
| `achievements_config.json` | Flask + client bootstrap | No |
| `progression_config.json` | Flask + Dart matchmaking | Often yes |
| `table_tiers.json` | Flask + Dart `level_matcher` | Often yes |

Deck/hands YAML live under `dart_bkend_base_01/.../config/` and Flutter `assets/` — separate from this JSON set.

## Next steps

1. Confirm desired change frequency (rare releases vs live tuning).
2. If rare: stay on **A** and add a short ops note only.
3. If live tuning: spike **D** (lazy load + revision) before **C** (new container).

## Files modified

*(none yet — planning only)*

## Notes

- Separate catalog container is justified for **frequent deploys / multiple consumers**, not for avoiding game interruption alone.
- Clients already handle catalog updates via revision; no Flutter change required for server-side reload strategy.
- See `Documentation/Dutch_game/CONSUMABLES_COSMETICS_MVP.md`, `Documentation/Consumables/DECLARATIVE_CATALOG.md`, `Documentation/SSOT_DECLARATIONS/`.

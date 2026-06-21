# Adding table tiers, special events & shop items — plus hot reload

Operational guide for **declarative catalog changes** without an app release: what to edit, where media lives, how the server picks up JSON, and how clients refresh.

**Related SSOT:**

| Topic | Doc |
|-------|-----|
| Table tiers & special events schema | [TABLE_TIERS.md](./TABLE_TIERS.md) |
| Gameplay rule profiles | [GAMEPLAY_PROFILES.md](./GAMEPLAY_PROFILES.md) |
| Shop consumables schema | [CONSUMABLES.md](./CONSUMABLES.md) |
| Client revision / init envelope | [INIT_DATA.md](./INIT_DATA.md) |
| Extended consumables ops | [../Consumables/DECLARATIVE_CATALOG.md](../Consumables/DECLARATIVE_CATALOG.md) |

---

## Three catalog surfaces (quick map)

| What you add | Canonical JSON | Media root | In-game / UI |
|--------------|----------------|------------|--------------|
| **Standard table tier** | `table_tiers.json` → `tiers[]` | Tier back graphics (bundled / `table-tier-back`) | Quick Join carousel, room `game_level`, felt + backdrop |
| **Special event** | `table_tiers.json` → `special_events[]` | `app_media/media/event_media/<event_id>/` | Special Events tab, event match styling, Game Ended modal |
| **Gameplay profile** | `gameplay_profiles.json` → `profiles{}` | — | Rule preset linked by `special_events[].gameplay_profile_id` |
| **Shop cosmetic** | `consumables_catalog.json` → `items[]` | `app_media/media/table_design/` or `card_back/` | Cosmetics shop, equipped overlay / card back |

**Canonical JSON paths (edit these):**

- [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json)
- [gameplay_profiles.json](../../python_base_04/core/modules/dutch_game/config/gameplay_profiles.json)
- [consumables_catalog.json](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json)

**Mirror (Dart WS bundled fallback):**

- [dart_bkend_base_01/config/table_tiers.json](../../dart_bkend_base_01/config/table_tiers.json)
- [dart_bkend_base_01/config/gameplay_profiles.json](../../dart_bkend_base_01/config/gameplay_profiles.json)

Keep mirrors in sync when you change tiers/events/profiles.

---

## Media layout & naming

### Standard table tier — back graphic

Tier `style.back_graphic_file` resolves to:

```http
GET {API}/public/dutch/table-tier-back/<filename>
```

Example filenames already in use: `home-table-backgraphic_002.webp`, `local-table-backgraphic.webp`, `town-table-backgraphic.webp`, `city-table-backgraphic.webp`.

No per-tier folder under `app_media/` for these — they ship with the Python static tier-back bundle unless you extend that pipeline.

### Special event — `event_media/<event_id>/`

One directory per `special_events[].id`:

```text
app_media/media/event_media/cards_night/
  cards_night_background.webp
  table_design_overlay_cards_night.webp
```

| File | JSON key | Used for |
|------|----------|----------|
| `{event_id}_background.webp` | `metadata.end_match_modal.background_image_file` | Lobby Special Events carousel + Game Ended modal hero |
| `table_design_overlay_{event_id}.webp` | `style.overlay_image_file` | In-game felt overlay only (full-bleed, 1024×576 WebP) |

Optional (same folder): `metadata.intro_video_file`, `metadata.audio_file` → server injects `*_url` under `event_media/<event_id>/`.

Served at:

```http
GET {API}/app_media/media/event_media/<event_id>/<filename>
```

See also: [app_media/media/event_media/README.txt](../../app_media/media/event_media/README.txt).

### Shop table design — `table_design/<pack>/`

Pack name = suffix after `table_design_` in `item_id`.

```text
app_media/media/table_design/crystal/
  table_design_overlay_crystal.webp
```

For `item_id` **`table_design_crystal`**. Served via query route:

```http
GET {API}/app_media/media/table_design_overlay.webp?skinId=table_design_crystal
```

### Shop card cover — `card_back/<pack>/`

```text
app_media/media/card_back/forest/
  card_back_forest.webp
```

For `item_id` **`card_back_forest`**.

---

## 1. Add a standard table tier

### JSON (`table_tiers.json`)

Add an object to `tiers[]` with a **unique integer** `level`:

```json
{
  "level": 5,
  "title": "Studio Table",
  "coin_fee": 75,
  "min_user_level": 3,
  "style": {
    "felt_hex": "#2E5A4E",
    "spotlight_hex": "#FFD4A3",
    "back_graphic_file": "town-table-backgraphic.webp"
  }
}
```

Bump `schema_version` when you want clients to treat the doc as a new generation (optional but recommended after structural changes).

### Checks

- `coin_fee` ≥ 1, `min_user_level` ≥ 1, non-empty `title`.
- Flutter reads tier list dynamically (`LevelMatcher.levelOrder`) — new levels appear in Quick Join when revision updates.
- User must meet `min_user_level` (progression) to join.

### Media

Reuse an existing `back_graphic_file` or add a new WebP to the tier-back asset pipeline (see [TABLE_TIERS.md](./TABLE_TIERS.md)).

---

## 2. Add a special event

### Step A — Create media directory

```bash
mkdir -p app_media/media/event_media/my_event_id
# Add WebPs (1024×576 recommended for overlay):
#   my_event_id_background.webp
#   table_design_overlay_my_event_id.webp
```

Convert PNG sources to WebP if needed (shop overlays use 1024×576 center-crop).

### Step B — JSON (`table_tiers.json` → `special_events[]`)

```json
{
  "id": "my_event_id",
  "title": "My Event",
  "description": "Short lobby copy.",
  "coin_fee": 25,
  "min_user_level": 1,
  "metadata": {
    "rewards": {
      "coins": "50",
      "achievement": "my_event_id_winner"
    },
    "end_match_modal": {
      "text": "You won 50 coins!",
      "background_image_file": "my_event_id_background.webp",
      "cta_text": {
        "text": "View Achievements",
        "action": "view_achievements",
        "redirect_to_screen": "achievements"
      }
    }
  },
  "style": {
    "felt_hex": "#4E8065",
    "spotlight_hex": "#FFD4A3",
    "back_graphic_file": "home-table-backgraphic_002.webp",
    "overlay_image_file": "table_design_overlay_my_event_id.webp",
    "border_style": "solid",
    "border_colors": ["#988858"]
  }
}
```

**`id` rules:** `[A-Za-z0-9_-]+` only.

**During special-event matches:** equipped shop table design and card back are **ignored**; event `style` owns felt, overlay, and border colors.

**Border colors:** align rim with overlay art. After adding WebPs:

```bash
python playbooks/rop01/sync_table_design_border_colors.py
```

That samples overlay rim pixels and updates `style.border_colors` for events and `border_colors` for shop `table_design_*` items.

### Step C — Achievement (optional)

If `metadata.rewards.achievement` is set, add a matching row in [achievements_config.json](../../python_base_04/core/modules/dutch_game/config/achievements_config.json) (see [ACHIEVEMENTS.md](./ACHIEVEMENTS.md)).

### Server URL injection

On init, Python replaces `*_file` keys with absolute `*_url` in the client payload (`build_client_table_tiers_payload`). Canonical JSON on disk keeps filenames only.

---

## 3. Add a shop table design (consumable)

### Step A — Media

```bash
mkdir -p app_media/media/table_design/my_pack
# table_design_overlay_my_pack.webp  (1024×576 WebP)
```

### Step B — JSON (`consumables_catalog.json`)

```json
{
  "item_id": "table_design_my_pack",
  "item_type": "table_design",
  "category_group": "table_designs",
  "category_theme": "fantasy",
  "price_coins": 650,
  "display_name": "Table Design My Pack",
  "is_active": true,
  "style": {
    "border_style": "solid",
    "border_colors": ["#786848"]
  }
}
```

`item_id` must be **`table_design_<pack>`** where `<pack>` matches the folder name.

Run border sync after art exists:

```bash
python playbooks/rop01/sync_table_design_border_colors.py
```

### Card cover (`card_back_*`)

Same pattern under `app_media/media/card_back/<pack>/card_back_<pack>.webp` with `item_type`: `"card_back"` and optional `style.card_background_color` / `frame_border_color`.

---

## Picking up changes on the server

| Change type | Flask restart? | Action |
|-------------|----------------|--------|
| Edit `table_tiers.json`, `gameplay_profiles.json`, or `consumables_catalog.json` | **No** (preferred) | Hot reload (below) |
| Edit JSON only, no reload endpoint | Yes (legacy) | Restart Python / redeploy |
| Add/replace WebP under `event_media/` or `table_design/` | **No** | Files served from disk per request |
| VPS static media | **No** | Upload + nginx serves files |

### Hot reload (in-process, no restart)

**Endpoint:** `POST /service/dutch/reload-catalogs`  
**Auth:** `X-Service-Key` header — same as other `/service/dutch/*` routes (`DART_BACKEND_SERVICE_KEY` or `DUTCH_MT_DASHBOARD_SERVICE_KEY` on the server).

Re-reads JSON from disk, rebuilds in-memory maps and revision hashes. Does **not** exit the Flask/gunicorn process.

**Local Mac (app.debug.py on port 5001):**

```bash
python3 playbooks/00_local/reload_dutch_catalogs.py
```

Loads repo-root [`.env.local`](../../.env.local) automatically for `DART_BACKEND_SERVICE_KEY` and API URL.

**Deploy / VPS:**

```bash
python playbooks/rop01/reload_dutch_catalogs.py --url https://your-api.example.com
```

**Example success response:**

```json
{
  "success": true,
  "table_tiers": {
    "reloaded": true,
    "previous_revision": "abc…",
    "revision": "def…",
    "tier_count": 4,
    "special_event_count": 5
  },
  "consumables_catalog": {
    "reloaded": true,
    "previous_revision": "…",
    "revision": "…",
    "item_count": 31
  },
  "timestamp": "2026-05-30T12:00:00.000000"
}
```

**Verify without app:**

```bash
curl -s 'http://127.0.0.1:5001/public/dutch/init-config' | python3 -m json.tool | head
```

Check `table_tiers_revision`, `consumables_catalog_revision`, and that new ids appear in the embedded documents when revisions are stale.

**Implementation:** [`catalog_hot_reload.py`](../../python_base_04/core/modules/dutch_game/catalog_hot_reload.py), [`table_tiers_catalog.reload_from_disk`](../../python_base_04/core/modules/dutch_game/table_tiers_catalog.py), [`consumables_catalog.reload_from_disk`](../../python_base_04/core/modules/dutch_game/consumables_catalog.py).

### Gunicorn multi-worker note

Each worker has its own memory. One reload request updates **one** worker. Hit the endpoint multiple times behind a load balancer, or reload once per worker in dev with a single worker.

---

## Picking up changes on clients (Flutter)

Hot reload updates server **revision hashes** only. The app caches catalogs in SharedPreferences until init sees a stale revision.

1. Call init / refresh user stats with current `client_*_revision` params (or restart app / hot restart after clearing stale cache).
2. When `client_table_tiers_revision ≠ table_tiers_revision`, response includes full `table_tiers`.
3. Same for `consumables_catalog_revision`.

See [INIT_DATA.md](./INIT_DATA.md) and `table_tiers_bootstrap.dart` / `consumables_catalog_bootstrap.dart`.

**No app store release** required for JSON + media URL changes — only a client refresh path that re-fetches init.

---

## End-to-end checklist (new special event)

Example: add event id `summer_night`.

1. [ ] Create `app_media/media/event_media/summer_night/` with background + overlay WebPs.
2. [ ] Add `special_events[]` row to [table_tiers.json](../../python_base_04/core/modules/dutch_game/config/table_tiers.json).
3. [ ] Run `python playbooks/rop01/sync_table_design_border_colors.py` (optional, if overlay present).
4. [ ] Copy/sync [dart_bkend_base_01/config/table_tiers.json](../../dart_bkend_base_01/config/table_tiers.json) if Dart WS uses bundled fallback.
5. [ ] **Local:** `python3 playbooks/00_local/reload_dutch_catalogs.py`
6. [ ] **VPS:** `python playbooks/rop01/18_upload_event_media.py --event summer_night` then `python playbooks/rop01/reload_dutch_catalogs.py`
7. [ ] Confirm init-config / get-init-data shows new event id and new revision.
8. [ ] Refresh app → Special Events tab → join smoke test.

---

## End-to-end checklist (new shop table design)

Example: pack `aurora` → `table_design_aurora`.

1. [ ] `app_media/media/table_design/aurora/table_design_overlay_aurora.webp`
2. [ ] Add item to [consumables_catalog.json](../../python_base_04/core/modules/dutch_game/config/consumables_catalog.json).
3. [ ] Border sync script (optional).
4. [ ] Hot reload catalogs.
5. [ ] **VPS media:** `python playbooks/rop01/14_upload_table_design_overlays.py --pack aurora`
6. [ ] Refresh app shop; purchase/equip smoke test.

---

## Upload scripts (VPS)

| Asset | Script |
|-------|--------|
| Special event media | [playbooks/rop01/18_upload_event_media.py](../../playbooks/rop01/18_upload_event_media.py) |
| Table design overlays | [playbooks/rop01/14_upload_table_design_overlays.py](../../playbooks/rop01/14_upload_table_design_overlays.py) |
| Card back packs | [playbooks/rop01/16_upload_card_back_packs.py](../../playbooks/rop01/16_upload_card_back_packs.py) |
| Event overlay placeholders (dev) | [playbooks/rop01/generate_event_table_design_placeholder_webps.py](../../playbooks/rop01/generate_event_table_design_placeholder_webps.py) |
| Border color sync from art | [playbooks/rop01/sync_table_design_border_colors.py](../../playbooks/rop01/sync_table_design_border_colors.py) |

After JSON deploy on VPS, run **`reload_dutch_catalogs.py`** (not a full container restart) unless you changed Python code.

---

## Local dev auth for reload scripts

Reload scripts POST to `/service/dutch/reload-catalogs` with:

```http
X-Service-Key: <DART_BACKEND_SERVICE_KEY>
```

Local SSOT: repo-root **`.env.local`** (same key used by Dart WS and Python via `run_python_app_to_global_log.sh` / `run_dart_ws_to_global_log.sh`).

---

## Worked example (smoke test pattern)

Used to validate hot reload locally:

1. Added tier level 5, event `dev_catalog_test`, item `table_design_catalog_test`.
2. Copied existing WebPs into `event_media/dev_catalog_test/` and `table_design/catalog_test/`.
3. Ran `playbooks/00_local/reload_dutch_catalogs.py` → `tier_count: 5`, `special_event_count: 6`, `item_count: 32`.
4. Verified `GET /public/dutch/init-config` listed all three.
5. Removed JSON rows and deleted media dirs; reloaded again.

Use the same pattern for any temporary catalog validation — **remove test ids and media before merge**.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Reload returns 401 | Missing/wrong `DART_BACKEND_SERVICE_KEY` in `.env.local` or `--service-key` |
| Reload OK but app unchanged | Client still has old revision cached — force init refresh |
| Event art 404 | Wrong path under `event_media/<id>/` or filename ≠ JSON `*_file` |
| Shop overlay 404 | Folder `<pack>` ≠ `item_id` suffix after `table_design_` |
| Card/table preview 404 (skinId routes) | Flask missing `/app_media/media` bind-mount from nginx docroot, or root `card_back.webp` / `table_logo.webp` not uploaded |
| Border wrong color | Re-run `sync_table_design_border_colors.py` after art swap |
| Tier fee wrong in match | Hot reload not run, or wrong worker behind LB |

---

## Related code (Flutter)

| Area | File |
|------|------|
| Table tiers cache | `flutter_base_05/lib/modules/dutch_game/utils/table_tiers_bootstrap.dart` |
| Level / event resolution | `flutter_base_05/lib/modules/dutch_game/backend_core/utils/level_matcher.dart` |
| Event overlay + borders in play | `flutter_base_05/lib/modules/dutch_game/screens/game_play/game_play_screen.dart` |
| Special Events lobby | `flutter_base_05/lib/modules/dutch_game/screens/lobby_room/widgets/join_random_game_widget.dart` |
| Shop cosmetics | `flutter_base_05/lib/modules/dutch_game/screens/shop/dutch_cosmetics_shop_screen.dart` |
| Border helpers | `flutter_base_05/lib/modules/dutch_game/screens/game_play/utils/table_design_style_helpers.dart` |

# Ad System Implementation Plan

**Status**: Planning  
**Created**: 2026-03-28  
**Last Updated**: 2026-03-28 (selection strategy on type config; default round-robin)  

**Related diagram**: `Documentation/00_FlowCharts/charts/end-to-end/ad-system/ad-system-flow.mmd`

## Objective

Implement an ad system that matches the flowchart:

1. **On app init**, load configuration and construct a single **ad coordinator / registry** instance.
2. **Ad event types** are registered first, each with **type-level config** (display rules, frequency caps, cooldowns, optional **Firebase Analytics** event names / parameters for that event).
3. **Individual ads** are registered second, each **bound to one type** and carrying **ad payload** (at minimum a `link`; room for title, image URL, tracking ids, etc.).
4. At runtime, **existing hooks** (e.g. `bottom_banner_bar_loaded`, screen-switch events) fire; the ad layer **resolves the event type**, picks an ad (see selection rules), and **loads** the right widget / action using the merged **type config + ad data**.

This keeps a clear separation: **type = when & how often & analytics contract**; **ad = what to show (link, assets)**.

## Existing app hooks (anchor points)

`AppManager` already registers placeholder hooks with data, including:

- `top_banner_bar_loaded`
- `bottom_banner_bar_loaded`
- `home_screen_main`

Screens or layout code should continue to **trigger** these hooks (or new ones added in a controlled way). The ad module **subscribes** via `HooksManager.registerHookWithData` and does not replace `HooksManager`.

Per project rules, **avoid changing core managers** unless unavoidable; prefer a **new module** that registers callbacks and holds registry state.

## Data model (conceptual)

### 1. Ad event type (`AdEventTypeId` + `AdTypeConfig`)

- **Stable id** (string), e.g. `bottom_banner`, `switch_screen_interstitial`, `home_hero`.
- **Config** (per type), examples:
  - **`selection_strategy`** (string): how to pick one ad when several are registered for this type. Allowed values (implement as an enum parsed from config): `round_robin`, `weighted`, `single_active`. **For now, set every type to `round_robin`**; other values are reserved for later (weighted needs per-ad weights; single active needs an active id or flag).
  - **Frequency**: max impressions per session / per day, minimum interval between shows.
  - **Display**: duration, dismissible, priority vs other types (if multiple candidates).
  - **Firebase Analytics**: event name(s) and default params when this type is shown / clicked / dismissed (typed once per event type).
  - **Hook name**: which `HooksManager` event this type listens to (must match what the app triggers).

Types are registered **once** at init from config (and optionally merged with remote config later).

### 2. Registered ad (`AdId` + `AdRegistration`)

- **Stable id** (string), e.g. `promo_spring_2026`.
- **`adTypeId`**: references a registered **ad event type**.
- **Payload** (`Map<String, dynamic>` or a small typed model), minimum:
  - `link` (String, required for link-out ads)
  - Optional: `title`, `imageUrl`, `deepLink`, `campaignId`, etc.
- **Optional overrides**: e.g. per-ad analytics param overrides if the type allows.

Many ads can point to the **same** type (rotation pool).

### 3. Resolution at hook time

When hook `H` fires with `data` (e.g. `BuildContext`, route name):

1. Find all **types** whose `hookName == H` (usually one).
2. Enforce **type config** (frequency, cooldown, feature flags).
3. **Select an ad** among ads for that type using the type’s **`selection_strategy`** (from config at type registration). **Initial implementation: only `round_robin`** is required; keep the switch so `weighted` / `single_active` can be added without changing the type model.
4. Emit FA using **type-level** analytics spec + **ad-level** payload fields.
5. **Load** UI: pass merged view-model to a small set of widgets per presentation (banner vs interstitial).

## Configuration format (suggested)

Single file or split by environment, e.g. `assets/config/ads.yaml` (exact path TBD):

```yaml
ad_event_types:
  - id: bottom_banner
    hook_name: bottom_banner_bar_loaded
    selection_strategy: round_robin
    frequency:
      max_per_session: 10
      min_interval_seconds: 60
    firebase_analytics:
      impression_event: ad_banner_impression
      click_event: ad_banner_click
      default_params:
        placement: bottom_banner

ads:
  - id: promo_partner_q2
    ad_type_id: bottom_banner
    link: "https://example.com/promo"
    title: "Partner promo"
    # optional: image_url, campaign_id, ...
```

Validation at startup: every `ad_type_id` on an ad must exist; every `hook_name` on a type should be known or documented; **`selection_strategy`** must be a known value (default parser can treat missing key as `round_robin` to match “all round-robin for now”).

## Implementation steps

- [ ] **Step 1 — Models & registry**: Define `AdTypeConfig` (including `selection_strategy` string / enum), `AdRegistration`, and an `AdRegistry` (register types, then ads; lookup by hook + strategy handler; **implement only round-robin** initially).
- [ ] **Step 2 — Loader**: Parse YAML/JSON in app init (module `initialize`), build registry; expose read-only API to the rest of the module.
- [ ] **Step 3 — Hook wiring**: In the new module, `registerHookWithData` for each distinct `hook_name` present in config (or a fixed list); on callback, call registry → analytics → UI callback / overlay.
- [ ] **Step 4 — Firebase Analytics**: Thin wrapper that logs using type + ad ids and merged params (reuse existing Firebase setup from the client analytics flow).
- [ ] **Step 5 — UI**: Minimal widgets (e.g. `AdBannerSlot`) that consume resolved `{typeConfig, ad}` and open `link` via `url_launcher` or in-app WebView policy (product decision).
- [ ] **Step 6 — Triggers**: Ensure each screen that should show ads calls the existing `AppManager` trigger helpers or `HooksManager.triggerHookWithData` with consistent hook names and `data` (e.g. route id).
- [ ] **Step 7 — Module registration**: Register module in `ModuleRegistry`; no changes to `HooksManager` / `AppManager` unless we only add **new** hook name constants (prefer keeping triggers in screens / a thin coordinator).

## Current progress

- Flowchart documented; **no app code** for this plan yet.

## Next steps

1. Approve **module name** (e.g. `ads_module`) and **config file location**.
2. Implement Steps 1–3 first (registry + hooks with **`selection_strategy` on each type**, all **`round_robin` for now**), then FA + UI.

## Files modified

- (None yet — planning only.)

## Notes

- **Types vs hooks**: Hook names are the bridge to “registered ad events” in the diagram; type config is the box linked bidirectionally to “load a registered ad.”
- **Core immutability**: Implement as a **new module** + config; subscribe to `HooksManager` instead of forking core.
- **AppManager** already has banner hook stubs; either reuse those names in YAML or add a small indirection layer so config only lists logical types and maps to hook names internally.
- **Choosing among multiple ads**: driven by **`selection_strategy`** on the type (`round_robin` | `weighted` | `single_active`); **v1 uses `round_robin` only**; config still carries the string so later strategies need no schema break.

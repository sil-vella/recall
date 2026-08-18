# Master plan index

**Last Updated:** 2026-08-18

## Task Manager (`dutch`)

The label is **project-wide**. Do **not** create one board task per app-build plan. Resolve numeric ids from `GET /api/label-get.php` — do not copy another product’s task ids.

| Board task | Use for |
|------------|---------|
| **App Dev** | All Flutter / Dart WS / Flask game micro-builds as **checklists**. Reuse this card forever. Create only if missing. |
| **Ideas** | Unstructured notes — **do not edit** unless asked |
| Other Ops cards | Marketing, dashboard, revenue — not the player app |

**Board:** Prefer `https://tm.reignofplay.com` (TLS 443). Bearer JWT on HTTPS. Categories: Match, World, Player, Design, Ops, General (App Dev → General; ops → Ops). Do not invent Backend/Frontend.

## Player app (App Dev checklists)

| Plan | Status | Focus |
|------|--------|--------|
| [cpu-player-decision-making.md](../00_Active_plans/cpu-player-decision-making.md) | In Progress | CPU known_cards / same-rank / miss chance |
| [practice-demo-seat-id-fix.md](../00_Active_plans/practice-demo-seat-id-fix.md) | Implemented | Practice/demo local seat id |
| [campaign-referral-deep-links.md](../00_Active_plans/campaign-referral-deep-links.md) | Completed | Campaign referral deep links |
| [declarative-catalog-config-ops.md](../00_Active_plans/declarative-catalog-config-ops.md) | Planned | Catalog reload / ops strategy |
| [delete-account-feature.md](../00_Active_plans/delete-account-feature.md) | Completed | Delete account |

## Ops / dashboard / marketing (own TM cards — not App Dev)

| Plan | Status | Focus | TM |
|------|--------|--------|----|
| [dashboard-revenue-tab.md](dashboard-revenue-tab.md) | Mostly done | Revenue tab — Play GCS · ASC · AdMob | Ops: Dashboard Revenue tab |
| [dashboard-revenue-downloads.md](dashboard-revenue-downloads.md) | Completed | Revenue → Downloads subtab | Ops: Dashboard Revenue tab |
| [marketing-post-metrics.md](marketing-post-metrics.md) | In Progress | Metrics + Platform posts browser | Ops: Marketing post metrics |
| [plan-dutch-narrative-html.md](plan-dutch-narrative-html.md) | Completed | HTML case study | Ops: Case study HTML |

Narrative: [case-study-dutch-card-game.html](case-study-dutch-card-game.html).

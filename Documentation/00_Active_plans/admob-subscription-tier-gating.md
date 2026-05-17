# AdMob gated by subscription tier (Play premium) + daily coins & rewarded boosts

**Status**: Partial — Play premium subscription + +11% coin perk shipped (2026-05-16); daily 25, 3-ad milestone, RTDN, SSV remain open  
**Created**: 2026-05-11  
**Last Updated**: 2026-05-16

## Play Console — configured (2026-05-16)

| Role | ID | Notes |
|------|-----|--------|
| **Subscription product** | `premium_subscription` | Single product; query this ID in Flutter `queryProductDetails` / Play verify API |
| **Base plan (monthly)** | `premium-auto-renew-monthly` | Auto-renewing monthly — map to ~$3.99/mo list price in Console |
| **Base plan (yearly)** | `premium-auto-renew-yearly` | Auto-renewing yearly — map to ~$34.99/yr list price in Console |
| **Store benefits (marketing)** | Ad free · Extra % on purchased coin packs | App: ad free = `subscription_tier` **`premium`**; coin perk = **+11%** via `subscriber_coin_bonus_percent` in catalog |

**Code contract (when implementing):**

- Backend sets `modules.dutch_game.subscription_tier` = **`premium`** after active subscription verify; revert to **`regular`** on lapse (confirm with product).
- Flutter/Android purchase: use **subscription** APIs (not `buyConsumable` / `products().get` used for coin packs). Verify via Play **Subscriptions** API (`purchases.subscriptionsv2.get` or equivalent), not consumable `products().get`.
- Optional body fields for verify endpoint: `subscription_id` (= `premium_subscription`), `base_plan_id` (`premium-auto-renew-monthly` \| `premium-auto-renew-yearly`), `purchase_token` (from client `PurchaseDetails.verificationData`, not order id alone on Android).

Legacy plan names (`premium_monthly`, `premium_yearly` as separate product IDs) are **not** used — one product + two base plans instead.

## Objective
1. **Subscription / ads**: Show AdMob placements (bottom banner, navigation interstitial, and any future slots) only for users who are **not** on the paid / premium experience. **Premium** is defined by the same subscription tier signal the app already uses for Dutch features (e.g. coins vs promotional play, match pot visibility).

   Console work: create the subscription product in **Google Play Console** and wire purchase verification so the backend sets the user’s tier to **premium** (or the agreed tier string). App work: read that tier (already exposed on stats / Dutch state) and **skip loading/showing** AdMob when premium.

2. **Daily coins + rewarded top-up**: Implement a **daily 25 coin** grant (claim once per calendar day per user). **Beyond** that daily amount, users earn **+25 coins only after watching 3 rewarded video ads** (repeatable: each block of 3 completed rewarded views unlocks one **+25** credit, subject to server validation and abuse limits).

   Product intent: light free drip + optional growth via **AdMob rewarded**; **grant amounts must be enforced on the server** (never trust client-only completion counts for coin mutation).

## Implemented in code (audit 2026-05-16)

| Area | What shipped | Notes |
|------|----------------|-------|
| **Flutter ad gating** | `AdExperiencePolicy.showMonetizedAds` in `lib/modules/admobs/ad_experience_policy.dart` | `subscription_tier == premium` → no banners, interstitials, or rewarded UI. Web always off. |
| **Wiring** | `screen_base.dart`, `banner_ad.dart`, `interstitial_ad.dart`, `adverts_module.dart`, `promotional_ads_module.dart`, `ads_navigator_observer.dart`, `coin_purchase_screen.dart` | Premium users get **0px** banner slots (no empty 50px gap). |
| **AdMob modules** | Registered in `module_registry.dart`: banner, interstitial, rewarded, `AdvertsModule`, `PromotionalAdsModule`; `admob_bootstrap.dart` in `main.dart` | See `Documentation/Admobs/README.md`. |
| **Rewarded coins (interim)** | `AdmobRewardsModule`: `POST /userauth/admob/claim-rewarded-ad` | **+25 per completed ad** (config `ADMOB_REWARDED_COINS_PER_CLAIM`, default 25), **daily cap** `ADMOB_REWARDED_DAILY_CAP` (default **20**/UTC day). Idempotent `client_nonce`. **403** for `premium`. No AdMob SSV yet. |
| **Flutter rewarded UI** | `coin_purchase_screen.dart` → `RewardedAdModule` + claim API | Not the planned 0/3 milestone UI. |
| **Play coin IAP** | `play_billing_module`: `/userauth/play/verify-coin-purchase` | Consumables; **+11% coins** when tier is `premium`. |
| **Play subscription** | `POST /userauth/play/verify-subscription`, `GET /userauth/play/subscription-status` | Sets `subscription_tier` = `premium` when Play sub active; reverts to **`regular`** on lapse. Ledger: `play_subscriptions`. |
| **Flutter Premium UI** | `coin_purchase_screen.dart` — Premium card above coin packs (Android) | Monthly/yearly via `premium_subscription`; manage link when active. |
| **Tier plumbing** | `subscription_tier` on Dutch stats; `tier_rank_level_matcher.py` | `premium` after verified Play subscription. |

**Still open:** Play RTDN webhooks, daily 25 claim, **3 ads → +25** milestone (shipped **1 ad → +25**), AdMob SSV, Stripe subscription SKU, app-wide resume tier refresh.

## Context (already in repo)
- Flutter reads `subscription_tier` from Dutch user stats (`DutchGameHelpers.getSubscriptionTier`, `userStats['subscription_tier']` in game UI). **`promotional`** = free-play path; **`regular`** / **`premium`** = coin economy when the match requires coins.
- Canonical paid tier string for **ad removal**: **`premium`** (matches `AdExperiencePolicy` and `AdmobRewardsModule`).
- Backend syncs `modules.subscription` (`enabled`, `plan`, `expires_at`) on verify; lapse reverts tier to **`regular`**.

## Premium subscription pricing & coin perk (USD)

**Adopted default (aligned with existing coin pack ladder in `dutch_coin_catalog.json`):**

- **Monthly:** **$3.99/mo**
- **Annual:** **$34.99/yr** (~$2.92/mo effective; ~**27%** cheaper than 12× monthly at $3.99)
- **Subscriber coin perk:** **10% discount** on coin packs **or** equivalent **+11% coins** for the same cash (pick one representation in UI; server/catalog must apply the benefit authoritatively).

**Alternative annual (sharper conversion push):** **$29.99/yr** instead of $34.99/yr if product wants a stronger “pay yearly” incentive.

**Bottom line:** $3.99/mo, $34.99/yr, and 10% coin discount (or +11% coins for same cash) is a coherent, fair package next to the existing pack ladder. Adjust yearly to **$29.99** if you want a sharper annual push.

Implementation notes:
- Create matching **Play base plan + regional prices** (and any Stripe mirror if web sells the same membership).
- Expose “effective” pack rows or a `subscriber_coin_bonus_percent` (e.g. 10) from API so Flutter coin shop stays single-source without hardcoding economics.

## Implementation Steps

### Play Console & monetization setup
- [x] Create subscription product **`premium_subscription`** with base plans **`premium-auto-renew-monthly`**, **`premium-auto-renew-yearly`** (active 2026-05-16).
- [ ] Confirm **list prices** in Console match targets: **$3.99/mo**, **$34.99/yr** (or **$29.99/yr** if using sharper annual variant) across key regions.
- [ ] Link subscription to correct application id / upload key on release and internal testing tracks.
- [x] Document product / base plan ids in `dutch_coin_catalog.json` (`premium_subscription`, base plans, `subscriber_coin_bonus_percent`: 11).
- [ ] Configure license testers / internal testing to validate purchase → entitlement flow before production.

### Backend: tie Play subscription → premium tier
- [x] On successful Play subscription verification, set **`subscription_tier`** to **`premium`** (`verify-subscription`).
- [x] On expiry / cancel (re-verify inactive), revert tier to **`regular`**.
- [x] Dutch stats payload includes **`subscription_tier`** (existing `get-user-stats` / init paths).
- [x] **+11% coins** on Play coin verify and Stripe coin webhook when tier is `premium` (`effective_coin_grant` in `dutch_game_credits.py`).

### Flutter: gate AdMob by tier
- [x] Central helper: **`AdExperiencePolicy.showMonetizedAds`** (equivalent to planned `shouldShowAdsForTier`; premium → false).
- [x] **`BaseScreen`**: banner preload skip; **0px** top/bottom when ads off.
- [x] **`BannerAdModule`**: skip load when monetized ads off.
- [x] **`PromotionalAdsModule`** / switch-screen interstitial: skip when monetized ads off.
- [x] **`RewardedAdModule`** + coin screen: hidden for premium; server returns `PREMIUM_NO_ADS`.
- [x] Refresh tier after subscription purchase (`verify-subscription` + `fetchAndUpdateUserDutchGameData`); **`subscription-status`** on coin screen load.
- [ ] App-wide tier refresh on **resume** (not only coin screen).

### QA & rollout
- [ ] Matrix: premium vs non-premium × cold start × post-purchase × subscription lapse.
- [x] Confirm no empty banner gap for premium users (layout uses 0px when `showMonetizedAds` is false)—**verify manually** on device.
- [x] Web: no AdMob (`kIsWeb` guards); no regression expected.

### Daily 25 coins + rewarded “3 videos → +25 coins”
- [ ] **Product rules (finalize in spec)**  
  - Daily grant: **25 coins**, **once per UTC day** (or user-local day—pick one and document).  
  - Extra grant: **+25 coins** per **3 rewarded completions** (same day or rolling window—pick one; recommend **per day** cap on extra grants to limit inflation).  
  - **Premium subscribers (TBD)**: e.g. still get daily 25 **without** rewarded requirement, **or** skip rewarded path entirely—decide and list in API contract.
- [ ] **Backend (authoritative)** — daily + milestone  
  - Persist `last_daily_coin_claim_at` (or date string) and optional `rewarded_completions_today` / `extra_coin_grants_today` on user Dutch module (or dedicated rewards doc).  
  - Endpoints: `POST /dutch/claim-daily-coins` (idempotent per day); milestone grant after **3** verified completions (or refactor current claim endpoint).  
  - Prefer AdMob **SSV** for production; minimum today is JWT + `client_nonce` + daily cap (see `admob_rewards_main.py`).
- [x] **Backend (interim rewarded)** — `POST /userauth/admob/claim-rewarded-ad` in `python_base_04/core/modules/admob_rewards_module/admob_rewards_main.py` (auto-discovered module). **Differs from plan:** +25 **per ad**, cap **20**/day—not 3-ad blocks.
- [x] **Flutter rewarded (interim)** — `coin_purchase_screen.dart` + `RewardedAdModule`; modules registered in `module_registry.dart`; `Config.admobsRewarded01`.  
- [ ] **Flutter (planned)** — **Claim daily 25** button; **0/3 → 3/3** progress + collect +25.  
- [ ] **Anti-abuse** — milestone caps per plan; optional SSV / Play Integrity. Client `SharedPref` `rewarded_ad_views` is **not** used for grants.

## Current Progress
- **Done:** AdMob gating; Play **subscription verify** + coin screen Premium UI; **+11%** coin perk (Play + Stripe); rewarded interim flow; consumable coin IAP.
- **Open:** License-tester QA; Play RTDN; daily 25; 3-ad milestone vs 1-ad model; AdMob SSV.

## Next Steps
1. License-tester QA: subscribe → `premium` → ads off → coin pack +11% → cancel → `regular` on refresh.
2. Play RTDN for subscription lapse without opening coin screen.
3. Decide daily 25 / 3-ad milestone vs keep 1-ad model.
4. AdMob SSV for production rewarded grants.

## Files touched / reference (implementation)

**Flutter (implemented):**
- `flutter_base_05/lib/modules/admobs/ad_experience_policy.dart`
- `flutter_base_05/lib/core/00_base/screen_base.dart`
- `flutter_base_05/lib/modules/admobs/banner/banner_ad.dart`
- `flutter_base_05/lib/modules/admobs/interstitial/interstitial_ad.dart`
- `flutter_base_05/lib/modules/admobs/rewarded/rewarded_ad.dart`
- `flutter_base_05/lib/modules/admobs/adverts_module.dart`
- `flutter_base_05/lib/modules/promotional_ads_module/promotional_ads_module.dart`
- `flutter_base_05/lib/modules/promotional_ads_module/ads_navigator_observer.dart`
- `flutter_base_05/lib/core/managers/module_registry.dart`
- `flutter_base_05/lib/screens/coin_purchase_screen/coin_purchase_screen.dart` — Premium subscribe + coin packs
- `flutter_base_05/lib/utils/play_purchase_token.dart`
- `flutter_base_05/assets/dutch_coin_catalog.json`
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`

**Backend (implemented):**
- `python_base_04/core/modules/admob_rewards_module/admob_rewards_main.py` — rewarded claim
- `python_base_04/core/modules/play_billing_module/play_billing_main.py` — coin IAP + subscription verify/status
- `python_base_04/utils/dutch_game_credits.py` — `effective_coin_grant`
- `python_base_04/tests/unit/test_subscriber_coin_bonus.py`
- `python_base_04/core/modules/user_management_module/tier_rank_level_matcher.py` — tier constants
- `python_base_04/utils/config/config.py` — `ADMOB_REWARDED_*` env defaults

**Docs:**
- `Documentation/Admobs/README.md` — setup and premium policy

## Notes
- **Naming**: Avoid overloading `promotional` for “paid”; keep **`premium`** explicit for ad removal and paid entitlement.
- **Compliance**: If the app is “paid removes ads,” ensure store listing and privacy policy match; consider Family / Designed for Families if applicable.
- **Testing**: Use Play billing test tracks; tier flips must be observable in the same API response the game already trusts for stats. Until subscription verify ships, test `premium` via DB/playbook.
- **Rewarded economics**: Plan target is **3 videos per +25**; shipped code is **1 video per +25** with a **20-claim/day** cap. Client `SharedPref` view counts are **not** authoritative for coins.

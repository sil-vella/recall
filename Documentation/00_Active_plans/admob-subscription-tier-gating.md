# AdMob gated by subscription tier (Play premium) + daily coins & rewarded boosts

**Status**: Partial — Flutter ad gating + rewarded coin claim landed; Play subscription → `premium`, daily 25, and 3-ad milestone remain open  
**Created**: 2026-05-11  
**Last Updated**: 2026-05-16

## Play Console — configured (2026-05-16)

| Role | ID | Notes |
|------|-----|--------|
| **Subscription product** | `premium_subscription` | Single product; query this ID in Flutter `queryProductDetails` / Play verify API |
| **Base plan (monthly)** | `premium-auto-renew-monthly` | Auto-renewing monthly — map to ~$3.99/mo list price in Console |
| **Base plan (yearly)** | `premium-auto-renew-yearly` | Auto-renewing yearly — map to ~$34.99/yr list price in Console |
| **Store benefits (marketing)** | Ad free · Extra % on purchased coin packs | App: ad free = `subscription_tier` **`premium`**; coin perk = server/catalog (not built yet) |

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
| **Play coin IAP** | `play_billing_module`: `/userauth/play/verify-coin-purchase` | Consumable coin packs only; **does not** set `subscription_tier`. |
| **Tier plumbing** | `subscription_tier` on Dutch stats; `tier_rank_level_matcher.py` (`promotional`, `regular`, `premium`) | New users get `promotional` or `regular`; **`premium` only if set server-side** (no sub purchase path yet). |

**Not implemented vs this plan:** Play subscription products ($3.99 / $34.99), backend verify-subscription → `premium`, tier revert on lapse, subscriber 10% coin perk, daily 25 claim endpoint/UI, **3 ads → +25** milestone (shipped **1 ad → +25** instead), AdMob SSV, dedicated app-resume tier refresh after subscription purchase.

## Context (already in repo)
- Flutter reads `subscription_tier` from Dutch user stats (`DutchGameHelpers.getSubscriptionTier`, `userStats['subscription_tier']` in game UI). **`promotional`** = free-play path; **`regular`** / **`premium`** = coin economy when the match requires coins.
- Canonical paid tier string for **ad removal**: **`premium`** (matches `AdExperiencePolicy` and `AdmobRewardsModule`).
- Backend / DB playbooks reference `modules.subscription.plan` / Dutch `subscription_tier`; **`play_billing_module`** handles **consumable coins** only today.

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
- [x] Document product / base plan ids (see **Play Console — configured** above); add to `dutch_coin_catalog.json` or a small `premium_subscription_catalog.json` when implementing Flutter.
- [ ] Configure license testers / internal testing to validate purchase → entitlement flow before production.

### Backend: tie Play subscription → premium tier
- [ ] On successful Play subscription verification (or existing webhook), set Dutch-facing **`subscription_tier`** to **`premium`**.
- [ ] On expiry / cancel / revoke, revert tier to non-premium (e.g. `regular` or `promotional`—**pick one contract** and document here when implemented).
- [x] Dutch stats payload includes **`subscription_tier`** (existing `get-user-stats` / init paths).
- [ ] Apply **subscriber coin perk** on authoritative purchase path: **10% off** list or **+11% coins** for same price; avoid client-only price mutation for real money.

### Flutter: gate AdMob by tier
- [x] Central helper: **`AdExperiencePolicy.showMonetizedAds`** (equivalent to planned `shouldShowAdsForTier`; premium → false).
- [x] **`BaseScreen`**: banner preload skip; **0px** top/bottom when ads off.
- [x] **`BannerAdModule`**: skip load when monetized ads off.
- [x] **`PromotionalAdsModule`** / switch-screen interstitial: skip when monetized ads off.
- [x] **`RewardedAdModule`** + coin screen: hidden for premium; server returns `PREMIUM_NO_ADS`.
- [ ] Refresh tier on **app resume** after subscription purchase (partial today: `fetchAndUpdateUserDutchGameData` after coin IAP / rewarded claim / account screen—not after sub flow because sub flow does not exist).

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
- **Done:** Client-side AdMob gating by `premium`; full AdMob module stack; server rewarded claim (+25/ad, daily cap); coin-shop rewarded UI; Play **consumable** coin verification.
- **In progress / gap:** Play **subscription verify** → `premium` tier (Console product live: `premium_subscription`); subscriber coin perk; daily 25; align rewarded economics to **3 ads → +25** (or update product spec to keep 1-ad model); AdMob SSV; subscription lapse QA.

## Next Steps
1. ~~Create Play Console subscription SKUs~~ — done: `premium_subscription` + monthly/yearly base plans.
2. Add backend **`POST /userauth/play/verify-subscription`** (Subscriptions API) → set/revert `modules.dutch_game.subscription_tier` = `premium`.
3. Flutter: query `premium_subscription`, purchase monthly/yearly offers, call verify, `fetchAndUpdateUserDutchGameData()`, fire `subscription_active` hook.
4. Implement subscriber **10% / +11%** in catalog or checkout APIs (`dutch_coin_catalog.json` + verify paths).
5. Decide: keep **1 ad = +25** (current) or implement **daily 25 + 3-ad milestone**; then add endpoints/UI accordingly.
6. Add AdMob **SSV** before scaling rewarded grants in production.
7. QA matrix: premium tier (test purchase) × ads off × subscription lapse.

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
- `flutter_base_05/lib/screens/coin_purchase_screen/coin_purchase_screen.dart`
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart`

**Backend (implemented / pending):**
- `python_base_04/core/modules/admob_rewards_module/admob_rewards_main.py` — rewarded claim (done)
- `python_base_04/core/modules/play_billing_module/play_billing_main.py` — coin IAP only (subscription TBD)
- `python_base_04/core/modules/user_management_module/tier_rank_level_matcher.py` — tier constants
- `python_base_04/utils/config/config.py` — `ADMOB_REWARDED_*` env defaults

**Docs:**
- `Documentation/Admobs/README.md` — setup and premium policy

## Notes
- **Naming**: Avoid overloading `promotional` for “paid”; keep **`premium`** explicit for ad removal and paid entitlement.
- **Compliance**: If the app is “paid removes ads,” ensure store listing and privacy policy match; consider Family / Designed for Families if applicable.
- **Testing**: Use Play billing test tracks; tier flips must be observable in the same API response the game already trusts for stats. Until subscription verify ships, test `premium` via DB/playbook.
- **Rewarded economics**: Plan target is **3 videos per +25**; shipped code is **1 video per +25** with a **20-claim/day** cap. Client `SharedPref` view counts are **not** authoritative for coins.

# AdMob gated by subscription tier (Play premium) + daily coins & rewarded boosts

**Status**: Planned (not started in code)  
**Created**: 2026-05-11  
**Last Updated**: 2026-05-12

## Objective
1. **Subscription / ads**: Show AdMob placements (bottom banner, navigation interstitial, and any future slots) only for users who are **not** on the paid / premium experience. **Premium** is defined by the same subscription tier signal the app already uses for Dutch features (e.g. coins vs promotional play, match pot visibility).

   Console work: create the subscription product in **Google Play Console** and wire purchase verification so the backend sets the user’s tier to **premium** (or the agreed tier string). App work: read that tier (already exposed on stats / Dutch state) and **skip loading/showing** AdMob when premium.

2. **Daily coins + rewarded top-up**: Implement a **daily 25 coin** grant (claim once per calendar day per user). **Beyond** that daily amount, users earn **+25 coins only after watching 3 rewarded video ads** (repeatable: each block of 3 completed rewarded views unlocks one **+25** credit, subject to server validation and abuse limits).

   Product intent: light free drip + optional growth via **AdMob rewarded**; **grant amounts must be enforced on the server** (never trust client-only completion counts for coin mutation).

## Context (already in repo)
- Flutter reads `subscription_tier` from Dutch user stats (`DutchGameHelpers.getSubscriptionTier`, `userStats['subscription_tier']` in game UI). Today much of the game treats **`promotional`** as the special “free / promo” path; paid users need a **stable, documented** tier value (e.g. `premium`) returned from the API after Play subscription is active.
- Backend / DB playbooks reference `modules.subscription.plan` / Dutch `subscription_tier` fields; Play Billing pieces may be in flight (`play_billing_module` etc.). This plan assumes **tier source of truth remains server-side** after purchase verification.

## Premium subscription pricing & coin perk (USD)

**Adopted default (aligned with existing coin pack ladder in `dutch_coin_catalog.json`):**

- **Monthly:** **\$3.99/mo**
- **Annual:** **\$34.99/yr** (~\$2.92/mo effective; ~**27%** cheaper than 12× monthly at \$3.99)
- **Subscriber coin perk:** **10% discount** on coin packs **or** equivalent **+11% coins** for the same cash (pick one representation in UI; server/catalog must apply the benefit authoritatively).

**Alternative annual (sharper conversion push):** **\$29.99/yr** instead of \$34.99/yr if product wants a stronger “pay yearly” incentive.

**Bottom line:** \$3.99/mo, \$34.99/yr, and 10% coin discount (or +11% coins for same cash) is a coherent, fair package next to the existing pack ladder. Adjust yearly to **\$29.99** if you want a sharper annual push.

Implementation notes:
- Create matching **Play base plan + regional prices** (and any Stripe mirror if web sells the same membership).
- Expose “effective” pack rows or a `subscriber_coin_bonus_percent` (e.g. 10) from API so Flutter coin shop stays single-source without hardcoding economics.

## Implementation Steps

### Play Console & monetization setup
- [ ] Create subscription base plan and subscription(s) in Play Console (region, pricing, grace period, offers as needed).
- [ ] Set **list prices** to adopted targets: **\$3.99/mo**, **\$34.99/yr** (or **\$29.99/yr** if using sharper annual variant); keep regional equivalents consistent with strategy.
- [ ] Link the subscription to the correct application id / upload key used by `app-release` / internal testing tracks.
- [ ] Document product ids (e.g. `premium_monthly`, `premium_yearly`) for Android `build` `--dart-define` or Gradle config if the billing client needs them at build time.
- [ ] Configure license testers / internal testing to validate purchase → entitlement flow before production.

### Backend: tie Play subscription → premium tier
- [ ] On successful Play subscription verification (or existing webhook), set Dutch-facing **`subscription_tier`** (or equivalent field the Flutter client already reads) to the agreed **premium** string.
- [ ] On expiry / cancel / revoke, revert tier to non-premium (e.g. empty, `standard`, or `promotional`—**pick one contract** and document it in this plan when implemented).
- [ ] Ensure `get-user-stats` / Dutch stats payload always includes the updated tier so the client does not need a separate “ads off” flag unless we add one later.
- [ ] Apply **subscriber coin perk** on authoritative purchase path: **10% off** list or **+11% coins** for same price (see **Premium subscription pricing & coin perk (USD)** above); avoid client-only price mutation for real money.

### Flutter: gate AdMob by tier
- [ ] Add a small helper (module service or util) e.g. `shouldShowAdsForTier(String? subscriptionTier)` used by:
  - `BaseScreen` / bottom banner slot
  - `BannerAdModule` hook behavior (optional preload skip)
  - `PromotionalAdsModule` / switch-screen interstitial path
  - Any other AdMob entry points added later
- [ ] Rules (initial proposal—adjust when tier strings are finalized):
  - **Premium** (exact string TBD): do not reserve bottom banner height, do not `loadBannerAd`, do not show switch-screen overlay / interstitial.
  - **Non-premium**: current behavior (show ads subject to existing web/native rules).
- [ ] Refresh tier when returning from purchase flow or on app resume if subscription can change outside stats poll.

### QA & rollout
- [ ] Matrix: premium vs non-premium × cold start × post-purchase × subscription lapse.
- [ ] Confirm no empty banner gap for premium users (layout should not reserve 50px if ads are off).
- [ ] Web: confirm intended behavior (no AdMob today; no regression).

### Daily 25 coins + rewarded “3 videos → +25 coins”
- [ ] **Product rules (finalize in spec)**  
  - Daily grant: **25 coins**, **once per UTC day** (or user-local day—pick one and document).  
  - Extra grant: **+25 coins** per **3 rewarded completions** (same day or rolling window—pick one; recommend **per day** cap on extra grants to limit inflation).  
  - **Premium subscribers (TBD)**: e.g. still get daily 25 **without** rewarded requirement, **or** skip rewarded path entirely—decide and list in API contract.
- [ ] **Backend (authoritative)**  
  - Persist `last_daily_coin_claim_at` (or date string) and optional `rewarded_completions_today` / `extra_coin_grants_today` on user Dutch module (or dedicated rewards doc).  
  - Endpoints (example shape): `POST /dutch/claim-daily-coins` (idempotent per day), `POST /dutch/rewarded-milestone` called **only after** client reports a **server-verifiable** token or **after** trusted server-side logging pattern—**preferred**: client calls API **after** `onUserEarnedReward` with a **nonce + server-issued session** or increment server only from a **signed** client attestation if you add Play Integrity later; **minimum**: rate-limit + require auth + correlate with AdMob SSV if/when integrated.  
  - On success: increment `coins` by 25; return new balances + next eligibility in `get-user-stats` payload so Flutter stays in sync.
- [ ] **Flutter**  
  - UI entry point: e.g. coin balance / shop / home—**Claim daily 25** button (disabled after claim, shows next reset time).  
  - **Rewarded path**: progress indicator **0 / 3 → 3 / 3** then call backend to grant +25 (or grant automatically on 3rd verified callback per product choice—prefer explicit “Collect” after 3/3 for clearer UX).  
  - Wire **`RewardedAdModule`** (`flutter_base_05/lib/modules/admobs/rewarded/rewarded_ad.dart`); register in `module_registry.dart` if still commented; use `Config.admobsRewarded01` (or dedicated unit id for “coin boost”).  
  - **Premium**: hide rewarded funnel if product says premium users do not earn via ads; still show daily claim if applicable.
- [ ] **Anti-abuse**  
  - Daily claim idempotency; max extra +25 blocks per day; IP/device fingerprint optional later; align with AdMob policies (no incentivized fake clicks).

## Current Progress
- Plan authored; no AdMob gating code landed yet.
- Tier plumbing for Dutch already exists client-side (`subscription_tier`); premium string and Play → API mapping remain to be finalized when implementing.
- Rewarded module exists in repo but is not fully wired into navigation/product flows until this work.

## Next Steps
1. Align product id(s) and **canonical premium tier string** with backend (single enum/string contract).
2. Implement Play Console subscription + backend verification → tier update.
3. Implement Flutter `shouldShowAdsForTier` (or equivalent) and wire banner + interstitial paths.
4. Spec daily vs rewarded coin rules (timezone, caps) and add backend endpoints + Flutter claim / rewarded UI.
5. Wire Play (and Stripe if applicable) to **\$3.99 / \$34.99** (or **\$29.99** annual) and implement **10% / +11%** coin pack benefit for `premium` tier in catalog or checkout APIs.

## Files likely to change (when implementing)
- `flutter_base_05/lib/core/00_base/screen_base.dart` — bottom slot / height when ads disabled.
- `flutter_base_05/lib/modules/admobs/banner/banner_ad.dart` — optional skip load by tier.
- `flutter_base_05/lib/modules/promotional_ads_module/promotional_ads_module.dart` and/or `widgets/switch_screen_ad_overlay.dart` — skip interstitial gate for premium.
- `flutter_base_05/lib/modules/dutch_game/utils/dutch_game_helpers.dart` — reuse or wrap `getSubscriptionTier`.
- `flutter_base_05/lib/modules/admobs/rewarded/rewarded_ad.dart` — callbacks / preload; `module_registry.dart` — register rewarded module.
- `flutter_base_05/lib/screens/coin_purchase_screen/` (or Dutch home) — entry UI for daily claim + rewarded progress.
- `python_base_04/...` Play Billing / user module paths that set `subscription_tier` after verification (exact files TBD when touching backend).
- `python_base_04/...` new or extended Dutch endpoints for daily claim + rewarded milestone (exact paths TBD).

## Notes
- **Naming**: Avoid overloading `promotional` for “paid”; keep premium explicit so game economy rules (coins, match pot) stay orthogonal to ad policy unless product explicitly ties them.
- **Compliance**: If the app is “paid removes ads,” ensure store listing and privacy policy match; consider Family / Designed for Families if applicable.
- **Testing**: Use Play billing test tracks; tier flips must be observable in the same API response the game already trusts for stats.
- **Rewarded economics**: “3 videos per 25 coins” implies **server-side** enforcement; client `SharedPref` view counts in `RewardedAdModule` are **not** sufficient for granting spendable currency.

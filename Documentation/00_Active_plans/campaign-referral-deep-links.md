# Campaign referral deep links

**Status**: Completed (celebration UX temporary)  
**Last Updated**: 2026-07-16

## Final workflow (SSOT)

Shlink `/rl/<REFCODE>` → **302** `/?ref=<REFCODE>` → landing shows **GET BONUS COINS** → `/gotoapp/<REFCODE>` → app applies code.

Full detail: [`Documentation/Referrals/CAMPAIGN_REFERRAL_CODES.md`](../Referrals/CAMPAIGN_REFERRAL_CODES.md)

## Ops checklist

- [x] Landing `?ref=` + bonus button (`website/index.html`)
- [x] `/gotoapp/` fallback keeps `?ref=` on home link
- [x] AASA / Android intent: `/gotoapp` only
- [x] Nginx `/rl/` 302 to `/?ref=`
- [x] Deploy playbook 17
- [x] Play signing SHA-256 in `assetlinks.json` (production)
- [x] Temporary: on `coins_awarded > 0`, push [DutchWinCelebrationScreen](../../flutter_base_05/lib/modules/dutch_game/screens/promotion/dutch_win_celebration_screen.dart) (replace later)
- [x] Dedicated [DutchReferralBonusCelebrationScreen](../../flutter_base_05/lib/modules/dutch_game/screens/promotion/dutch_referral_bonus_celebration_screen.dart) for successful awards
- [x] Per-user cap: campaign `max_per_user` + user `referral_code_counts` (TESTREF8719 = 1000)
- [x] Unsuccessful sync → `InstantMessageModal` (try again / already applied)

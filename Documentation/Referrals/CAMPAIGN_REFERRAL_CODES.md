# Campaign referral codes

**Status:** Implemented

## Final workflow

```text
Shlink short URL ending in /rl/<REFCODE>
  → 302 redirect → https://dutch.reignofplay.com/?ref=<REFCODE>
  → Root landing (website/index.html)
  → If ?ref= present: show GET BONUS COINS
  → Button href: /gotoapp/<REFCODE>
  → Universal Link / App Link opens Dutch
  → App stores code → session → POST /userauth/referrals/sync
```

| Step | URL / surface | Behavior |
|------|----------------|----------|
| 1. Share | Shlink → `…/rl/<REFCODE>` | Tracking / social short link |
| 2. Redirect | nginx `302` → `/?ref=<REFCODE>` | Same root landing as `/` |
| 3. Landing | `/?ref=<REFCODE>` | Store badges always; **GET BONUS COINS** only if `ref` set |
| 4. Open app | `/gotoapp/<REFCODE>` or `dutch://gotoapp/<REFCODE>` | HTTPS Universal/App Link; custom scheme for same-site Safari |
| 5. App | Flutter `/gotoapp/:code` or `dutch://gotoapp/...` | Prefs list → guest/login if needed → sync + coins |

**Safari note:** Tapping a same-host HTTPS link from the landing page does **not** open Universal Links. **GET BONUS COINS** tries `dutch://gotoapp/<CODE>` first, then falls back to `/gotoapp/<CODE>` if the app is not installed.

Fallback: if the app is not installed, `/gotoapp/<REFCODE>` shows store CTAs; **Back to Dutch home** goes to `/?ref=<REFCODE>` (keeps the code).

## What is *not* an open-app link

- `/rl/*` is **web/tracking only** (redirect). Not in AASA / `assetlinks.json`.
- Only **`/gotoapp/*`** is declared for Universal Links / Android App Links.
- Custom scheme: `dutch://gotoapp/<CODE>` (iOS `CFBundleURLTypes` + Android intent-filter).

## Backend

- Campaign SSOT: MongoDB `referral_campaigns`
  - `code`, `coins`, `enabled`, `expires_at`
  - `max_redemptions` — global cap across all users (`null` = unlimited)
  - `max_per_user` — how many times the **same user** can be rewarded (default `1` if missing)
- User fields:
  - `modules.referrals.referral_codes` (array of codes ever applied)
  - `modules.referrals.referral_code_counts` (map `CODE → times rewarded`)
- Gate: if user count for code `>= max_per_user` → `already_applied` (no credit)
- Endpoint: `POST /userauth/referrals/sync` `{ "codes": ["…"] }`
- Seed: `playbooks/00_local/seed_referral_campaign.py` (`--max-per-user`)

## Hosting / deploy

| Asset | Path |
|-------|------|
| Landing + bonus button | `website/index.html` |
| Open-app fallback | `website/gotoapp/index.html` |
| AASA | `website/.well-known/apple-app-site-association` (`/gotoapp/*`) |
| Asset Links | `website/.well-known/assetlinks.json` |

```bash
ansible-playbook -i playbooks/rop01/inventory.ini \
  playbooks/rop01/17_upload_dutch_landing_site.yml -e vm_name=rop01
```

Nginx: see [`website/README.md`](../../website/README.md) (`/rl/` → `302 /?ref=`, `/gotoapp/` static, `/.well-known/` static).

## Verify

```bash
curl -sI https://dutch.reignofplay.com/rl/test
# expect: 302 Location: …/?ref=test

curl -s 'https://dutch.reignofplay.com/?ref=test' | grep -F 'GET BONUS COINS'

curl -sI https://dutch.reignofplay.com/.well-known/apple-app-site-association
# expect: 200, paths /gotoapp/*
```

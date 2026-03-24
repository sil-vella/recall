# Stripe web coin packages — active plan

**Status**: In progress (local E2E works in test mode; production cutover pending)  
**Created**: 2026-03-21  
**Last updated**: 2026-03-24

## Objective

Ship **hosted Stripe Checkout** for the five Dutch **coin packages** on **Flutter web**, with server-side session creation (JWT), webhook fulfillment crediting **`modules.dutch_game.coins`**, and a clear operator checklist for Dashboard, env, and return URLs.

## Implementation steps (todos)

### Done (in repo)

- [x] Python: `GET /public/stripe/coin-packages` — pack keys, labels, coin amounts, `available` when Price ID is configured  
- [x] Python: `POST /userauth/stripe/create-coin-checkout-session` — body `{ "package_key": "starter" | "casual" | "popular" | "grinder" | "pro" }`, returns Checkout `url`  
- [x] Python: Webhook branch **`checkout.session.completed`** → idempotent **`stripe_coin_purchases`** + `$inc` **`modules.dutch_game.coins`** (metadata `purchase_type: dutch_coins`)  
- [x] Config: `STRIPE_COIN_CHECKOUT_SUCCESS_URL`, `STRIPE_COIN_CHECKOUT_CANCEL_URL`, `STRIPE_PRICE_COIN_*` (five price IDs)  
- [x] Flutter web: Coin purchase screen — **Buy** per pack, open Checkout, handle return `stripe_checkout=success` (query or hash fragment) + refresh stats via **`DutchGameHelpers.fetchAndUpdateUserDutchGameData()`**
- [x] Local Stripe webhook wiring validated with Stripe CLI (`stripe listen --forward-to http://localhost:5001/stripe/webhook`) and matching `STRIPE_WEBHOOK_SECRET`
- [x] Added targeted diagnostics for return URL parsing + router initial location + webhook ingress/signature verification/event processing
- [x] Local test purchase confirmed webhook credit log: `Stripe coin purchase credited ... coins=100 ...`

### TODO — Stripe Dashboard

- [ ] **Webhook endpoint**: `https://<python-api-host>/stripe/webhook` (production endpoint only; local uses Stripe CLI forwarding)  
- [ ] **Subscribe to event**: `checkout.session.completed`  
- [ ] Copy **signing secret** into **`STRIPE_WEBHOOK_SECRET`** (Vault / env; same path as existing Stripe secrets)

### TODO — Environment / Vault (Python)

- [ ] **`STRIPE_SECRET_KEY`** — already required for Checkout; confirm production key  
- [ ] Map each Dashboard **Price ID** to env (or secret files):

| `package_key` | Coins | Config / env |
|-----------------|-------|----------------|
| `starter` | 100 | `STRIPE_PRICE_COIN_STARTER` |
| `casual` | 300 | `STRIPE_PRICE_COIN_CASUAL` |
| `popular` | 700 | `STRIPE_PRICE_COIN_POPULAR` |
| `grinder` | 1500 | `STRIPE_PRICE_COIN_GRINDER` |
| `pro` | 3500 | `STRIPE_PRICE_COIN_PRO` |

- [ ] **`STRIPE_COIN_CHECKOUT_SUCCESS_URL`** — must land user on app with **`stripe_checkout=success`**; may include Stripe’s `{CHECKOUT_SESSION_ID}`  
  - **Recommended** (verified): path-style URL  
  - Example: `https://dutch.mt/coin-purchase?stripe_checkout=success&session_id={CHECKOUT_SESSION_ID}`  
- [ ] **`STRIPE_COIN_CHECKOUT_CANCEL_URL`** — e.g. `https://dutch.mt/coin-purchase?stripe_checkout=cancel` (or hash equivalent)

### TODO — Verification

- [ ] End-to-end test: logged-in web user → **Buy** → pay (test card) → webhook fires → **coins** increase in DB / **get-user-stats** / app bar  
- [ ] Confirm **CORS** allows web origin to Python API (production list already includes `dutch.mt` in [`python_base_04/app.py`](../../python_base_04/app.py))  
- [ ] Confirm **`stripe_module`** loads in deployment (keys present; dependencies satisfied)

### Optional follow-ups

- [ ] Server-side **session verify** on return (e.g. retrieve Checkout Session with `session_id` from URL) for stronger UX than “webhook + delayed refresh”  
- [ ] Use **`GET /public/stripe/coin-packages`** on web to grey out packs when `available: false` instead of only failing at Checkout  
- [ ] **`STRIPE_PUBLISHABLE_KEY`** on Flutter only if adding Stripe.js / Elements later (hosted Checkout does not need it today)

## Current progress

Checkout creation, webhook crediting, config knobs, and Flutter web UI are implemented. Local test-mode flow now works end-to-end when Stripe CLI is running and webhook secret matches the current listener session. **Production remains blocked until** production webhook + live keys + live price IDs + live URLs are set and E2E-tested.

## Next steps

1. Keep local Stripe CLI running during local tests and rotate `STRIPE_WEBHOOK_SECRET` when CLI session changes.  
2. Set production Stripe webhook + secret and live values for all five **`STRIPE_PRICE_COIN_*`** and checkout URLs.  
3. Run one full test purchase in **test mode**, then repeat in **live** when ready.

## Files modified (reference)

- [`python_base_04/utils/config/config.py`](../../python_base_04/utils/config/config.py) — coin checkout URL + price ID config  
- [`python_base_04/core/modules/stripe_module/stripe_main.py`](../../python_base_04/core/modules/stripe_module/stripe_main.py) — routes, Checkout Session, webhook handler, Dutch coin credit  
- [`flutter_base_05/lib/screens/coin_purchase_screen/coin_purchase_screen.dart`](../../flutter_base_05/lib/screens/coin_purchase_screen/coin_purchase_screen.dart) — web Buy + return handling  

## Notes

- Coins are applied **only after** Stripe delivers **`checkout.session.completed`**; the app waits briefly then refreshes stats so balance updates are visible once the webhook has run.  
- Idempotency: **`stripe_coin_purchases`** keyed by **`checkout_session_id`** prevents double credit on webhook retries.  
- Hosted Checkout opens via **`ConnectionsApiModule.launchUrl`**; users may need to allow pop-ups.

---

## Production cutover note (required changes)

When moving from local test mode to production, update both code/runtime config and Stripe Dashboard:

- **Code/runtime config**
  - Set production env/secret values for:
    - `STRIPE_SECRET_KEY` (live key)
    - `STRIPE_WEBHOOK_SECRET` (from production Dashboard webhook endpoint, not Stripe CLI)
    - `STRIPE_PRICE_COIN_STARTER|CASUAL|POPULAR|GRINDER|PRO` (live mode price IDs)
    - `STRIPE_COIN_CHECKOUT_SUCCESS_URL` and `STRIPE_COIN_CHECKOUT_CANCEL_URL` to production domain (path-style recommended)
  - Restart backend after env/secret changes.
  - Optionally set `LOGGING_SWITCH` back to `false` in `stripe_main.py`, `coin_purchase_screen.dart`, and `navigation_manager.dart` after validation.

- **Stripe Dashboard**
  - Create/verify all five **LIVE** Price objects for coin packs.
  - Configure production webhook endpoint: `https://<prod-api-host>/stripe/webhook`.
  - Subscribe to at least `checkout.session.completed` (and any other events you require operationally).
  - Copy production webhook signing secret (`whsec_...`) into `STRIPE_WEBHOOK_SECRET`.
  - Ensure test-mode values are not mixed with live-mode values (keys, prices, webhook secret).

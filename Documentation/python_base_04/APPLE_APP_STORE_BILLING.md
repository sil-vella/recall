# Apple App Store Billing (server verify)

Server-side verification for **consumable coin packs** and **Premium subscriptions** on iOS uses the [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) and StoreKit 2 signed transaction JWS from the Flutter app.

**SSOT for secrets:** repo root `.env.prod`. Flutter builds use `.env.dart.defines.prod` only for client dart-defines (no Apple server secrets in the app).

---

## 1. One-time: App Store Connect

1. Accept **Paid Apps Agreement** + banking/tax (App Store Connect → Business).
2. Create IAP products matching [`dutch_coin_catalog.json`](../../flutter_base_05/assets/dutch_coin_catalog.json) — see [`Documentation/Android_V_ios/IOS_IN_APP_PURCHASES_SETUP.md`](../Android_V_ios/IOS_IN_APP_PURCHASES_SETUP.md).
3. App Store Connect → **Users and Access** → **Integrations** → **In-App Purchase** → generate API key (`.p8`), note **Issuer ID** and **Key ID**.

Save the key locally (never commit):

```text
app_dev/secrets/apple-iap-key.p8
```

---

## 2. `.env.prod` (deploy SSOT)

Add to **`.env.prod`** at repo root:

```bash
# Apple App Store — server verify (coins + premium subscriptions)
APPLE_BUNDLE_ID=com.reignofplay.dutch
APPLE_IAP_ISSUER_ID=your-issuer-uuid
APPLE_IAP_KEY_ID=your-key-id
APPLE_IAP_PRIVATE_KEY_FILE=/app/secrets/apple-iap-key.p8
APPLE_APP_STORE_ENVIRONMENT=Production
APPLE_APP_ID=6772967073
```

Use `Sandbox` for TestFlight/sandbox testing against sandbox purchases.

Deploy flow: [`playbooks/rop01/08_deploy_docker_compose.yml`](../../playbooks/rop01/08_deploy_docker_compose.yml) reads `.env.prod` → templates [`env.j2`](../../playbooks/rop01/templates/env.j2) → VPS `.env`.

[`python_base_04/utils/config/config.py`](../../python_base_04/utils/config/config.py) reads `APPLE_*` from environment.

---

## 3. VPS layout

| Host path | Container path |
|-----------|----------------|
| `/opt/apps/reignofplay/dutch/data/secrets/apple-iap-key.p8` | `/app/secrets/apple-iap-key.p8` |

Apple root CA certificates for JWS verification are bundled in the Flask image at `/app/assets/apple_root_certs/`.

Ansible **08_deploy** copies `secrets/apple-iap-key.p8` from your laptop when the local file exists.

---

## 4. Verify deployment

**Module health** (no JWT):

```http
GET https://dutch.reignofplay.com/modules/apple_billing_module/health
```

Expect `"status": "healthy"` and `"apple_billing_configured": true`.

**App (iOS):** Game Coins → purchase a pack → balance updates. Account → Premium → subscribe → tier **premium**, ads off.

---

## 5. API routes

[`apple_billing_main.py`](../../python_base_04/core/modules/apple_billing_module/apple_billing_main.py):

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/userauth/apple/verify-coin-purchase` | Consumable coins (+11% if tier is premium) |
| POST | `/userauth/apple/verify-subscription` | Set `subscription_tier` = `premium` |
| GET | `/userauth/apple/subscription-status` | Re-check latest Apple subscription ledger |

**Request body (coins):** `{ "product_id": "coins_100", "signed_transaction": "<StoreKit JWS>" }`  
Optional fallback: `{ "product_id": "...", "transaction_id": "..." }`

**Request body (subscription):** `{ "product_id": "premium_auto_renew_monthly", "signed_transaction": "..." }`

Mongo ledgers: `apple_coin_purchases` (unique `transaction_id`), `apple_subscriptions` (unique `original_transaction_id`).

---

## 6. App Review resubmission notes

- Digital coins and Premium are sold **only** via Apple In-App Purchase on iOS.
- Rewarded ads provide optional free coins (AdMob); they are not a substitute for paid coin packs.
- Remove any references to Stripe or web checkout from the iOS binary (implemented in `coin_purchase_screen.dart`).

---

## Related docs

- App Store Connect setup: [`IOS_IN_APP_PURCHASES_SETUP.md`](../Android_V_ios/IOS_IN_APP_PURCHASES_SETUP.md)
- Product ID SSOT: [`COIN_CATALOG_SSOT.md`](../Android_V_ios/COIN_CATALOG_SSOT.md)
- Android parity: [`GOOGLE_PLAY_BILLING.md`](GOOGLE_PLAY_BILLING.md)

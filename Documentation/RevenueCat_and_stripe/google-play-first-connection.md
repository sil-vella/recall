# RevenueCat + Google Play — First connection (step by step)

This document describes the **first-time** setup we used: connect a RevenueCat project to **Google Play** using a **service account**, then wire the **public SDK key** into the Dutch app build. It also covers how coin SKUs fit into the **single catalog** the app and backend share.

**App package name:** `com.reignofplay.dutch`

---

## 1. RevenueCat — create or open the project

1. Log in at [RevenueCat](https://app.revenuecat.com).
2. Create a project (e.g. **Dutch App**) or open the existing one.

---

## 2. RevenueCat — add a real Google Play app

1. Go to **Apps & providers** → **Configurations**.
2. Under **Real store configuration**, choose **Set up a connection with any mobile app store** (Google Play icon).
3. Open **New Play Store configuration** (wording may vary).
4. Set:
   - **App name** — e.g. `Dutch App (Play Store)`.
   - **Google Play package name** — `com.reignofplay.dutch` (must match `applicationId` in `flutter_base_05/android/app/build.gradle.kts`).
5. **Do not save yet** if the form requires credentials first — you need the JSON from the next sections.

---

## 3. Google Cloud — enable APIs (project: e.g. `reignofplay-app-services`)

In [Google Cloud Console](https://console.cloud.google.com/) for the **same** project you will use for the service account:

1. **APIs & Services** → **Library** (or **Enabled APIs & services**).
2. Enable:
   - **Google Play Android Developer API**
   - **Google Play Developer Reporting API**
   - **Cloud Pub/Sub API** (needed later for real-time developer notifications; safe to enable now)

---

## 4. Google Cloud — service account + IAM roles

1. **IAM & Admin** → **Service accounts**.
2. **Create service account** (or use an existing one dedicated to Play), e.g. `google-play-api-service`.
3. Grant this service account access to the **project** with at least:
   - **Pub/Sub Editor** *or* **Pub/Sub Admin** (RevenueCat docs suggest Admin if topic creation fails)
   - **Monitoring Viewer**
4. **Keys** tab → **Add key** → **Create new key** → **JSON** → download the file once.  
   Store it securely; you cannot re-download the same private key later.

---

## 5. Google Play Console — invite the service account

1. [Google Play Console](https://play.google.com/console) → **Users and permissions**.
2. **Invite user** → enter the service account **email** (from the JSON: `client_email`).
3. **Account permissions** — enable at least:
   - View app information and download bulk reports (read-only)
   - View financial data, orders, and cancellation survey responses
   - Manage orders and subscriptions  
   (Other checkboxes are optional unless you need them.)
4. **App permissions** — add **Dutch MT** (or your live app) so this account can access **`com.reignofplay.dutch`**.
5. Confirm the user shows as **Active**.

Official RevenueCat walkthrough: [Creating Google Play service credentials](https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials).

---

## 6. RevenueCat — upload JSON and validate

1. Return to the **Play Store** app configuration in RevenueCat.
2. **Service Account Credentials JSON** — upload the downloaded `.json` file.
3. **Save changes**.
4. Use **Validate credentials** / status UI until it shows **Valid credentials** (first activation can take hours; RevenueCat documents a possible delay and workarounds in their guide).

---

## 7. Flutter / repo — public SDK key (not the JSON)

1. In RevenueCat, open the same Play Store app → **Public API Key** (section may be collapsed).
2. Copy the **Google Play public API key** (RevenueCat labels this for the Android / Play app).
3. In the repo root **`.env.prod`** (or the env file your build uses), set:

   `REVENUECAT_GOOGLE_API_KEY='…'`

4. Rebuild the Android app so the key is passed as `--dart-define` (e.g. `playbooks/frontend/build_apk.sh`, which reads `.env.prod` via `dart_defines_from_env.sh`).

App-side keys are read from `flutter_base_05/lib/utils/consts/config.dart` (`Config.revenueCatGoogleApiKey`, etc.).

**Secret key (server only):** `REVENUECAT_SECRET_API_KEY` belongs in the Python/Flask environment only. It is used to call RevenueCat’s REST API when verifying purchases (`GET /v1/subscribers/{app_user_id}`). Never ship it in the mobile build.

---

## 8. Android — billing permission (Play IAP)

In `flutter_base_05/android/app/src/main/AndroidManifest.xml` ensure:

```xml
<uses-permission android:name="com.android.vending.BILLING" />
```

RevenueCat Flutter install notes: [Flutter installation](https://www.revenuecat.com/docs/getting-started/installation/flutter).

---

## 9. In-app products, RevenueCat offerings, and the coin catalog (SSOT)

After Play and RevenueCat can talk to each other, **consumable** SKUs must exist in **Google Play**, be attached to **RevenueCat** (product catalog + an **offering** the app loads), and be listed in the repo’s **coin catalog JSON**. That JSON is the **single source of truth** for “which native product IDs exist” and “how many in-game coins each one grants.” The Flutter coin UI and the Python verifier both read it (Python via `python_base_04/utils/coin_catalog.py`, which resolves `flutter_base_05/assets/dutch_coin_catalog.json` from the repo layout).

**Catalog file:** `flutter_base_05/assets/dutch_coin_catalog.json`  
It must stay registered as an asset in `flutter_base_05/pubspec.yaml`.

### 9.1 Play Console — create the SKU

1. Play Console → your app → **Monetize** → **Products** → **In-app products**.
2. Create a **managed product** (consumable) with a **Product ID** you will reuse everywhere (example shape: `coins_500`).  
   Set price, region, and activation per Google’s flow.

### 9.2 RevenueCat — import product and attach to an offering

1. RevenueCat → **Product catalog** → add/import the same **Product ID** from Play.
2. **Offerings** — ensure a current offering includes a **package** that references that product (the Flutter app uses `Purchases.getOfferings()` and matches packages by identifier).

### 9.3 Repo — update `dutch_coin_catalog.json` so app + server stay aligned

Whenever you **add**, **rename**, or **change the coin value** of a native pack:

1. Edit **`revenuecat_products`** in `dutch_coin_catalog.json`.  
   - **Keys** must match RevenueCat / Play **product identifiers** exactly (case-sensitive).  
   - **Values** are the integer **coin amount** credited after a successful server verify.

   Example (illustrative):

   ```json
   "revenuecat_products": {
     "coins_100": 100,
     "coins_500": 500,
     "my_new_pack": 2000
   }
   ```

2. **Deploy both** the updated **JSON** (Flutter release that bundles the asset) **and** the **backend** that reads the same file from disk (or ensure your deploy pipeline ships the repo with that path so `coin_catalog.py` sees the new file). If you only change Play/RevenueCat but forget the JSON, the app may still show old packs or the server will **reject** unknown product IDs.

3. **Hotfix discipline:** If you change only coin *amounts* for an existing SKU, you must still ship JSON + backend together; otherwise old builds could show one number while the server credits another.

**Web (Stripe) coin rows** in the same file: `stripe_packages` lists `key`, `label`, `coins`, and `stripe_price_env` (the name of an env var whose value is the Stripe **Price ID**). Adding a web-only pack means a new row **and** defining that env var on the server. `recommended_ui_packages` drives optional display hints for the web coin screen (labels, `priceLabel`, `isPopular`).

### 9.4 Client behavior you should know

- The coin purchase screen calls **`Purchases.logIn(userId)`** with your backend user id **before** a native purchase. If login fails, purchase does not start — this keeps RevenueCat’s `app_user_id` aligned with `GET .../subscribers/{user_id}` on the server.
- After a store purchase, the app calls **`POST /userauth/revenuecat/verify-coin-purchase`** (JWT) with `product_identifier` and `store_transaction_id`; the server verifies against RevenueCat and credits coins **idempotently**.

---

## 10. MongoDB, optional RevenueCat webhook, and env checklist

### 10.1 Unique index (every environment)

Run your database setup so **`revenuecat_coin_purchases`** has a **unique** index on **`store_transaction_id`**. This prevents double-crediting the same store transaction if a request retries after a partial failure.

The playbook **`playbooks/rop01/10_setup_apps_database_structure(update_existing).yml`** includes **Step 6b** (collections + that index). Apply it to **dev / staging / prod** clusters, or run the equivalent `createIndex` once in `mongosh` if you maintain indexes manually.

### 10.2 Optional server webhook (safety net)

RevenueCat can notify your API when purchases occur. The Flask route is:

**`POST /public/revenuecat/webhook`**

- Configure the webhook URL in the RevenueCat dashboard to hit that path on your API base URL.
- Set the webhook **Authorization** header in RevenueCat to a long random secret, and set the same value in the server environment as **`REVENUECAT_WEBHOOK_AUTH`**.  
  If unset or mismatched, the endpoint rejects requests (by design); the app’s **client-triggered verify** remains the primary path.

### 10.3 Still optional for later

- **Google Developer Notifications** (Pub/Sub + **Connect to Google** in RevenueCat) — extra reconciliation signal; not required for the catalog + verify flow above.

---

## Quick checklist

| Step | Where |
|------|--------|
| Project | RevenueCat |
| Play app + package | RevenueCat |
| APIs enabled | Google Cloud |
| Service account + JSON | Google Cloud |
| Invite + permissions + app access | Play Console |
| Upload JSON + valid credentials | RevenueCat |
| `REVENUECAT_GOOGLE_API_KEY` in `.env.prod` | Repo + rebuild |
| `REVENUECAT_SECRET_API_KEY` on API only | Server env / Vault (never in Flutter) |
| `BILLING` permission | Android manifest |
| Play in-app products + RC offering | Play Console + RevenueCat |
| **`dutch_coin_catalog.json`** (`revenuecat_products` + optional Stripe rows) | Repo — **must match** new/changed SKUs |
| Unique index on `revenuecat_coin_purchases.store_transaction_id` | MongoDB / playbook Step 6b |
| Optional: webhook URL + `REVENUECAT_WEBHOOK_AUTH` | RevenueCat + server env |

RevenueCat Flutter install notes: [Flutter installation](https://www.revenuecat.com/docs/getting-started/installation/flutter).

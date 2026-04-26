# RevenueCat + Google Play — First connection (step by step)

This document describes the **first-time** setup we used: connect a RevenueCat project to **Google Play** using a **service account**, then wire the **public SDK key** into the Dutch app build.

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

---

## 8. Android — billing permission (Play IAP)

In `flutter_base_05/android/app/src/main/AndroidManifest.xml` ensure:

```xml
<uses-permission android:name="com.android.vending.BILLING" />
```

RevenueCat Flutter install notes: [Flutter installation](https://www.revenuecat.com/docs/getting-started/installation/flutter).

---

## 9. What we did *not* finish in this pass (next work)

- **Google Developer Notifications** (Pub/Sub topic + **Connect to Google** in RevenueCat) — optional but recommended for production server reconciliation.
- **In-app products** in Play Console + import into RevenueCat **Product catalog** + **Offerings**.
- **Backend** idempotent coin credit + webhooks (for consumables).

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
| `BILLING` permission | Android manifest |

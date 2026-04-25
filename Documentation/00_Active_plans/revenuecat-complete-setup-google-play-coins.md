# RevenueCat Complete Setup (Google Play + Coins)

**Status**: In Progress  
**Created**: 2026-04-25  
**Last Updated**: 2026-04-25

## Objective
Set up RevenueCat end-to-end for Flutter with production-safe secret handling via `--dart-define`, including Google Play one-time coin purchases, subscriptions/entitlements, server validation, and release-readiness checks.

## Implementation Steps
- [ ] Step 1: Configure Google Play Console products (coins as one-time products, subscriptions if used).
- [ ] Step 2: Connect Google Play to RevenueCat project and sync products.
- [ ] Step 3: Configure RevenueCat offerings/packages and entitlement mapping.
- [ ] Step 4: Implement robust purchase processing for coins (backend credit, idempotency, transaction ledger).
- [ ] Step 5: Ensure auth lifecycle correctly updates RevenueCat user identity on login/logout.
- [ ] Step 6: Configure RevenueCat webhooks and backend handlers for purchase/subscription events.
- [ ] Step 7: Run full testing matrix (test track, license testers, restore, identity, idempotent credits).

## Current Progress
Completed:
- RevenueCat keys and entitlement ID are now read from Flutter `Config` via `String.fromEnvironment`.
- RevenueCat SDK initialization now uses `Config.revenueCat*ApiKey` instead of constants.
- Entitlement check in paywall logic now uses `Config.revenueCatEntitlementId`.
- `.env.prod` now contains RevenueCat keys:
  - `REVENUECAT_ENTITLEMENT_ID`
  - `REVENUECAT_APPLE_API_KEY`
  - `REVENUECAT_GOOGLE_API_KEY`
  - `REVENUECAT_AMAZON_API_KEY`
  - `REVENUECAT_WEB_API_KEY`
- `playbooks/frontend/build_apk.sh` already sources `.env.prod` and uses `dart_defines_from_env.sh`, which converts each env variable into `--dart-define=KEY="VALUE"` automatically.

## Step-by-Step Setup Runbook

### 1) Flutter SDK and platform prerequisites
1. Ensure `purchases_flutter` is in `flutter_base_05/pubspec.yaml`.
2. Keep Android `MainActivity` launch mode as `standard` or `singleTop` (current manifest uses `singleTop`).
3. Ensure Android billing permission exists in `android/app/src/main/AndroidManifest.xml`:
   - `<uses-permission android:name="com.android.vending.BILLING" />`
4. If using RevenueCat native paywalls package/UI that requires it, subclass `FlutterFragmentActivity` for Android activity.

### 2) Secrets and runtime config (project-standard)
1. Store RevenueCat values in root `.env.prod`:
   - `REVENUECAT_ENTITLEMENT_ID`
   - `REVENUECAT_APPLE_API_KEY`
   - `REVENUECAT_GOOGLE_API_KEY`
   - `REVENUECAT_AMAZON_API_KEY`
   - `REVENUECAT_WEB_API_KEY`
2. Keep all app reads through `flutter_base_05/lib/utils/consts/config.dart`.
3. Build APK through `playbooks/frontend/build_apk.sh`; script auto-generates all `--dart-define` flags from `.env.prod`.

### 3) Google Play Console configuration (coins + subscriptions)
1. Go to Play Console -> Monetize -> Products -> In-app products.
2. Create one-time products for each coin pack (consumables), for example:
   - `coins_500`
   - `coins_1200`
   - `coins_3000`
3. Set localized title/description/price and activate all products.
4. If premium subscriptions are needed, create subscription products and base plans (monthly/yearly).
5. Add internal/closed testing track and license testers.

### 4) RevenueCat dashboard configuration
1. Create/select project and add Android app with exact package name.
2. Connect Google Play service account/API access in RevenueCat.
3. Import/sync products from Play Console.
4. Configure offerings/packages:
   - Example offering: `default`
   - Map packages to Play product IDs.
5. Configure entitlement(s) for premium access (for example `premium`) and ensure value matches `REVENUECAT_ENTITLEMENT_ID`.

### 5) Purchase flow architecture (important for coin packs)
1. **Subscriptions**:
   - Use RevenueCat customer info entitlements to unlock premium features.
2. **Coins (one-time consumables)**:
   - Do not treat coin ownership as a permanent entitlement.
   - On successful purchase, credit wallet on backend.
   - Use idempotency keys (transaction ID / original transaction ID) to prevent double credit.
   - Persist purchase ledger records (user, product ID, transaction ID, source, timestamp).

### 6) Identity lifecycle and auth integration
1. On app start, configure RevenueCat SDK.
2. On authenticated login, call RevenueCat login with stable app user ID.
3. On logout, call RevenueCat logout (returns anonymous user context).
4. Ensure auth hooks call adapter identity sync methods so RevenueCat user does not become stale across account switches.

### 7) Server-side webhooks and reconciliation
1. Configure RevenueCat webhook endpoint on backend.
2. Handle relevant events for:
   - Initial purchases
   - Renewals
   - Cancellations/expirations
   - Restores/transfers
3. Reconcile coin credits and subscription state server-side; backend should remain source of truth for wallet and permission-sensitive gates.

### 8) QA and release checklist
1. Test purchases using Play internal testing and license testers.
2. Validate flows:
   - Guest -> login identity transitions
   - Purchase success/failure/cancel
   - Restore behavior
   - Subscription activation/deactivation
   - Coin credits exactly once
3. Verify analytics and error logs for purchase funnel observability.
4. Launch only after passing complete matrix on real Android device(s).

## Next Steps
1. Populate `.env.prod` RevenueCat production values.
2. Configure Play Console coin products and RevenueCat offerings.
3. Implement backend idempotent credit endpoint + webhook handlers (if not already present).
4. Wire auth hooks so RevenueCat identity updates on every login/logout transition.
5. Run internal test track end-to-end purchase QA.

## Files Modified
- `flutter_base_05/lib/utils/consts/config.dart`
- `flutter_base_05/lib/core/ext_plugins/revenuecat/main.dart`
- `flutter_base_05/lib/core/ext_plugins/revenuecat/src/views/paywall.dart`
- `flutter_base_05/lib/core/ext_plugins/revenuecat/src/constant.dart`
- `.env.prod`
- `Documentation/00_Active_plans/revenuecat-complete-setup-google-play-coins.md`

## Notes
- RevenueCat Flutter installation and platform caveats (launchMode, billing permission, web limitations) follow official docs: [RevenueCat Flutter Installation](https://www.revenuecat.com/docs/getting-started/installation/flutter).
- Current project build pipeline already supports env-driven `--dart-define` generation; no additional build script changes are required for new RevenueCat env keys.
- For coin packs, server-side idempotency is mandatory to avoid duplicate credits during retries/webhook replay.

# Mobile push notifications (phone) — implementation plan

**Status**: Planned (not started)  
**Created**: 2026-05-12  
**Last Updated**: 2026-05-12

## Objective
Deliver **native push notifications** on **Android and iOS** so users receive timely alerts when the backend has something important (e.g. inbox / Dutch instant-style events, system messages—exact categories TBD). Today the app already has **in-app** notification plumbing (`NotificationsModule`: API fetch, unread, instant modals, WS-driven inbox refresh) but **no** `firebase_messaging` (or equivalent) dependency; pushes should **complement** that flow (tap opens relevant screen / refreshes inbox), not duplicate fragile client-only logic.

## Context (already in repo)
- **Flutter**: `firebase_core` + `firebase_analytics` present; **`firebase_messaging` not yet** in `pubspec.yaml`. `NotificationsModule` (`flutter_base_05/lib/modules/notifications_module/notifications_module.dart`) handles **pull** + **WebSocket**-triggered inbox behavior.
- **Python**: `notification_module` + `NotificationService` write user-facing rows to Mongo; `user_management` user prefs include `notifications.push` (default **true** in some paths)—use this as the **user opt-in** flag once device tokens are stored.
- **Fairness / product**: Push is for **engagement and awareness**, not gameplay advantage; align copy and payload schema with existing notification types (`instant`, `admin`, etc.).

## Implementation steps

### Product & policy
- [ ] Define which events **send push** (e.g. new inbox notification, rematch invite, tournament admin message) vs **in-app only**.
- [ ] Confirm **opt-in / opt-out** UX (respect `notifications.push` + OS permission).
- [ ] Update privacy policy / data processing text for device tokens + FCM.

### Firebase & Apple / Google console
- [ ] Enable **Firebase Cloud Messaging** for the same Firebase project already used by the app.
- [ ] **Android**: ensure correct `google-services.json` / app id; default notification **channel** (sound, importance) for Android 8+.
- [ ] **iOS**: enable **Push Notifications** capability, upload **APNs** key/cert to Firebase, set **background modes** if using background handlers (minimal set first).

### Flutter client
- [ ] Add **`firebase_messaging`** (and **`flutter_local_notifications`** if showing foreground banners on Android/iOS—optional first phase).
- [ ] On login (and on token refresh), obtain **`getToken()`** / iOS `getAPNSToken()` as needed; send token + **platform** + app version to backend (**authenticated** endpoint).
- [ ] Handle **foreground** / **background** / **terminated** `RemoteMessage`: map `data` payload to existing navigation (`NavigationManager` / deep links) or trigger `NotificationsModule` refresh.
- [ ] Request **notification permission** at an appropriate time (not necessarily cold start); handle denial gracefully.
- [ ] On **logout**, unregister or delete token server-side and delete local subscription if applicable.

### Backend (Python)
- [ ] **Store device tokens** per user (multi-device): e.g. `modules.dutch_game.device_push_tokens[]` or top-level `push_tokens` collection with `user_id`, `token`, `platform`, `updated_at`, `invalid` flag.
- [ ] **API**: `POST /userauth/.../register-push-token` (or extend existing profile) — validate JWT, upsert token, respect `notifications.push`.
- [ ] **Sender**: when `NotificationService.create()` (or selected paths) succeeds, enqueue **FCM HTTP v1** send to all valid tokens for that user (batch, retry, prune on `UNREGISTERED` / `INVALID_ARGUMENT`).
- [ ] **Secrets**: service account JSON or workload identity for FCM v1; never commit keys; wire via Vault/env per `python_base_04` patterns.
- [ ] **Rate limits**: avoid spamming duplicate pushes for same notification id.

### QA & rollout
- [ ] Test matrix: Android + iOS × permission granted/denied × logged in/out × token rotation.
- [ ] Verify tap-through to correct route and unread counts.
- [ ] Load test: single user many devices; many users single broadcast (if ever needed—defer).

## Current progress
- Plan only; no FCM client or token API implemented yet.

## Next steps
1. Lock **event list** and payload JSON schema (`type`, `notification_id`, deep link path).
2. Add Flutter FCM dependency + minimal token registration after auth.
3. Add Python token store + FCM send from notification creation path(s).

## Files likely to change (initial pass)
- `flutter_base_05/pubspec.yaml` — add `firebase_messaging` (+ optional `flutter_local_notifications`).
- `flutter_base_05/lib/main.dart` — background handler registration, `Firebase.initializeApp` ordering.
- `flutter_base_05/ios/Runner/` — entitlements, `Info.plist` if needed.
- `flutter_base_05/android/app/src/main/AndroidManifest.xml` — default channel / `FirebaseMessagingService` if custom.
- `flutter_base_05/lib/modules/notifications_module/` — token lifecycle, refresh listeners, tap routing.
- `flutter_base_05/lib/modules/connections_api_module/` — register token API wrapper.
- `python_base_04/core/modules/notification_module/` — hook send after create (or async worker).
- `python_base_04/core/modules/user_management_module/` — token fields / prefs alignment.
- `python_base_04/requirements.txt` — FCM HTTP client (e.g. `google-auth` + `requests` or official SDK).

## Notes
- **Web** is out of scope for “phone” push here; web can keep poll/WS or add **Web Push** later.
- Prefer **data messages** or hybrid for flexible routing; test iOS behavior when app is swiped away.
- If **premium** removes ads, do **not** conflate with push—push remains a separate user-controlled channel.

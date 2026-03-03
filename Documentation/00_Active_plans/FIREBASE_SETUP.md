# Firebase Setup for Flutter Card Game

Firebase setup for the Flutter card game: **Analytics**, **AdMob-ready**, **Google Ads tracking**, **Android first**.

---

## Step 1 — Create Firebase Project

- [ ] Open [Firebase Console](https://console.firebase.google.com/)
- [ ] Create a new project (or use an existing one)
- [ ] Enable **Analytics** when prompted
- [ ] Finish project creation

---

## Step 2 — Add Android App

- [ ] In the project overview, click **Add app** → **Android**
- [ ] Use the **package name** from `android/app/src/main/AndroidManifest.xml` — it must **match exactly**
- [ ] Optionally set an app nickname
- [ ] **Skip** SHA-1 for now (add later if needed for Sign-in or Dynamic Links)

---

## Step 3 — Download google-services.json

- [ ] Download `google-services.json` from the Firebase Console (Project settings → Your apps → Android app)
- [ ] Place it in: `android/app/google-services.json`
- [ ] Do **not** commit secrets; ensure `google-services.json` is in `.gitignore` if it contains sensitive data, or keep it in repo per Firebase’s typical setup for Android

---

## Step 4 — Update Android Build Files

**Project-level `android/build.gradle`** — add the Google services classpath:

```gradle
buildscript {
    dependencies {
        // ... existing
        classpath 'com.google.gms:google-services:4.x.x'
    }
}
```

**App-level `android/app/build.gradle`** — apply the plugin at the **bottom** of the file:

```gradle
apply plugin: 'com.google.gms.google-services'
```

- [ ] Sync Gradle after changes

---

## Step 5 — Add Flutter Packages

In `pubspec.yaml` (or via CLI):

```yaml
dependencies:
  firebase_core: ^2.x.x
  firebase_analytics: ^10.x.x
```

Then run:

```bash
flutter pub get
```

- [ ] Resolve any version conflicts if they appear

---

## Step 6 — Initialize Firebase in main.dart

- [ ] Add imports:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
```

- [ ] Make `main` async and call `Firebase.initializeApp()` before `runApp()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}
```

- [ ] Optionally obtain and use `FirebaseAnalytics.instance` for logging events

---

## Step 7 — Test Analytics

- [ ] Log a test event, e.g.:

```dart
await FirebaseAnalytics.instance.logEvent(name: 'test_analytics_ready', parameters: {});
```

- [ ] Run the app, trigger the event, then open **Firebase Console → Analytics → Realtime** and confirm the event appears

---

## Step 8 — Recommended Events for Card Game

Use these (or equivalent) for the card game:

| Event name             | When to log                          |
|------------------------|--------------------------------------|
| `game_started`         | When a game session starts           |
| `game_finished`        | When a game ends (win/loss/abandon)  |
| `rewarded_ad_watched`  | When user completes a rewarded ad    |
| `coins_earned`         | When user earns coins (e.g. ad/win)  |

- [ ] Add parameters (e.g. `game_id`, `outcome`, `coins`) as needed for reporting

---

## Step 9 — Link to AdMob Later

- [ ] When adding ads: create an AdMob app and link it to the same Firebase project (or follow AdMob + Firebase linking in Firebase/AdMob docs)
- [ ] Use the same `google-services.json`; no extra placement step for the config file

---

## Important “First App” Notes

- **Don’t overcomplicate**: for the first version, focus on:
  - **Tracking game start and game end**
  - **Tracking rewarded ad watches** (when you add them)
- Skip advanced audiences and complex conversions until the basics work and you’re ready to grow.

---

*Document: Firebase setup for Flutter card game — Analytics, AdMob-ready, Google Ads tracking, Android first.*

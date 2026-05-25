# iOS App Store release checklist (Dutch Card Game)

**Full walkthrough (Apple account → IPA):** [`Documentation/Android_V_ios/IOS_APP_STORE_RELEASE_GUIDE.md`](../Android_V_ios/IOS_APP_STORE_RELEASE_GUIDE.md)

Bundle ID: **`com.reignofplay.dutch`**  
Team ID (Xcode): **`D6J4Y6ZQGV`**  
Workspace: **`flutter_base_05/ios/Runner.xcworkspace`**

Official references:

- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Distributing for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Edit access to an app](https://developer.apple.com/help/app-store-connect/create-an-app-record/edit-access-to-an-app/)

---

## Agent / repo (done in project)

| Item | Location |
|------|----------|
| Bundle ID | `ios/Runner.xcodeproj` → `com.reignofplay.dutch` |
| Automatic signing + team | `DEVELOPMENT_TEAM = D6J4Y6ZQGV`, `CODE_SIGN_STYLE = Automatic` |
| Firebase iOS | `ios/Runner/GoogleService-Info.plist` (`BUNDLE_ID` matches) |
| AdMob app ID | `ios/Flutter/Debug.xcconfig` / `Release.xcconfig` → `GAD_APPLICATION_ID` |
| Release IPA script | `playbooks/frontend/build_ipa.sh` |

---

## You — one-time Xcode confirm (~5 min)

1. Open **`flutter_base_05/ios/Runner.xcworkspace`**.
2. **Runner** → **Signing & Capabilities**.
3. Confirm **Automatically manage signing** and team **D6J4Y6ZQGV** (no red errors).
4. If prompted, sign in with Apple ID and allow Xcode to manage profiles.

---

## You — build & upload

### Option A: Script (recommended)

```bash
cd /path/to/app_dev
chmod +x playbooks/frontend/build_ipa.sh
./playbooks/frontend/build_ipa.sh
```

Uses `.env.prod` (version bump) and `.env.dart.defines.prod` (API URLs, keys).

### Option B: Xcode GUI

1. Destination: **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. **Window → Organizer** → **Distribute App** → **App Store Connect** → Upload.

### After IPA exists

- **Transporter** app: drag `.ipa` from `flutter_base_05/build/ios/ipa/`.
- Wait for **Processing** in App Store Connect → **TestFlight**.

**Build number rule:** Each upload needs a **higher** build number than the last. Bump `APP_VERSION` in `.env.prod` (via script prompt) or `pubspec.yaml` `version:` before rebuilding.

---

## You — App Store Connect (metadata)

App: **Dutch Card Game** → **Distribution** → **iOS App 1.0**

| Section | Action |
|---------|--------|
| **Previews and Screenshots** | iPhone 6.5": up to 10 screenshots (1242×2688 or 1284×2778, etc.) |
| **Description / keywords / URLs** | Support URL, marketing text, privacy policy URL |
| **App Privacy** | Privacy questionnaire |
| **Pricing and Availability** | Territories, price |
| **App Review Information** | Contact, demo account if login required |
| **Age Rating** | Questionnaire |
| **Build** | After processing, select uploaded build on version 1.0 |
| **Submit** | **Save** → **Add for Review** |

---

## Config — `APP_STORE_URL` (share links on iOS)

When App Store Connect shows the numeric app ID (e.g. `id1234567890`), add to **`.env.dart.defines.prod`** (not committed):

```bash
APP_STORE_URL=https://apps.apple.com/app/id1234567890
```

Rebuild IPA so celebration share sheets include the link. `PLAY_STORE_URL` is separate (Android).

---

## TestFlight (recommended before review)

1. App Store Connect → **TestFlight** → internal testing.
2. Add your Apple ID as tester.
3. Install **TestFlight** on iPhone → open build → smoke-test login, game, ads.

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| **No Accounts: Add a new account in Accounts settings** | Xcode → **Settings → Accounts** → **+** → Apple ID (team D6J4Y6ZQGV). Then open Runner signing again. |
| **No profiles for com.reignofplay.dutch** | Same as above; enable **Automatically manage signing** on Runner. |
| CocoaPods `ASCII-8BIT` / UTF-8 | `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` before build (set in `build_ipa.sh`). |
| No signing certificate | Xcode Signing & Capabilities; sign in to Apple ID |
| Bundle ID mismatch | Must be `com.reignofplay.dutch` everywhere |
| Invalid binary / processing failed | Read email from App Store Connect; often export compliance or missing icons |
| Version already used | Increase build number and re-archive |

---

## What the agent cannot do

- App Store Connect forms, screenshots, privacy answers, **Add for Review**
- Apple ID / 2FA prompts
- TestFlight install on your phone

See plan: *iOS release agent scope* (repo `.cursor/plans/` if saved locally).

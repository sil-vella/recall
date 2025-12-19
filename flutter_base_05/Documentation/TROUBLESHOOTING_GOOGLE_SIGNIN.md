# Troubleshooting Google Sign-In on Android

If you're still getting error code `10` after configuring the Android OAuth client, check these items:

## 1. Verify SHA-1 Fingerprint Matches

The SHA-1 fingerprint in your APK must **exactly match** what's registered in Google Cloud Console.

**Check your release keystore SHA-1:**
```bash
cd flutter_base_05
./tools/scripts/get_sha1_fingerprint.sh
```

**Verify in Google Cloud Console:**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. APIs & Services → Credentials
3. Find your Android OAuth client: `907176907209-u7cjeiousj1dd460730rgspf05u0fhic...`
4. Click edit (pencil icon)
5. Check the SHA-1 fingerprint matches: `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`

**Important:** The SHA-1 must match **exactly** (including colons and case).

## 2. Verify Package Name Matches

**Check your app's package name:**
- File: `flutter_base_05/android/app/build.gradle.kts`
- Line 24: `applicationId = "com.reignofplay.cleco"`

**Verify in Google Cloud Console:**
- The OAuth client's package name must be: `com.reignofplay.cleco`
- Must match **exactly** (case-sensitive)

## 3. Verify Client ID is Being Used

**Check the build script:**
- File: `tools/scripts/build_apk.sh`
- Should include: `--dart-define=GOOGLE_CLIENT_ID_ANDROID=907176907209-u7cjeiousj1dd460730rgspf05u0fhic.apps.googleusercontent.com`

**Check the code:**
- File: `flutter_base_05/lib/modules/login_module/login_module.dart`
- Line 608-612: Should use `Config.googleClientIdAndroid` when not on web

**Enable logging to verify:**
- The app logs: `"LoginModule: Google Sign-In initialized - Platform: Android, Client ID: 907176907209-u7cje..."`

## 4. Check OAuth Client Status

In Google Cloud Console:
1. Go to your Android OAuth client
2. Check if it shows as **"Active"**
3. Check the **"Last used"** date (should update when you try to sign in)
4. If it shows warnings, address them

## 5. Verify OAuth Consent Screen

1. Go to **APIs & Services** → **OAuth consent screen**
2. Ensure it's configured (even for internal/testing)
3. Check that your app name and support email are set

## 6. Common Issues

### Issue: "Client ID not found"
- **Cause:** Client ID doesn't exist or is in wrong project
- **Fix:** Verify the client ID exists in the same Google Cloud project as your web client

### Issue: "Package name mismatch"
- **Cause:** Package name in OAuth client doesn't match `applicationId` in `build.gradle.kts`
- **Fix:** Update OAuth client with correct package name: `com.reignofplay.cleco`

### Issue: "SHA-1 fingerprint mismatch"
- **Cause:** APK was signed with a different keystore than registered
- **Fix:** 
  - Verify you're using `upload-key.jks` for release builds
  - Re-check SHA-1 from the actual keystore used
  - Update OAuth client with correct SHA-1

### Issue: "OAuth client not active"
- **Cause:** OAuth client was deleted or disabled
- **Fix:** Recreate the OAuth client or check if it was accidentally deleted

## 7. Test with Logs

Enable logging in the app to see what client ID is being used:

1. The app should log: `"LoginModule: Google Sign-In initialized - Platform: Android, Client ID: ..."`
2. Check if the client ID matches: `907176907209-u7cjeiousj1dd460730rgspf05u0fhic.apps.googleusercontent.com`
3. If it shows "Not configured", the client ID isn't being set correctly

## 8. Rebuild After Changes

After making any changes:
1. **Clean build:** `cd flutter_base_05 && flutter clean`
2. **Rebuild APK:** `./tools/scripts/build_apk.sh`
3. **Uninstall old APK** from device
4. **Install new APK** and test again

## 9. Verify APK Signature

You can verify which SHA-1 your APK was signed with:

```bash
# Extract and check APK signature
cd flutter_base_05
unzip -q build/app/outputs/flutter-apk/app-release.apk -d /tmp/apk_extract
keytool -printcert -file /tmp/apk_extract/META-INF/*.RSA | grep -A 1 "SHA1:"
```

This should match: `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`

## Still Not Working?

If none of the above fixes the issue:

1. **Double-check all values** match exactly (no typos, correct case)
2. **Wait a few minutes** - Google Cloud changes can take time to propagate
3. **Try creating a new OAuth client** with a fresh SHA-1
4. **Check Google Cloud Console logs** for any error messages
5. **Verify the OAuth consent screen** is fully configured

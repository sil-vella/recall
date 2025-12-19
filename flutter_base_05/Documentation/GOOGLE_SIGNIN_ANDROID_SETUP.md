# Google Sign-In Android Setup Guide (Without Firebase)

This guide explains how to configure Google Sign-In for Android APK builds using Google Cloud Console OAuth 2.0 (no Firebase required).

## Problem

When building an APK, Google Sign-In fails with error code `10` (`PlatformException: sign_in_failed`). This happens because:

1. Android requires a separate OAuth 2.0 Client ID (different from web)
2. The Android OAuth client must be configured with your app's package name and SHA-1 fingerprint
3. The Android client ID must be provided to the `GoogleSignIn` constructor

## Solution Steps

### Step 1: Get SHA-1 Fingerprints

Run the helper script to get your app's SHA-1 fingerprints:

```bash
cd flutter_base_05
./tools/scripts/get_sha1_fingerprint.sh
```

This will output:
- **Release SHA-1**: For production APK builds (from `upload-key.jks`)
- **Debug SHA-1**: For development builds (from `~/.android/debug.keystore`)

**Example output:**
```
🔴 RELEASE (Production APK):
   AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD

🟡 DEBUG (Development APK):
   11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44
```

### Step 2: Go to Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project (or create a new one)
3. Navigate to **APIs & Services** → **Credentials**

### Step 3: Create OAuth 2.0 Client ID for Android

1. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
2. If prompted, configure the OAuth consent screen first:
   - User Type: **External** (or Internal if using Google Workspace)
   - App name: **Cleco**
   - User support email: Your email
   - Developer contact: Your email
   - Click **Save and Continue** through the scopes (defaults are fine)
   - Click **Save and Continue** for test users (if needed)
   - Click **Back to Dashboard**

3. Back in Credentials, click **+ CREATE CREDENTIALS** → **OAuth client ID**
4. Select **Application type**: **Android**
5. Fill in the details:
   - **Name**: Cleco Android (or any descriptive name)
   - **Package name**: `com.reignofplay.cleco` (must match `applicationId` in `build.gradle.kts`)
   - **SHA-1 certificate fingerprint**: Paste your **Release SHA-1** from Step 1
6. Click **Create**

### Step 4: Add Debug SHA-1 (Optional but Recommended)

For development builds, you should also add the debug SHA-1:

1. In Google Cloud Console → **APIs & Services** → **Credentials**
2. Find your Android OAuth client ID
3. Click the edit (pencil) icon
4. Click **+ ADD SHA-1 CERTIFICATE FINGERPRINT**
5. Paste your **Debug SHA-1** from Step 1
6. Click **Save**

> **Important**: You can add multiple SHA-1 fingerprints to the same OAuth client. This allows the same client ID to work for both debug and release builds.

### Step 5: Copy the Android Client ID

1. After creating the Android OAuth client, you'll see a dialog with your **Client ID**
2. Copy the Client ID (it looks like: `123456789-abcdefghijklmnop.apps.googleusercontent.com`)
3. Save this for the next step

### Step 6: Configure Web Client ID for Android (serverClientId)

**Important**: On Android, `serverClientId` should be the **Web OAuth Client ID**, not the Android OAuth Client ID.

The Android OAuth Client (created in Step 3) is automatically detected via package name + SHA-1. The `serverClientId` is used to get ID tokens to send to your backend server.

**Configuration**:
- The code automatically uses `Config.googleClientId` (Web Client ID) as `serverClientId` for Android
- No additional configuration needed - the Web Client ID is already configured
- The Android OAuth Client (with SHA-1) is automatically matched via package name + SHA-1 fingerprint

### Step 7: Rebuild APK

After completing the above steps:

```bash
cd flutter_base_05
./tools/scripts/build_apk.sh
```

Or if using environment variable:

```bash
export GOOGLE_CLIENT_ID_ANDROID="your-android-client-id-here.apps.googleusercontent.com"
./tools/scripts/build_apk.sh
```

The Google Sign-In should now work in the APK.

## How It Works

- **Web**: Uses `clientId` parameter with Web OAuth Client ID (`GOOGLE_CLIENT_ID`)
- **Android**: 
  - Uses `serverClientId` parameter with **Web OAuth Client ID** (`GOOGLE_CLIENT_ID`) - this is for getting ID tokens to send to your backend
  - The Android OAuth Client (with SHA-1) is **automatically detected** via package name + SHA-1 fingerprint
  - You still need to create an Android OAuth Client in Google Cloud Console with the correct SHA-1 and package name
- Both client IDs are created in the same Google Cloud project
- The Android OAuth client is linked to your app via package name + SHA-1 fingerprint (automatic detection)

## Troubleshooting

### Error Code 10: sign_in_failed

**Causes:**
- SHA-1 fingerprint not registered in Android OAuth client
- Package name mismatch between app and Android OAuth client
- Web Client ID not configured (needed for `serverClientId` on Android)
- Android OAuth client not created or misconfigured

**Solutions:**
1. Verify SHA-1 fingerprints are added to the Android OAuth client in Google Cloud Console
2. Check package name matches: `com.reignofplay.cleco`
3. Ensure `GOOGLE_CLIENT_ID` (Web Client ID) is configured - this is used as `serverClientId` on Android
4. Verify the Android OAuth Client exists with correct SHA-1 and package name (it's auto-detected)

### Package name mismatch

**Error:** `The package name does not match the client ID`

**Solution:**
- Verify `applicationId` in `android/app/build.gradle.kts` is `com.reignofplay.cleco`
- Verify the Android OAuth client in Google Cloud Console has the same package name
- Recreate the OAuth client if needed

### Different SHA-1 for different builds

**Note:** If you use different keystores for different build variants (e.g., staging vs production), you need to add ALL SHA-1 fingerprints to the same Android OAuth client in Google Cloud Console.

### Client ID not being used

**Check:**
1. Verify `GOOGLE_CLIENT_ID` (Web Client ID) is configured - this is used as `serverClientId` on Android
2. Check the default value in `config.dart` - should be the Web Client ID
3. Look at app logs to see which Server Client ID is being used (first 20 chars are logged)
4. The Android OAuth Client is automatically detected - verify it exists in Google Cloud Console with correct SHA-1

## File Locations

```
flutter_base_05/
├── android/
│   ├── app/
│   │   └── build.gradle.kts          # Package name: com.reignofplay.cleco
│   └── settings.gradle.kts
├── lib/
│   ├── utils/consts/
│   │   └── config.dart                # GOOGLE_CLIENT_ID_ANDROID config
│   └── modules/login_module/
│       └── login_module.dart          # GoogleSignIn initialization
├── keystore.properties                # Release keystore config
└── tools/scripts/
    └── get_sha1_fingerprint.sh        # Helper script for SHA-1
```

## Security Notes

- OAuth 2.0 Client IDs are public identifiers, not secrets
- They're safe to include in your app code
- The SHA-1 fingerprint is also public (it's in your APK)
- Keep your keystore files (`.jks`) secure and out of version control

## Additional Resources

- [Google Sign-In for Android](https://developers.google.com/identity/sign-in/android/start)
- [Creating OAuth 2.0 Credentials](https://developers.google.com/identity/protocols/oauth2)
- [Flutter google_sign_in Plugin](https://pub.dev/packages/google_sign_in)

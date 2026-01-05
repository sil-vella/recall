# Local Testing Google Sign-In on Android

This guide explains how to test Google Sign-In locally without rebuilding APKs every time.

## Quick Start

1. **Connect your Android device** via USB (or use an emulator)
2. **Run the debug launcher:**
   ```bash
   ./tools/scripts/launch_android_debug.sh
   ```
3. **Test Google Sign-In** - changes apply instantly with hot reload!

## The Problem with Debug vs Release

- **Debug builds** use the debug keystore (SHA-1: `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C`)
- **Release builds** use the release keystore (SHA-1: `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`)
- **Google Cloud Console** OAuth clients can only have **one SHA-1** per client

## Solution: Create a Debug OAuth Client

Since Google Cloud Console doesn't allow multiple SHA-1s in one client, create a **separate debug OAuth client**:

### Step 1: Create Debug OAuth Client

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. APIs & Services → Credentials
3. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
4. Select **Application type**: **Android**
5. Fill in:
   - **Name**: Dutch Android Debug
   - **Package name**: `com.reignofplay.dutch` (same as release)
   - **SHA-1 certificate fingerprint**: `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C` (debug SHA-1)
6. Click **Create**
7. **Copy the Debug Client ID** (will be different from release)

### Step 2: Use Debug Client ID for Local Testing

**Option A: Set environment variable before running:**
```bash
export GOOGLE_CLIENT_ID_ANDROID="your-debug-client-id.apps.googleusercontent.com"
./tools/scripts/launch_android_debug.sh
```

**Option B: Edit the script** to use the debug client ID by default for local testing.

## Using the Debug Launcher

The `launch_android_debug.sh` script:
- ✅ Uses `flutter run` with hot reload (no APK building needed!)
- ✅ Automatically detects connected Android devices
- ✅ Includes all necessary `--dart-define` flags
- ✅ Shows verbose logging for Google Sign-In debugging
- ✅ Supports both local and VPS backends

### Usage

```bash
# Test with local backend (default)
./tools/scripts/launch_android_debug.sh

# Test with VPS backend
./tools/scripts/launch_android_debug.sh vps

# Use custom debug client ID
GOOGLE_CLIENT_ID_ANDROID="your-debug-client-id" ./tools/scripts/launch_android_debug.sh
```

### Hot Reload Commands

While the app is running:
- Press **`r`** - Hot reload (apply code changes instantly)
- Press **`R`** - Hot restart (restart the app)
- Press **`q`** - Quit

## Debugging Google Sign-In

The enhanced logging will show:
- ✅ Which Client ID is being used
- ✅ Platform (Android vs Web)
- ✅ Detailed error messages if sign-in fails
- ✅ Specific guidance for error code 10 (SHA-1 mismatch)

### Check Logs

Look for these log messages:
```
LoginModule: Google Sign-In initialized - Platform: Android, Client ID: 907176907209-...
LoginModule: Google Sign-In request initiated
```

If you see error code 10:
```
LoginModule: This is error code 10 - likely SHA-1 fingerprint mismatch
LoginModule: Current Client ID: 907176907209-...
```

## Troubleshooting

### Issue: "No Android device found"
- **Fix:** Connect device via USB and enable USB debugging
- Or use an Android emulator

### Issue: Google Sign-In still fails with error 10
- **Cause:** Debug build uses debug SHA-1, but OAuth client has release SHA-1
- **Fix:** Create a separate debug OAuth client (see Step 1 above)

### Issue: Hot reload not working
- **Fix:** Make sure you're using `flutter run` (not `flutter build apk`)
- The debug launcher uses `flutter run` automatically

### Issue: Changes not applying
- **Fix:** Press `R` for hot restart (full app restart)
- Some changes require a full restart

## Benefits of Local Testing

✅ **Fast iteration** - No need to rebuild APKs  
✅ **Instant feedback** - See changes immediately  
✅ **Better debugging** - Verbose logs and error messages  
✅ **Easy testing** - Just connect device and run script  

## Production Builds

For production APKs, continue using:
```bash
./tools/scripts/build_apk.sh
```

This will use the release keystore and release OAuth client ID automatically.

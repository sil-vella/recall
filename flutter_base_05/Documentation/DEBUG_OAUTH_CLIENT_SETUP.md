# Create Debug OAuth Client for Local Testing

## The Problem

- **Debug builds** use debug keystore → SHA-1: `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C`
- **Release builds** use release keystore → SHA-1: `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`
- **Google Cloud Console** only allows **one SHA-1 per OAuth client**
- Your current OAuth client has the **release SHA-1**, so debug builds fail with error code 10

## Solution: Create Separate Debug OAuth Client

### Step 1: Create Debug OAuth Client in Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project (same one with the release client)
3. Navigate to **APIs & Services** → **Credentials**
4. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
5. Select **Application type**: **Android**
6. Fill in:
   - **Name**: `Dutch Android Debug` (or any name)
   - **Package name**: `com.reignofplay.dutch` (same as release)
   - **SHA-1 certificate fingerprint**: `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C`
7. Click **Create**
8. **Copy the Debug Client ID** (will be different from release)

### Step 2: Use Debug Client ID for Local Testing

**Option A: Set environment variable (Recommended)**
```bash
export GOOGLE_CLIENT_ID_ANDROID="your-debug-client-id.apps.googleusercontent.com"
./tools/scripts/launch_android_debug.sh
```

**Option B: Edit the launch script**
Edit `tools/scripts/launch_android_debug.sh` and change line ~40:
```bash
GOOGLE_CLIENT_ID_ANDROID="${GOOGLE_CLIENT_ID_ANDROID:-your-debug-client-id.apps.googleusercontent.com}"
```

### Step 3: Test

1. Run the debug launcher with the debug client ID
2. Try Google Sign-In
3. It should work now! ✅

## Summary

- **Release OAuth Client**: SHA-1 `8F:60:94:F1:...` → Used for production APKs
- **Debug OAuth Client**: SHA-1 `44:FF:5B:9F:...` → Used for local testing with `flutter run`

Both clients use the same package name (`com.reignofplay.dutch`) but different SHA-1 fingerprints.

## Quick Reference

**Debug SHA-1:** `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C`  
**Release SHA-1:** `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`  
**Package Name:** `com.reignofplay.dutch` (same for both)

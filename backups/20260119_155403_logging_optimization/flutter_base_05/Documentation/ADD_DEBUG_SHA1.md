# How to Add Debug SHA-1 to Android OAuth Client

After creating your Android OAuth 2.0 Client ID in Google Cloud Console, you can add multiple SHA-1 fingerprints to support both debug and release builds.

## Steps to Add Debug SHA-1

1. **Go to Google Cloud Console**
   - Navigate to: https://console.cloud.google.com
   - Select your project

2. **Open Credentials**
   - Go to **APIs & Services** → **Credentials**

3. **Edit Your Android OAuth Client**
   - Find your Android OAuth client ID: `907176907209-u7cjeiousj1dd460730rgspf05u0fhic.apps.googleusercontent.com`
   - Click the **pencil/edit icon** (✏️) next to it

4. **Add Debug SHA-1**
   - In the edit screen, you'll see the **SHA-1 certificate fingerprint** field
   - Look for a button or link that says:
     - **"Add SHA-1 certificate fingerprint"** or
     - **"Add another fingerprint"** or
     - A **"+"** button next to the existing SHA-1
   - Click it to add a new fingerprint field
   - Paste your debug SHA-1: `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C`

5. **Save**
   - Click **Save** at the bottom of the page

## Alternative: If You Don't See the Option

If you don't see an option to add multiple SHA-1 fingerprints:

1. You can create a **separate OAuth client** for debug builds with the debug SHA-1
2. Or, some Google Cloud Console interfaces allow you to enter multiple SHA-1s separated by commas or newlines in the same field

## Verify Both SHA-1s Are Added

After saving, you should see both fingerprints listed:
- Release: `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`
- Debug: `44:FF:5B:9F:94:9D:33:23:CD:B8:7A:C3:8E:39:61:0F:71:22:1B:5C`

## Note

If you can only add one SHA-1 at a time, you can:
- Use the release SHA-1 for production APK builds
- Create a separate debug OAuth client for development (less common but works)

The same Android Client ID can work with multiple SHA-1 fingerprints, so adding both is the recommended approach.

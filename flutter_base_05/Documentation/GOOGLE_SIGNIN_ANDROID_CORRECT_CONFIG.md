# Google Sign-In Android Configuration - Correct Setup

## Key Understanding

**Important**: On Android, Google Sign-In uses **two different OAuth clients**:

1. **Android OAuth Client** (with SHA-1 + package name):
   - Created in Google Cloud Console as "Android" type
   - Automatically detected by Google Sign-In via package name + SHA-1 fingerprint
   - **NOT passed to `GoogleSignIn` constructor**
   - Must match your APK's signature

2. **Web OAuth Client** (for `serverClientId`):
   - Created in Google Cloud Console as "Web application" type
   - **Passed as `serverClientId` parameter** to `GoogleSignIn` constructor
   - Used to get ID tokens to send to your backend server
   - Same client ID used for web platform

## Correct Configuration

### In Code (`login_module.dart`):

```dart
final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile', 'openid'],
  clientId: kIsWeb ? webClientId : null, // For web only
  serverClientId: kIsWeb ? null : webClientId, // For Android: use Web Client ID
);
```

### What Happens:

1. **Android OAuth Client** (with SHA-1 `8F:60:94:F1:...`):
   - Automatically matched by Google Sign-In
   - No code configuration needed
   - Must exist in Google Cloud Console with correct SHA-1 and package name

2. **Web Client ID** (as `serverClientId`):
   - Used to obtain ID tokens
   - Must be the Web OAuth Client ID (not Android client ID)
   - Configured in `Config.googleClientId`

## Common Mistakes

❌ **Wrong**: Using Android OAuth Client ID as `serverClientId`
```dart
serverClientId: androidClientId, // ❌ Wrong!
```

✅ **Correct**: Using Web OAuth Client ID as `serverClientId`
```dart
serverClientId: webClientId, // ✅ Correct!
```

## Verification Checklist

- [ ] Android OAuth Client created in Google Cloud Console
- [ ] Android OAuth Client has correct SHA-1: `8F:60:94:F1:E5:ED:DD:FD:FF:4F:5A:79:FF:BB:B7:E9:33:AD:B2:76`
- [ ] Android OAuth Client has correct package name: `com.reignofplay.dutch`
- [ ] Web OAuth Client ID configured in `Config.googleClientId`
- [ ] Code uses Web Client ID as `serverClientId` for Android
- [ ] APK is signed with release keystore (matching SHA-1)

## References

- [google_sign_in package](https://pub.dev/packages/google_sign_in)
- [Google Sign-In for Android](https://developers.google.com/identity/sign-in/android/start)
- [OAuth 2.0 for Mobile & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)

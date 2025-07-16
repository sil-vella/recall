# Deployment Documentation

## Overview

This document provides comprehensive deployment instructions for the Flutter Base 05 application across different platforms and environments.

## Prerequisites

### Development Environment

1. **Flutter SDK**: >=3.2.3
2. **Dart SDK**: >=3.2.3
3. **Android Studio** or **VS Code**
4. **Git** for version control

### Platform-Specific Requirements

#### Android
- Android SDK (API level 21+)
- Android Studio or command line tools
- Java Development Kit (JDK) 11+

#### iOS
- macOS with Xcode 12+
- iOS SDK 12.0+
- Apple Developer Account (for App Store deployment)

#### Web
- Modern web browser for testing
- Web server for production deployment

## Build Configurations

### Environment Configuration

The application supports multiple build configurations through environment variables:

#### Development Configuration
```bash
flutter run --dart-define=API_URL_LOCAL=http://localhost:8081
flutter run --dart-define=WS_URL_LOCAL=ws://localhost:8081
```

#### Staging Configuration
```bash
flutter build apk --dart-define=API_URL_LOCAL=https://staging-api.example.com
flutter build apk --dart-define=WS_URL_LOCAL=wss://staging-ws.example.com
```

#### Production Configuration
```bash
flutter build apk --dart-define=API_URL_LOCAL=https://api.example.com
flutter build apk --dart-define=WS_URL_LOCAL=wss://ws.example.com
```

### Configuration Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `API_URL_LOCAL` | API base URL | `http://10.0.2.2:8081` |
| `WS_URL_LOCAL` | WebSocket URL | `ws://10.0.2.2:8081` |
| `API_KEY` | API authentication key | `''` |
| `STRIPE_PUBLISHABLE_KEY` | Stripe publishable key | `''` |
| `ADMOBS_TOP_BANNER01` | AdMob top banner ID | `''` |
| `ADMOBS_BOTTOM_BANNER01` | AdMob bottom banner ID | `''` |
| `ADMOBS_INTERSTITIAL01` | AdMob interstitial ID | `''` |
| `ADMOBS_REWARDED01` | AdMob rewarded ad ID | `''` |

## Android Deployment

### Setup

1. **Configure Android SDK**
   ```bash
   flutter doctor --android-licenses
   ```

2. **Update Android Configuration**
   - Edit `android/app/build.gradle`
   - Update `applicationId` and `versionCode`
   - Configure signing keys

3. **Configure Signing Keys**
   ```bash
   # Generate keystore
   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

4. **Create `android/key.properties`**
   ```properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=<path to keystore>
   ```

### Build Commands

#### Debug Build
```bash
flutter build apk --debug
```

#### Release Build
```bash
flutter build apk --release
```

#### App Bundle (Recommended for Play Store)
```bash
flutter build appbundle --release
```

#### Split APKs by ABI
```bash
flutter build apk --split-per-abi --release
```

### Testing

#### Local Testing
```bash
flutter install
flutter run --release
```

#### Emulator Testing
```bash
flutter emulators --launch <emulator_id>
flutter run --release
```

### Play Store Deployment

1. **Create App Bundle**
   ```bash
   flutter build appbundle --release
   ```

2. **Upload to Play Console**
   - Go to Google Play Console
   - Create new app or update existing
   - Upload the generated `.aab` file
   - Fill in app metadata and screenshots
   - Submit for review

3. **Release Management**
   - Use internal testing for initial validation
   - Gradual rollout for production releases
   - Monitor crash reports and analytics

## iOS Deployment

### Setup

1. **Install Xcode**
   - Download from Mac App Store
   - Install command line tools: `xcode-select --install`

2. **Configure iOS Project**
   - Open `ios/Runner.xcworkspace` in Xcode
   - Update bundle identifier
   - Configure signing certificates

3. **Update Bundle Identifier**
   ```xml
   <!-- ios/Runner/Info.plist -->
   <key>CFBundleIdentifier</key>
   <string>com.example.yourapp</string>
   ```

4. **Configure Signing**
   - Open Xcode project
   - Select Runner target
   - Go to Signing & Capabilities
   - Configure team and provisioning profiles

### Build Commands

#### Debug Build
```bash
flutter build ios --debug
```

#### Release Build
```bash
flutter build ios --release
```

#### Archive for App Store
```bash
flutter build ios --release --no-codesign
```

### Testing

#### Simulator Testing
```bash
flutter run --release
```

#### Device Testing
```bash
flutter run --release --device-id <device_id>
```

### App Store Deployment

1. **Create Archive**
   ```bash
   flutter build ios --release
   ```

2. **Upload to App Store Connect**
   - Open Xcode
   - Product → Archive
   - Upload to App Store Connect
   - Or use `xcodebuild` command line

3. **App Store Connect Setup**
   - Create new app in App Store Connect
   - Configure app metadata
   - Upload screenshots and descriptions
   - Submit for review

## Web Deployment

### Setup

1. **Enable Web Support**
   ```bash
   flutter config --enable-web
   ```

2. **Configure Web Settings**
   - Update `web/index.html` for SEO
   - Configure service worker if needed
   - Update manifest.json

### Build Commands

#### Development Build
```bash
flutter build web --debug
```

#### Production Build
```bash
flutter build web --release
```

#### Optimized Build
```bash
flutter build web --release --web-renderer html
```

### Deployment Options

#### Static Hosting (Netlify, Vercel, GitHub Pages)

1. **Build for Production**
   ```bash
   flutter build web --release
   ```

2. **Deploy to Netlify**
   ```bash
   # Install Netlify CLI
   npm install -g netlify-cli
   
   # Deploy
   netlify deploy --prod --dir=build/web
   ```

3. **Deploy to Vercel**
   ```bash
   # Install Vercel CLI
   npm install -g vercel
   
   # Deploy
   vercel build/web
   ```

#### Traditional Web Server

1. **Build Application**
   ```bash
   flutter build web --release
   ```

2. **Upload Files**
   - Upload contents of `build/web/` to web server
   - Configure server for SPA routing

3. **Server Configuration**
   ```nginx
   # Nginx configuration
   location / {
       try_files $uri $uri/ /index.html;
   }
   ```

## Environment-Specific Deployment

### Development Environment

#### Local Development
```bash
# Run with development configuration
flutter run --dart-define=API_URL_LOCAL=http://localhost:8081
```

#### Development Server
```bash
# Build for development
flutter build web --debug --dart-define=API_URL_LOCAL=http://localhost:8081

# Serve locally
python -m http.server 8000 --directory build/web
```

### Staging Environment

#### Staging Build
```bash
flutter build apk --release \
  --dart-define=API_URL_LOCAL=https://staging-api.example.com \
  --dart-define=WS_URL_LOCAL=wss://staging-ws.example.com
```

#### Staging Web
```bash
flutter build web --release \
  --dart-define=API_URL_LOCAL=https://staging-api.example.com \
  --dart-define=WS_URL_LOCAL=wss://staging-ws.example.com
```

### Production Environment

#### Production Build
```bash
flutter build appbundle --release \
  --dart-define=API_URL_LOCAL=https://api.example.com \
  --dart-define=WS_URL_LOCAL=wss://ws.example.com \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_... \
  --dart-define=ADMOBS_TOP_BANNER01=ca-app-pub-...
```

#### Production Web
```bash
flutter build web --release \
  --dart-define=API_URL_LOCAL=https://api.example.com \
  --dart-define=WS_URL_LOCAL=wss://ws.example.com
```

## Continuous Integration/Continuous Deployment (CI/CD)

### GitHub Actions

#### Android CI/CD
```yaml
name: Android CI/CD
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.2.3'
      - run: flutter pub get
      - run: flutter test
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v3
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

#### iOS CI/CD
```yaml
name: iOS CI/CD
on:
  push:
    branches: [main]

jobs:
  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.2.3'
      - run: flutter pub get
      - run: flutter test
      - run: flutter build ios --release --no-codesign
```

#### Web CI/CD
```yaml
name: Web CI/CD
on:
  push:
    branches: [main]

jobs:
  build-web:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.2.3'
      - run: flutter pub get
      - run: flutter test
      - run: flutter build web --release
      - uses: actions/upload-artifact@v3
        with:
          name: web-build
          path: build/web
```

### Firebase App Distribution

#### Android
```yaml
- name: Upload to Firebase App Distribution
  uses: wzieba/Firebase-Distribution-Github-Action@v1
  with:
    appId: ${{ secrets.FIREBASE_APP_ID }}
    serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
    groups: testers
    file: build/app/outputs/flutter-apk/app-release.apk
```

#### iOS
```yaml
- name: Upload to Firebase App Distribution
  uses: wzieba/Firebase-Distribution-Github-Action@v1
  with:
    appId: ${{ secrets.FIREBASE_APP_ID }}
    serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
    groups: testers
    file: build/ios/ipa/runner.ipa
```

## Performance Optimization

### Build Optimization

#### Android
```bash
# Enable R8 optimization
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

#### iOS
```bash
# Enable bitcode (deprecated in Xcode 14+)
flutter build ios --release --no-codesign
```

#### Web
```bash
# Optimize for size
flutter build web --release --web-renderer html --dart-define=FLUTTER_WEB_USE_SKIA=false
```

### Asset Optimization

1. **Image Optimization**
   - Use WebP format for better compression
   - Implement responsive images
   - Optimize image sizes

2. **Font Optimization**
   - Use system fonts when possible
   - Subset custom fonts
   - Implement font loading strategies

3. **Code Splitting**
   - Use lazy loading for modules
   - Implement code splitting for web
   - Optimize bundle sizes

## Security Considerations

### Android Security

1. **Network Security**
   ```xml
   <!-- android/app/src/main/res/xml/network_security_config.xml -->
   <network-security-config>
     <domain-config cleartextTrafficPermitted="false">
       <domain includeSubdomains="true">api.example.com</domain>
     </domain-config>
   </network-security-config>
   ```

2. **App Signing**
   - Use App Signing by Google Play
   - Secure keystore storage
   - Regular key rotation

### iOS Security

1. **App Transport Security**
   ```xml
   <!-- ios/Runner/Info.plist -->
   <key>NSAppTransportSecurity</key>
   <dict>
     <key>NSAllowsArbitraryLoads</key>
     <false/>
   </dict>
   ```

2. **Code Signing**
   - Use automatic code signing
   - Secure certificate storage
   - Regular certificate renewal

### Web Security

1. **Content Security Policy**
   ```html
   <!-- web/index.html -->
   <meta http-equiv="Content-Security-Policy" 
         content="default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval';">
   ```

2. **HTTPS Enforcement**
   - Force HTTPS in production
   - Implement HSTS headers
   - Secure cookie settings

## Monitoring and Analytics

### Crash Reporting

#### Firebase Crashlytics
```yaml
# Add to pubspec.yaml
dependencies:
  firebase_crashlytics: ^3.4.8
```

#### Implementation
```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
  
  runApp(MyApp());
}
```

### Analytics

#### Firebase Analytics
```yaml
# Add to pubspec.yaml
dependencies:
  firebase_analytics: ^10.7.4
```

#### Implementation
```dart
import 'package:firebase_analytics/firebase_analytics.dart';

class MyApp extends StatelessWidget {
  static FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: analytics),
      ],
      // ... rest of app
    );
  }
}
```

## Troubleshooting

### Common Build Issues

#### Android Build Issues
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build apk --release

# Check Android SDK
flutter doctor --android-licenses
```

#### iOS Build Issues
```bash
# Clean and rebuild
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release

# Check Xcode
flutter doctor
```

#### Web Build Issues
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter build web --release

# Check web configuration
flutter config --enable-web
```

### Deployment Issues

#### Play Store Issues
- Verify app signing configuration
- Check bundle size limits
- Validate app metadata
- Review content policies

#### App Store Issues
- Verify code signing
- Check app review guidelines
- Validate app metadata
- Test on multiple devices

#### Web Deployment Issues
- Check server configuration
- Verify HTTPS setup
- Test cross-browser compatibility
- Monitor performance metrics

## Conclusion

This deployment documentation provides comprehensive guidance for deploying the Flutter Base 05 application across different platforms and environments. Follow the platform-specific instructions and best practices to ensure successful deployment.

For additional support or troubleshooting, refer to the Flutter documentation or platform-specific guides. 
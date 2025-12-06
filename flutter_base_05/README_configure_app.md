# Flutter App Configuration Script

This script automatically replaces all app-specific declarations in the Flutter project with your custom app name and domain.

## Usage

Run the script from the Flutter project root directory:

```bash
python3 configure_app.py
```

## What the script does

The script will prompt you for:
1. **App Name** (required) - e.g., "MyApp", "CreditSystem", "Cleco"
2. **Domain** (optional) - e.g., "myapp.com", "creditsystem.app" (defaults to "example.com" if skipped)

## Files Updated

The script automatically updates the following files:

### 1. App Name & Title
- `pubspec.yaml` - Package name and description
- `lib/main.dart` - App title in MaterialApp
- `lib/utils/consts/config.dart` - App title constant
- `android/app/src/main/AndroidManifest.xml` - Android app label
- `ios/Runner/Info.plist` - iOS display name

### 2. Deep Linking & URLs
- `android/app/src/main/AndroidManifest.xml` - Deep link scheme and app links
- `lib/modules/connections_api_module/connections_api_module.dart` - HTTP URLs and app schemes

## Examples

### Input:
- App Name: "CreditSystem"
- Domain: "creditsystem.app"

### Output:
- Package name: `creditsystem`
- App title: `"CreditSystem App"`
- Deep link scheme: `creditsystem://`
- App link host: `creditsystem.app`
- Privacy policy URL: `https://creditsystem.app/legal/policy.html`

## Notes

- The script automatically handles capitalization and formatting
- App names with spaces are converted to lowercase for package names
- All changes are made in-place, so make sure to backup your project if needed
- The script provides detailed feedback on which files were successfully updated

## Troubleshooting

If some files fail to update, check:
1. File permissions
2. File paths (ensure you're running from the Flutter project root)
3. Original file content matches expected patterns

The script will show which files failed and provide error messages for debugging. 
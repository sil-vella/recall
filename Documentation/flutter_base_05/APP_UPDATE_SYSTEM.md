# App Update System

## Overview

The App Update System provides automatic version checking and mandatory update enforcement for mobile platforms (Android and iOS). When a major version update is required, users are presented with a blocking screen that prevents app usage until they download and install the latest version.

## Key Features

- **Automatic Version Checking**: Checks for updates after app initialization
- **Major Version Enforcement**: Requires updates when major version changes (e.g., 1.x.x → 2.x.x)
- **Blocking Update Screen**: Prevents app usage until update is downloaded
- **Platform-Aware**: Skips version check on web (web apps update automatically)
- **Download Link Integration**: Provides clickable download links for app updates

## Architecture

### Components

#### 1. VersionCheckService
**Location**: `lib/core/services/version_check_service.dart`

Service responsible for:
- Retrieving current app version from platform (`package_info_plus`)
- Calling Python API to check for available updates
- Comparing versions (semantic versioning)
- Storing last checked version in SharedPreferences
- Extracting update requirements and download links from API response

**Key Methods**:
- `getCurrentAppVersion()` - Gets version from PackageInfo
- `checkForUpdates(ConnectionsApiModule)` - Calls API and processes response
- `compareVersions(String, String)` - Semantic version comparison
- `saveLastCheckedVersion(String)` - Persists version to SharedPreferences

#### 2. UpdateRequiredScreen
**Location**: `lib/screens/update_required_screen/update_required_screen.dart`

Update screen that:
- Displays update required message
- Shows current and server versions
- Provides clickable download button
- Uses `url_launcher` to open download links
- Allows users to skip the update and return to account screen (optional)

**Key Features**:
- Uses `PopScope` with `canPop: true` to allow back navigation
- Provides "Skip for Now" button to navigate back to account screen
- Extracts download link from route query parameters
- Handles URL launching errors gracefully
- Follows app theme styling

**Note**: While updates are recommended, users can skip and continue using the app. The update screen is informative rather than fully blocking.

**Important**: When users skip an update, the version check will run again the next time they visit the account screen, ensuring they don't miss critical updates.

#### 3. AppManager Integration
**Location**: `lib/core/managers/app_manager.dart`

Integrates version checking into app initialization:
- Calls version check after app initialization completes
- Checks platform (skips on web)
- Navigates to update screen when update is required
- Non-blocking (doesn't delay app startup)

**Method**: `_checkForAppUpdates(BuildContext context)`

#### 4. AccountScreen Integration
**Location**: `lib/screens/account_screen/account_screen.dart`

Integrates version checking into account screen:
- Calls version check on every account screen load
- Ensures users get update notifications even after skipping
- Runs asynchronously after screen initialization (non-blocking)
- Uses same logic as AppManager for consistency

**Method**: `_checkForAppUpdates()`

**Key Behavior**:
- Version check runs automatically when account screen loads
- If user previously skipped an update, they'll be checked again
- Prevents users from permanently missing critical updates
- Non-blocking - account screen loads normally while check runs in background

#### 5. Python API Endpoint
**Location**: `python_base_04/core/modules/system_actions_module/system_actions_main.py`

Backend endpoint that:
- Accepts current app version as query parameter
- Compares with server version
- Determines if update is required (major version change)
- Generates version-specific download URL
- Returns update status and download link

**Endpoint**: `GET /public/check-updates?current_version={version}`

**Response Structure**:
```json
{
  "success": true,
  "app_id": "external_app_001",
  "app_name": "External Application",
  "current_version": "1.0.1",
  "server_version": "2.0.0",
  "update_available": true,
  "update_required": true,
  "download_link": "https://download.example.com/v2.0.0/app.apk",
  "timestamp": "2024-01-01T12:00:00"
}
```

## Configuration

### Python Configuration

**File**: `python_base_04/utils/config/config.py`

```python
APP_VERSION = get_file_first_config_value("app_version", "APP_VERSION", "1.0.0")
APP_DOWNLOAD_BASE_URL = get_file_first_config_value("app_download_base_url", "APP_DOWNLOAD_BASE_URL", "https://download.example.com")
```

### Flutter Configuration

**File**: `flutter_base_05/pubspec.yaml`

```yaml
dependencies:
  package_info_plus: ^8.0.0  # For getting app version
  url_launcher: ^6.2.4       # For opening download links
```

## How It Works

### Flow Diagram

```
App Startup
    ↓
AppManager.initializeApp()
    ↓
markAppInitialized()
    ↓
_checkForAppUpdates()
    ↓
Platform Check (kIsWeb?)
    ├─ Web → Skip (return early)
    └─ Mobile → Continue
         ↓
VersionCheckService.checkForUpdates()
    ↓
Get Current Version (PackageInfo)
    ↓
Call Python API: /public/check-updates?current_version={version}
    ↓
Python API:
    ├─ Compare versions
    ├─ Determine update_required (major version change)
    └─ Generate download_link
    ↓
Process Response
    ↓
update_required == true?
    ├─ Yes → Navigate to /update-required?download_link={link}
    │        └─ UpdateRequiredScreen (blocking)
    └─ No → Continue normal app flow

Account Screen Load
    ↓
initState()
    ↓
addPostFrameCallback()
    ↓
_checkForAppUpdates()
    ↓
Platform Check (kIsWeb?)
    ├─ Web → Skip (return early)
    └─ Mobile → Continue
         ↓
VersionCheckService.checkForUpdates()
    ↓
[Same flow as App Startup]
    ↓
If update_required → Navigate to update screen
    ↓
If user skips → Next account screen load will check again
```

### Version Comparison Logic

**Update Required When**:
- Server major version > Client major version
- Example: Client 1.0.1 → Server 2.0.0 = **Required**
- Example: Client 1.0.1 → Server 1.0.2 = **Optional** (not required)

**Update Available When**:
- Server version ≠ Client version
- Any version difference triggers `update_available: true`

### Download Link Generation

**Format**: `{APP_DOWNLOAD_BASE_URL}/v{server_version}/app.apk`

**Example**:
- Base URL: `https://download.example.com`
- Server Version: `2.0.0`
- Download Link: `https://download.example.com/v2.0.0/app.apk`

## Platform Considerations

### Web Platform

- **Behavior**: Version check is completely skipped
- **Reason**: Web apps update automatically when deployed
- **Implementation**: Early return in `_checkForAppUpdates()` when `kIsWeb == true`

### Mobile Platforms (Android/iOS)

- **Behavior**: Full version check and update enforcement
- **Download Links**: Platform-specific (APK for Android, IPA for iOS)
- **Note**: Current implementation uses `.apk` extension - may need platform detection for iOS

## Usage

### Automatic (Default)

The version check runs automatically:
1. **After app initialization** - Checks when app first starts
2. **On every account screen load** - Ensures users get update notifications even after skipping

No manual intervention required. Users who skip an update will be checked again the next time they visit the account screen.

### Manual Version Check

If needed, you can manually trigger a version check:

```dart
final versionCheckService = VersionCheckService();
await versionCheckService.initialize();
final apiModule = ModuleManager().getModuleByType<ConnectionsApiModule>();
final result = await versionCheckService.checkForUpdates(apiModule);

if (result['update_required'] == true) {
  // Handle required update
  final downloadLink = result['download_link'];
  // Navigate to update screen or show dialog
}
```

### Listening to Version Check Events

The system triggers a hook when version check completes:

```dart
AppManager().hooksManager.registerHookWithData('app_version_checked', (data) {
  final updateAvailable = data['update_available'];
  final updateRequired = data['update_required'];
  final currentVersion = data['current_version'];
  final serverVersion = data['server_version'];
  final downloadLink = data['download_link'];
  
  // Handle version check results
});
```

## Update Required Screen

### Features

- **Blocking**: Cannot navigate away (no back button, no drawer, no app bar)
- **Informative**: Shows current and server versions
- **Actionable**: Large, prominent download button
- **Accessible**: Download link is also displayed as selectable text

### User Experience

1. User opens app
2. If update required, immediately redirected to update screen
3. Screen displays:
   - Update required message
   - Current version vs Server version
   - Download button
   - Instructions for installation
4. User taps download button → Opens download link in browser
5. User installs update → Opens updated app

**Skip Update Flow**:
1. User taps "Skip for Now" → Navigates to account screen
2. User continues using app
3. Next time user visits account screen → Version check runs again
4. If update still required → User sees update screen again
5. This ensures users don't permanently miss critical updates

## Error Handling

### Network Errors

- Version check failures don't block app startup
- Errors are logged but app continues normally
- User can use app even if version check fails

### Missing Download Link

- If download link is missing, error message is shown
- User can manually copy link if displayed
- App remains blocked until update is installed

### URL Launch Errors

- If download link fails to open, error snackbar is shown
- User can retry or manually copy link

## Logging

All components include logging switches for debugging:

- `VersionCheckService.LOGGING_SWITCH`
- `AppManager.LOGGING_SWITCH`
- `UpdateRequiredScreen.LOGGING_SWITCH`
- `SystemActionsModule.LOGGING_SWITCH` (Python)

Enable logging by setting switches to `true` in respective files.

## Testing

### Testing Update Required Flow

1. Set Python `APP_VERSION` to a higher major version (e.g., `2.0.0`)
2. Ensure Flutter app version is lower (e.g., `1.0.1` in `pubspec.yaml`)
3. Start app on mobile device/emulator
4. App should navigate to update required screen
5. Verify download link is correct
6. Test download button functionality

### Testing Optional Update

1. Set Python `APP_VERSION` to a higher minor/patch version (e.g., `1.0.2`)
2. Ensure Flutter app version is `1.0.1`
3. Start app
4. App should continue normally (no blocking screen)
5. Check logs for `update_available: true, update_required: false`

### Testing Web Platform

1. Run app on web
2. Check logs for "Skipping version check on web platform"
3. Verify no version check API calls are made

## Future Enhancements

### Potential Improvements

1. **iOS Support**: Add platform detection for download link format (APK vs IPA)
2. **Update Notifications**: Show non-blocking notifications for optional updates
3. **In-App Updates**: Integrate with platform-specific in-app update APIs
4. **Update Scheduling**: Allow scheduling version checks at specific intervals
5. **Version History**: Track version check history in SharedPreferences
6. **Force Update Threshold**: Configurable threshold for when updates become required

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md)
- [State Management System](./STATE_MANAGEMENT_SYSTEM.md)
- [Logging System](./LOGGING_SYSTEM.md)

## Files Reference

### Flutter Files

- `lib/core/services/version_check_service.dart` - Version check service
- `lib/screens/update_required_screen/update_required_screen.dart` - Update screen
- `lib/core/managers/app_manager.dart` - App initialization and version check trigger
- `lib/screens/account_screen/account_screen.dart` - Account screen with version check on load
- `lib/core/managers/navigation_manager.dart` - Route registration

### Python Files

- `python_base_04/core/modules/system_actions_module/system_actions_main.py` - API endpoint
- `python_base_04/utils/config/config.py` - Configuration

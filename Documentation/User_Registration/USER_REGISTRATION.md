# User Registration Process Documentation

## Overview

This document describes the complete user registration process in the Recall application. The registration flow spans from the Flutter frontend through the Python backend to database storage and hook processing. This is a comprehensive guide covering all aspects of the registration system.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Frontend Flow](#frontend-flow)
3. [Backend Flow](#backend-flow)
4. [Guest Registration](#guest-registration)
5. [Google Sign-In](#google-sign-in)
6. [Data Structures](#data-structures)
7. [Validation Rules](#validation-rules)
8. [Security Features](#security-features)
9. [Error Handling](#error-handling)
10. [Hook System](#hook-system)
11. [Related Files](#related-files)
12. [Future Improvements](#future-improvements)

---

## Architecture Overview

### System Components

The registration system consists of several key components:

1. **Frontend (Flutter)**
   - `AccountScreen` - User interface for registration
   - `LoginModule` - Registration logic and API communication
   - `ConnectionsApiModule` - HTTP client for API requests

2. **Backend (Python)**
   - `UserManagementModule` - Registration endpoint handler
   - `DatabaseManager` - Database operations
   - `HooksManager` - Event system for post-registration actions

3. **Database**
   - MongoDB `users` collection
   - User document structure

4. **Hook System**
   - `user_created` hook
   - `CreditSystemModule` - Listens to user creation events

### Registration Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    User Registration Flow                    │
└─────────────────────────────────────────────────────────────┘

User Input (AccountScreen)
    ↓
Form Validation (AccountScreen)
    ↓
LoginModule.registerUser()
    ↓
Client-side Validation (LoginModule)
    ↓
ConnectionsApiModule.sendPostRequest()
    ↓
HTTP POST /public/register
    ↓
UserManagementModule.create_user()
    ↓
Backend Validation
    ↓
Duplicate Checks (email, username)
    ↓
Password Hashing (bcrypt)
    ↓
User Data Structure Creation
    ↓
DatabaseManager.insert() - Automatic Encryption
    ├─ Email → Deterministic encryption (det_...)
    ├─ Username → Deterministic encryption (det_...)
    └─ Phone → Fernet encryption (gAAAAAB...)
    ↓
Database Insert (MongoDB - encrypted data)
    ↓
Hook Trigger: user_created
    ↓
CreditSystemModule._on_user_created()
    ↓
Response: 201 Created
    ↓
Frontend Success Message
    ↓
Switch to Login Mode
```

---

## Frontend Flow

### 1. User Interface (AccountScreen)

**Location**: `flutter_base_05/lib/screens/account_screen/account_screen.dart`

**Components**:
- Registration form with fields:
  - Username input
  - Email input
  - Password input
  - Confirm Password input (UI validation only)
- Form validation using `GlobalKey<FormState>`
- Loading state management
- Error/success message display

**Form Fields**:
```dart
final TextEditingController _usernameController = TextEditingController();
final TextEditingController _emailController = TextEditingController();
final TextEditingController _passwordController = TextEditingController();
final TextEditingController _confirmPasswordController = TextEditingController();
```

**Registration Handler**:
```dart
Future<void> _handleRegister() async {
  // 1. Validate form
  if (!_registerFormKey.currentState!.validate()) {
    return;
  }
  
  // 2. Set loading state
  setState(() {
    _isLoading = true;
    _clearMessages();
  });
  
  // 3. Call LoginModule
  final result = await _loginModule!.registerUser(
    context: context,
    username: _usernameController.text.trim(),
    email: _emailController.text.trim(),
    password: _passwordController.text,
  );
  
  // 4. Handle response
  if (result['success'] != null) {
    // Show success message
    // Switch to login mode after 2 seconds
  } else {
    // Show error message
  }
}
```

### 2. LoginModule Registration Logic

**Location**: `flutter_base_05/lib/modules/login_module/login_module.dart`

**Method**: `registerUser()`

**Process**:

#### Step 1: Dependency Initialization
```dart
_initDependencies(context);
// Gets ConnectionsApiModule for HTTP requests
// Validates services are available
```

#### Step 2: Client-Side Validation

**Username Validation**:
- Length: 3-20 characters
- Pattern: `^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$`
- Cannot contain consecutive special characters
- Cannot start or end with special characters

**Email Validation**:
- Format: `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`

**Password Validation**:
- Minimum 8 characters

**Validation Code**:
```dart
// Username validation
if (username.length < 3) {
  return {"error": "Username must be at least 3 characters long"};
}
if (username.length > 20) {
  return {"error": "Username cannot be longer than 20 characters"};
}
if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$').hasMatch(username)) {
  return {"error": "Username can only contain letters, numbers, underscores, and hyphens"};
}

// Email validation
final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
if (!emailRegex.hasMatch(email)) {
  return {"error": "Invalid email format. Please enter a valid email address."};
}

// Password validation
if (password.length < 8) {
  return {"error": "Password must be at least 8 characters long"};
}
```

#### Step 3: API Request
```dart
final response = await _connectionModule!.sendPostRequest(
  "/public/register",
  {
    "username": username,
    "email": email,
    "password": password,
  },
);
```

#### Step 4: Response Handling
```dart
if (response is Map) {
  if (response["success"] == true || response["message"] == "User created successfully") {
    return {"success": "Registration successful. Please log in."};
  } else if (response["error"] != null) {
    // Handle rate limiting
    if (response["status"] == 429) {
      return {
        "error": response["error"] ?? "Too many registration attempts. Please try again later.",
        "isRateLimited": true
      };
    }
    return {"error": response["error"]};
  }
}
```

### 3. HTTP Request Transmission

**Location**: `flutter_base_05/lib/modules/connections_api_module/connections_api_module.dart`

**Process**:

1. **Request Construction**:
   - Base URL from config
   - Full URL: `{baseUrl}/public/register`
   - Headers: `Content-Type: application/json`
   - Body: JSON-encoded payload

2. **HTTP Client**:
   - Uses `InterceptedClient` with `AuthInterceptor`
   - Timeout: `Config.httpRequestTimeout`
   - Note: `/public/register` does not require authentication (no JWT token)

3. **Response Processing**:
   - Status 200-299: Parse JSON response
   - Status 401: Return unauthorized error
   - Other errors: Parse error JSON or return generic error

**Code**:
```dart
Future<dynamic> sendPostRequest(String route, Map<String, dynamic> data) async {
  final url = Uri.parse('$baseUrl$route');
  
  try {
    final response = await client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _processResponse(response);
  } catch (e) {
    return _handleError('POST', url, e);
  }
}
```

---

## Backend Flow

### 1. Route Registration

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**Route Registration**:
```python
def register_routes(self):
    # Public routes (no authentication required)
    self._register_auth_route_helper("/public/register", self.create_user, methods=["POST"])
```

**Authentication Detection**:
- Routes starting with `/public/` → No authentication required
- Routes starting with `/userauth/` → JWT token required
- Routes starting with `/keyauth/` → API key required

**Route Helper**:
```python
def _register_auth_route_helper(self, route: str, view_func, methods: List[str] = None):
    auth_type = None
    
    if route.startswith('/public/'):
        auth_type = None  # Explicitly public
    elif route.startswith('/userauth/'):
        auth_type = 'jwt'
    elif route.startswith('/keyauth/'):
        auth_type = 'key'
    
    self._register_route_helper(route, view_func, methods, auth_type)
```

### 2. User Creation Handler

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**Method**: `create_user()`

#### Step 1: Request Validation

**Extract and Validate Required Fields**:
```python
required_fields = ["username", "email", "password"]
for field in required_fields:
    if not data.get(field):
        return jsonify({
            "success": False,
            "error": f"Missing required field: {field}"
        }), 400
```

**Email Format Validation**:
```python
if not self._is_valid_email(email):
    return jsonify({
        "success": False,
        "error": "Invalid email format"
    }), 400
```

**Password Strength Validation**:
```python
if not self._is_valid_password(password):
    return jsonify({
        "success": False,
        "error": "Password must be at least 8 characters long"
    }), 400
```

#### Step 2: Duplicate Checks

**Email Uniqueness**:
```python
existing_user = self.db_manager.find_one("users", {"email": email})
if existing_user:
    return jsonify({
        "success": False,
        "error": "User with this email already exists"
    }), 409
```

**Note**: The `DatabaseManager.find_one()` method automatically encrypts the search query for email (using deterministic encryption) before querying the database. This allows searching encrypted email fields.

**Username Uniqueness**:
```python
existing_username = self.db_manager.find_one("users", {"username": username})
if existing_username:
    return jsonify({
        "success": False,
        "error": "Username already taken"
    }), 409
```

**Note**: Similar to email, the username query is automatically encrypted (deterministic) before database lookup.

#### Step 3: Password Hashing

**Bcrypt Hashing**:
```python
hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
```

#### Step 4: User Data Structure Creation

**Complete User Document Structure**:

```python
user_data = {
    # Core fields
    'username': username,
    'email': email,
    'password': hashed_password.decode('utf-8'),
    'status': 'active',
    'created_at': current_time.isoformat(),
    'updated_at': current_time.isoformat(),
    'last_login': None,
    'login_count': 0,
    
    # Profile section
    'profile': {
        'first_name': data.get('first_name', ''),
        'last_name': data.get('last_name', ''),
        'phone': data.get('phone', ''),
        'timezone': data.get('timezone', 'UTC'),
        'language': data.get('language', 'en')
    },
    
    # Preferences section
    'preferences': {
        'notifications': {
            'email': data.get('notifications_email', True),
            'sms': data.get('notifications_sms', False),
            'push': data.get('notifications_push', True)
        },
        'privacy': {
            'profile_visible': data.get('profile_visible', True),
            'activity_visible': data.get('activity_visible', False)
        }
    },
    
    # Modules section with default configurations
    'modules': {
        'wallet': {
            'enabled': True,
            'balance': 0,
            'currency': 'credits',
            'last_updated': current_time.isoformat()
        },
        'subscription': {
            'enabled': False,
            'plan': None,
            'expires_at': None
        },
        'referrals': {
            'enabled': True,
            'referral_code': f"{username.upper()}{current_time.strftime('%Y%m')}",
            'referrals_count': 0
        },
        'cleco_game': {
            'enabled': True,
            'wins': 0,
            'losses': 0,
            'total_matches': 0,
            'points': 0,
            'level': 1,
            'rank': 'beginner',
            'win_rate': 0.0,
            'subscription_tier': 'promotional',  # Default: promotional tier (free play)
            'last_match_date': None,
            'last_updated': current_time.isoformat()
        }
    },
    
    # Audit section
    'audit': {
        'last_login': None,
        'login_count': 0,
        'password_changed_at': current_time.isoformat(),
        'profile_updated_at': current_time.isoformat()
    }
}
```

#### Step 5: Database Insertion

```python
user_id = self.db_manager.insert("users", user_data)

if not user_id:
    return jsonify({
        "success": False,
        "error": "Failed to create user account"
    }), 500
```

**Note**: The `DatabaseManager.insert()` method automatically encrypts sensitive fields (email, username, phone, etc.) before inserting into MongoDB. The encryption is transparent to the registration code - you pass plain text data, and it's encrypted automatically.

#### Step 6: Hook Triggering

```python
if self.app_manager:
    from utils.config.config import Config
    
    hook_data = {
        'user_id': user_id,
        'username': username,
        'email': email,  # Raw email from request (non-encrypted)
        'user_data': user_data,
        'created_at': current_time.isoformat(),
        'app_id': Config.APP_ID,
        'app_name': Config.APP_NAME,
        'source': 'external_app'
    }
    self.app_manager.trigger_hook("user_created", hook_data)
```

#### Step 7: Response

```python
# Remove password from response
user_data.pop('password', None)
user_data['_id'] = user_id

return jsonify({
    "success": True,
    "message": "User created successfully",
    "data": {
        "user": user_data
    }
}), 201
```

---

## Guest Registration

### Overview

Guest registration allows users to create accounts without providing email or password. The system auto-generates all required credentials, making it quick and easy for users to start using the application without the friction of traditional registration.

**Key Features**:
- No user input required (no email, no password)
- Auto-generated credentials
- Persistent across app restarts and logouts
- Seamless re-login experience
- Full account functionality (same as regular accounts)

### Guest Account Characteristics

**Auto-Generated Credentials**:
- **Username**: `Guest_{8_char_random_id}` (e.g., `Guest_a3f8b2c1`)
- **Email**: `guest_{username}@guest.local` (e.g., `guest_Guest_a3f8b2c1@guest.local`)
- **Password**: Same as username (e.g., `Guest_a3f8b2c1`)

**Account Type**:
- Marked with `account_type: 'guest'` in user document
- Distinguished from regular accounts for special handling

**Credential Persistence**:
- Guest credentials stored in permanent SharedPreferences keys
- Never cleared on logout or token expiration
- Allows seamless re-login after app restart

### Frontend Flow

#### 1. Guest Registration UI

**Location**: `flutter_base_05/lib/screens/account_screen/account_screen.dart`

**UI Components**:
- "Continue as Guest" button in registration form
- Appears only in registration mode
- Helper text: "No email or password required"

**Registration Handler**:
```dart
Future<void> _handleGuestRegister() async {
  // 1. Set loading state
  setState(() {
    _isLoading = true;
    _clearMessages();
  });
  
  // 2. Call LoginModule
  final result = await _loginModule!.registerGuestUser(
    context: context,
  );
  
  // 3. Handle response
  if (result['success'] != null) {
    final username = result['username']?.toString() ?? '';
    // Show success message with username
    // Auto-login if successful
  }
}
```

#### 2. LoginModule Guest Registration

**Location**: `flutter_base_05/lib/modules/login_module/login_module.dart`

**Method**: `registerGuestUser()`

**Process**:

##### Step 1: API Request
```dart
final response = await _connectionModule!.sendPostRequest(
  "/public/register-guest",
  {},  // No parameters required
);
```

##### Step 2: Credential Storage

**Permanent Keys** (never cleared on logout):
```dart
await _sharedPref!.setString('guest_username', username);
await _sharedPref!.setString('guest_email', email);
await _sharedPref!.setString('guest_user_id', userId);
await _sharedPref!.setBool('is_guest_account', true);
```

**Session Keys** (for current session):
```dart
await _sharedPref!.setString('username', username);
await _sharedPref!.setString('email', email);
await _sharedPref!.setString('user_id', userId);
```

##### Step 3: Auto-Login
```dart
// Automatically log in the guest user after registration
final loginResult = await loginUser(
  context: context,
  email: email,
  password: password,  // Same as username
);
```

#### 3. Guest Re-Login Features

**Auto-Population**:
- When login screen loads, checks for preserved guest credentials
- Auto-populates login form with:
  - Email: `guest_{username}@guest.local`
  - Password: `{username}`

**"Continue as Guest" Button**:
- Appears in login mode if guest credentials exist
- Automatically uses stored credentials
- One-click re-login experience

**Implementation**:
```dart
Future<void> _checkForGuestCredentials() async {
  final sharedPref = SharedPrefManager();
  await sharedPref.initialize();
  
  final isGuestAccount = sharedPref.getBool('is_guest_account') ?? false;
  final guestUsername = sharedPref.getString('guest_username');
  
  if (isGuestAccount && guestUsername != null) {
    // Auto-populate login form
    final guestEmailFull = 'guest_$guestUsername@guest.local';
    _emailController.text = guestEmailFull;
    _passwordController.text = guestUsername;
  }
}
```

#### 4. Logout Handling

**Guest Account Logout**:
```dart
if (isGuestAccount) {
  // Only clear session keys, preserve permanent guest credentials
  await _sharedPref!.remove('user_id');
  await _sharedPref!.remove('username');
  await _sharedPref!.remove('email');
  // DO NOT clear: guest_username, guest_email, guest_user_id, is_guest_account
}
```

**Regular Account Logout**:
```dart
else {
  // Clear all credentials (existing behavior)
  await _sharedPref!.remove('user_id');
  await _sharedPref!.remove('username');
  await _sharedPref!.remove('email');
}
```

#### 5. Session Validation & Restoration

**Location**: `flutter_base_05/lib/core/managers/auth_manager.dart`

**Process**:
```dart
Future<AuthStatus> validateSessionOnStartup() async {
  // Check if guest account credentials exist
  final isGuestAccount = _sharedPref!.getBool('is_guest_account') ?? false;
  final guestUsername = _sharedPref!.getString('guest_username');
  final guestEmail = _sharedPref!.getString('guest_email');
  
  // Restore guest credentials to session keys if tokens expire
  if (isGuestAccount && guestUsername != null && guestEmail != null) {
    await _sharedPref!.setString('username', guestUsername);
    await _sharedPref!.setString('email', guestEmail);
    await _sharedPref!.setString('user_id', guestUserId);
  }
  
  // Continue with normal session validation...
}
```

### Backend Flow

#### 1. Route Registration

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**Route**:
```python
self._register_auth_route_helper("/public/register-guest", self.create_guest_user, methods=["POST"])
```

#### 2. Guest Username Generation

**Method**: `_generate_guest_username()`

**Process**:
```python
def _generate_guest_username(self):
    """Generate unique guest username in format Guest_*******"""
    max_attempts = 10
    for attempt in range(max_attempts):
        # Generate 8-character random ID (lowercase letters + digits)
        random_id = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(8))
        username = f"Guest_{random_id}"
        
        # Check uniqueness
        existing = self.db_manager.find_one("users", {"username": username})
        if not existing:
            return username
    
    # If all attempts fail, raise exception
    raise Exception("Failed to generate unique guest username")
```

**Characteristics**:
- Format: `Guest_{8_char_random_id}`
- Random ID: 8 characters, lowercase letters + digits
- Uniqueness: Checked against database
- Retry: Up to 10 attempts on collision

#### 3. Guest User Creation

**Method**: `create_guest_user()`

**Process**:

##### Step 1: Generate Credentials
```python
# Generate unique guest username
username = self._generate_guest_username()

# Generate email from username
email = f"guest_{username}@guest.local"

# Use username as password
password = username
```

##### Step 2: Password Hashing
```python
hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
```

##### Step 3: User Data Structure

**Same structure as regular user, with additions**:
```python
user_data = {
    # Core fields
    'username': username,
    'email': email,
    'password': hashed_password.decode('utf-8'),
    'status': 'active',
    'account_type': 'guest',  # Mark as guest account
    'created_at': current_time.isoformat(),
    # ... rest of structure same as regular user
    
    # Preferences (guest-specific defaults)
    'preferences': {
        'notifications': {
            'email': False,  # Guest accounts don't need email notifications
            'sms': False,
            'push': True
        },
        # ...
    }
}
```

##### Step 4: Database Insertion
```python
user_id = self.db_manager.insert("users", user_data)
```

##### Step 5: Hook Triggering
```python
hook_data = {
    'user_id': user_id,
    'username': username,
    'email': email,
    'user_data': user_data,
    'created_at': current_time.isoformat(),
    'app_id': Config.APP_ID,
    'app_name': Config.APP_NAME,
    'source': 'external_app',
    'account_type': 'guest'  # Include account type in hook data
}
self.app_manager.trigger_hook("user_created", hook_data)
```

##### Step 6: Response
```python
return jsonify({
    "success": True,
    "message": "Guest account created successfully",
    "data": {
        "user": user_data,
        "credentials": {
            "username": username,
            "email": email,
            "password": password  # Return password so frontend can store it
        }
    }
}), 201
```

#### 4. Guest Account Login Detection

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**In `login_user()` method**:
```python
# Check if this is a guest account
account_type = user.get("account_type", "regular")
is_guest = account_type == "guest"

if is_guest:
    custom_log(f"Guest account login attempt - Email: {email}, Username: {user.get('username')}")
```

### Guest Registration Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  Guest Registration Flow                     │
└─────────────────────────────────────────────────────────────┘

User Clicks "Continue as Guest" (AccountScreen)
    ↓
_handleGuestRegister()
    ↓
LoginModule.registerGuestUser()
    ↓
HTTP POST /public/register-guest
    ↓
UserManagementModule.create_guest_user()
    ↓
Generate Unique Username (Guest_*******)
    ↓
Generate Email (guest_{username}@guest.local)
    ↓
Set Password = Username
    ↓
Hash Password (bcrypt)
    ↓
Create User Data (account_type: 'guest')
    ↓
DatabaseManager.insert() - Automatic Encryption
    ├─ Email → Deterministic encryption (det_...)
    ├─ Username → Deterministic encryption (det_...)
    └─ Phone → Fernet encryption (if provided)
    ↓
Database Insert (MongoDB - encrypted data)
    ↓
Hook Trigger: user_created (with account_type: 'guest')
    ↓
Response with Credentials
    ↓
Frontend: Store Permanent Guest Credentials
    ↓
Frontend: Auto-Login Guest User
    ↓
User Logged In
```

### Guest Re-Login Flow

```
App Startup / After Logout
    ↓
AccountScreen.initState()
    ↓
_checkForGuestCredentials()
    ↓
Check SharedPreferences for guest_username
    ↓
If Found:
    ↓
    Auto-Populate Login Form
    (Email: guest_{username}@guest.local, Password: {username})
    ↓
    Show "Continue as Guest" Button
    ↓
User Clicks "Continue as Guest" or Submits Form
    ↓
LoginModule.loginUser()
    ↓
HTTP POST /public/login
    ↓
Backend: Detect Guest Account (account_type: 'guest')
    ↓
Backend: Validate Credentials
    ↓
Response: JWT Tokens
    ↓
Frontend: Store Tokens & Session Data
    ↓
User Logged In
```

### Credential Persistence

#### Permanent SharedPreferences Keys

These keys are **never cleared** on logout or token expiration:

- `guest_username` - Guest username (e.g., `Guest_a3f8b2c1`)
- `guest_email` - Guest email (e.g., `guest_Guest_a3f8b2c1@guest.local`)
- `guest_user_id` - Guest user ID
- `is_guest_account` - Boolean flag (`true` for guest accounts)

#### Session SharedPreferences Keys

These keys are cleared on logout but restored from permanent keys when needed:

- `username` - Current session username
- `email` - Current session email
- `user_id` - Current session user ID
- `is_logged_in` - Current session status

#### Credential Lifecycle

1. **Registration**: Store in both permanent and session keys
2. **Logout**: Clear session keys, preserve permanent keys
3. **Token Expiration**: Clear session keys, preserve permanent keys
4. **App Restart**: Restore session keys from permanent keys if guest account
5. **Re-Login**: Use restored credentials for seamless login

### API Endpoints

#### Guest Registration

**Endpoint**: `POST /public/register-guest`

**Request Body**: `{}` (empty, no parameters required)

**Success Response (201 Created)**:
```json
{
  "success": true,
  "message": "Guest account created successfully",
  "data": {
    "user": {
      "_id": "ObjectId",
      "username": "Guest_a3f8b2c1",
      "email": "guest_Guest_a3f8b2c1@guest.local",
      "account_type": "guest",
      "status": "active",
      "created_at": "ISO 8601 timestamp",
      "profile": { ... },
      "preferences": { ... },
      "modules": { ... },
      "audit": { ... }
    },
    "credentials": {
      "username": "Guest_a3f8b2c1",
      "email": "guest_Guest_a3f8b2c1@guest.local",
      "password": "Guest_a3f8b2c1"
    }
  }
}
```

**Error Response (500 Internal Server Error)**:
```json
{
  "success": false,
  "error": "Internal server error"
}
```

**Error Scenarios**:
- Username generation failure (after 10 collision attempts)
- Database insertion failure
- Hook system failure

#### Guest Login

**Endpoint**: `POST /public/login` (same as regular login)

**Request Body**:
```json
{
  "email": "guest_Guest_a3f8b2c1@guest.local",
  "password": "Guest_a3f8b2c1"
}
```

**Response**: Same as regular login (includes `account_type: 'guest'` in user data)

### Data Structures

#### Guest User Document

**Additional Field**:
```json
{
  "_id": "ObjectId",
  "username": "Guest_a3f8b2c1",
  "email": "guest_Guest_a3f8b2c1@guest.local",
  "password": "bcrypt_hashed_password",
  "account_type": "guest",  // NEW FIELD
  "status": "active",
  // ... rest same as regular user
}
```

#### SharedPreferences Structure

**Permanent Keys** (persist across logouts):
```dart
{
  "guest_username": "Guest_a3f8b2c1",
  "guest_email": "guest_Guest_a3f8b2c1@guest.local",
  "guest_user_id": "ObjectId",
  "is_guest_account": true
}
```

**Session Keys** (cleared on logout):
```dart
{
  "username": "Guest_a3f8b2c1",
  "email": "guest_Guest_a3f8b2c1@guest.local",
  "user_id": "ObjectId",
  "is_logged_in": true
}
```

### Security Considerations

#### 1. Credential Generation

**Randomness**:
- Uses `secrets` module (cryptographically secure)
- 8-character random ID provides sufficient entropy
- Format: `Guest_{8_char_random_id}` ensures uniqueness

**Uniqueness**:
- Database check before assignment
- Retry mechanism (up to 10 attempts)
- Exception raised if all attempts fail

#### 2. Password Security

**Same Security as Regular Accounts**:
- Passwords hashed with bcrypt
- Same salt generation
- Same storage format

**Password = Username**:
- System requirement (password field must exist)
- User never needs to know password
- Login uses email + password (both auto-generated)

#### 3. Credential Persistence

**Permanent Storage**:
- Guest credentials stored in SharedPreferences
- Never cleared on logout
- Survives app restarts

**Security Implications**:
- Credentials accessible to app only
- Protected by device security
- Lost if app is uninstalled

#### 4. Account Type Distinction

**Purpose**:
- Allows different handling for guest vs regular accounts
- Enables future features (upgrade to regular account, etc.)
- Analytics and reporting

**Privacy**:
- Guest accounts marked in database
- Can be filtered/identified for special handling
- No additional privacy concerns

### Error Handling

#### Username Collision

**Scenario**: Generated username already exists in database

**Handling**:
- Retry with new random ID (up to 10 attempts)
- If all attempts fail, return 500 error
- Log collision attempts for monitoring

**Response**:
```json
{
  "success": false,
  "error": "Internal server error"
}
```

#### Database Insertion Failure

**Scenario**: User document insertion fails

**Handling**:
- Return 500 error
- Log error details
- No partial data created

**Response**:
```json
{
  "success": false,
  "error": "Failed to create guest account"
}
```

### UI/UX Features

#### Registration Screen

**"Continue as Guest" Button**:
- Prominent placement in registration form
- Clear messaging: "No email or password required"
- One-click registration

#### Login Screen

**Auto-Population**:
- Form automatically filled with guest credentials
- User can immediately click "Sign In"
- No typing required

**"Continue as Guest" Button**:
- Appears if guest credentials exist
- Helper text: "Use your saved guest account"
- One-click re-login

**Success Messages**:
- After registration: "Guest account created! Your username is: Guest_*******"
- After login: "Welcome back, Guest_*******!"

### Related Files

**Frontend**:
- `flutter_base_05/lib/screens/account_screen/account_screen.dart`
  - Guest registration UI
  - Guest login UI
  - Credential auto-population
  - "Continue as Guest" buttons

- `flutter_base_05/lib/modules/login_module/login_module.dart`
  - `registerGuestUser()` method
  - Guest credential storage
  - Guest account detection in login
  - Logout handling for guest accounts

- `flutter_base_05/lib/core/managers/auth_manager.dart`
  - Guest credential restoration on session validation
  - Token expiration handling for guests

- `flutter_base_05/lib/core/services/shared_preferences.dart`
  - Permanent credential storage
  - Credential retrieval

**Backend**:
- `python_base_04/core/modules/user_management_module/user_management_main.py`
  - `create_guest_user()` method
  - `_generate_guest_username()` helper
  - Guest account detection in login
  - Route registration

### Future Improvements

#### 1. Guest Account Upgrade

**Proposed Enhancement**:
- Allow guests to upgrade to regular accounts
- Add email/password to existing guest account
- Preserve game history and data
- Convert `account_type` from 'guest' to 'regular'

#### 2. Guest Account Expiration

**Proposed Enhancement**:
- Auto-delete inactive guest accounts after X days
- Cleanup mechanism for abandoned accounts
- Notification before expiration

#### 3. Multiple Guest Accounts

**Proposed Enhancement**:
- Allow users to create multiple guest accounts
- Switch between guest accounts
- Account selection UI

#### 4. Guest Account Limits

**Proposed Enhancement**:
- Limit features available to guest accounts
- Encourage upgrade to regular accounts
- Feature comparison UI

#### 5. Guest Account Analytics

**Proposed Enhancement**:
- Track guest account creation
- Track guest account usage
- Track conversion to regular accounts
- Analytics dashboard

---

## Google Sign-In

### Overview

Google Sign-In allows users to authenticate using their Google accounts, providing a quick and secure alternative to email/password registration. The implementation uses Flutter's `google_sign_in` package on the frontend and verifies Google ID tokens on the Python backend, seamlessly integrating with the existing JWT authentication system.

**Key Features**:
- One-click authentication with Google account
- Automatic account creation for new users
- Account linking for existing users (by email)
- Same JWT token system as email/password login
- Platform-specific handling (Web, Android, iOS)

### Architecture

**Approach**: Flutter-side Google Sign-In with backend token verification
- Flutter handles the Google OAuth flow using `google_sign_in` package
- Backend verifies the Google ID token (or access token on web) and creates/updates user accounts
- Returns standard JWT tokens (same as email/password login)
- Supports both new user registration and existing user login

**Why this approach**:
- Better UX for mobile apps (no redirects)
- Reuses existing JWT token system
- Can link Google accounts to existing email accounts
- Simpler implementation than full OAuth2 redirect flow

### Frontend Flow

#### 1. User Interface (AccountScreen)

**Location**: `flutter_base_05/lib/screens/account_screen/account_screen.dart`

**UI Components**:
- "Sign in with Google" button in login mode
- "Sign up with Google" button in registration mode
- Positioned above email/password form with "OR" divider
- Google logo icon (with fallback to login icon)

**Button Handler**:
```dart
Future<void> _handleGoogleSignIn() async {
  setState(() {
    _isLoading = true;
    _clearMessages();
  });
  
  try {
    final result = await _loginModule!.signInWithGoogle(
      context: context,
    );
    
    if (result['success'] != null) {
      setState(() {
        _successMessage = result['success'];
        _isLoading = false;
      });
      // Navigate to main screen after successful login
      Future.delayed(const Duration(seconds: 2), () {
        context.go('/');
      });
    } else {
      setState(() {
        _errorMessage = result['error'];
        _isLoading = false;
      });
    }
  } catch (e) {
    setState(() {
      _errorMessage = 'An unexpected error occurred: $e';
      _isLoading = false;
    });
  }
}
```

#### 2. LoginModule Google Sign-In Logic

**Location**: `flutter_base_05/lib/modules/login_module/login_module.dart`

**Method**: `signInWithGoogle()`

**Process**:

##### Step 1: Initialize GoogleSignIn

**Platform-Specific Configuration**:
```dart
final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile', 'openid'],
  // Web requires explicit client ID
  clientId: kIsWeb ? Config.googleClientId : null,
);
```

**Configuration**:
- **Scopes**: `['email', 'profile', 'openid']` - Required for ID token retrieval
- **Web Client ID**: Required for web platform (from `Config.googleClientId`)
- **Mobile**: Client ID not needed (uses app configuration)

##### Step 2: Sign-In Flow

**Web-Specific Handling**:
```dart
GoogleSignInAccount? googleUser;
if (kIsWeb) {
  try {
    // Try silent sign-in first (for returning users)
    googleUser = await googleSignIn.signInSilently();
  } catch (e) {
    // Silent sign-in failed, will prompt user
  }
}

// If silent sign-in didn't work or not on web, prompt user
if (googleUser == null) {
  googleUser = await googleSignIn.signIn();
}
```

**User Cancellation**:
```dart
if (googleUser == null) {
  return {"error": "Sign-in cancelled"};
}
```

##### Step 3: Get Authentication Tokens

```dart
final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
final String? idToken = googleAuth.idToken;
final String? accessToken = googleAuth.accessToken;
```

##### Step 4: Handle Token Types

**ID Token (Preferred - Mobile)**:
```dart
if (idToken != null) {
  // Send ID token to backend
  requestPayload = {"id_token": idToken};
}
```

**Access Token (Fallback - Web)**:
```dart
else if (accessToken != null && kIsWeb) {
  // Fetch user info from Google using access token
  final userInfoResponse = await http.get(
    Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
    headers: {'Authorization': 'Bearer $accessToken'},
  );
  
  if (userInfoResponse.statusCode == 200) {
    final userInfo = json.decode(userInfoResponse.body);
    // Send access token and user info to backend
    requestPayload = {
      "access_token": accessToken,
      "user_info": userInfo,
    };
  }
}
```

##### Step 5: Send to Backend

```dart
final response = await _connectionModule!.sendPostRequest(
  "/public/google-signin",
  requestPayload,
);
```

##### Step 6: Process Response

```dart
if (response?["success"] == true) {
  // Store JWT tokens
  await AuthManager().storeTokens(
    accessToken: response["data"]["access_token"],
    refreshToken: response["data"]["refresh_token"],
  );
  
  // Store user data
  final userData = response["data"]["user"];
  await _sharedPref!.setString('username', userData["username"]);
  await _sharedPref!.setString('email', userData["email"]);
  await _sharedPref!.setString('user_id', userData["_id"]);
  
  return {"success": "Google Sign-In successful"};
}
```

### Backend Flow

#### 1. Route Registration

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**Route**:
```python
self._register_auth_route_helper("/public/google-signin", self.google_signin, methods=["POST"])
```

#### 2. Google Sign-In Handler

**Location**: `python_base_04/core/modules/user_management_module/user_management_main.py`

**Method**: `google_signin()`

**Process**:

##### Step 1: Extract Token/User Info

```python
data = request.get_json()
id_token_string = data.get("id_token")
access_token = data.get("access_token")
user_info_from_client = data.get("user_info")  # For web fallback
```

##### Step 2: Verify Token

**ID Token Verification (Mobile)**:
```python
if id_token_string:
    google_auth_service = GoogleAuthService()
    user_info = google_auth_service.get_user_info(id_token_string)
```

**Access Token Verification (Web)**:
```python
elif access_token and user_info_from_client:
    # Verify access token by calling Google's tokeninfo endpoint
    token_info_response = http_requests.get(
        f'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token={access_token}',
        timeout=10
    )
    
    if token_info_response.status_code == 200:
        token_info = token_info_response.json()
        # Verify email matches
        # Use user info from client
        user_info = {
            'google_id': user_info_from_client.get('id'),
            'email': user_info_from_client.get('email'),
            'email_verified': user_info_from_client.get('verified_email', False),
            'name': user_info_from_client.get('name'),
            'picture': user_info_from_client.get('picture'),
            'given_name': user_info_from_client.get('given_name'),
            'family_name': user_info_from_client.get('family_name')
        }
```

##### Step 3: Check for Existing User

**Account Linking by Email**:
```python
# Check if user exists by email
existing_user = self.db_manager.find_one("users", {"email": user_info['email']})

if existing_user:
    # Link Google account to existing user
    # Update auth_providers to include 'google'
    auth_providers = existing_user.get('auth_providers', [])
    if 'google' not in auth_providers:
        auth_providers.append('google')
        self.db_manager.update("users", {"_id": existing_user['_id']}, {
            "auth_providers": auth_providers
        })
    user_id = existing_user['_id']
else:
    # Create new user account
    # Generate username from email or name
    username = self._generate_username_from_google(user_info)
    # Create user with Google authentication
    user_id = self._create_user_from_google(user_info, username)
```

##### Step 4: Generate JWT Tokens

```python
jwt_manager = self.app_manager.jwt_manager
access_token = jwt_manager.create_access_token(
    user_id=str(user_id),
    additional_claims={"username": username, "email": user_info['email']}
)
refresh_token = jwt_manager.create_refresh_token(user_id=str(user_id))
```

##### Step 5: Response

```python
return jsonify({
    "success": True,
    "message": "Google Sign-In successful",
    "data": {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "user": {
            "_id": str(user_id),
            "username": username,
            "email": user_info['email'],
            "auth_providers": auth_providers
        }
    }
}), 200
```

### Google Sign-In Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  Google Sign-In Flow                         │
└─────────────────────────────────────────────────────────────┘

User Clicks "Sign in with Google" (AccountScreen)
    ↓
_handleGoogleSignIn()
    ↓
LoginModule.signInWithGoogle()
    ↓
Initialize GoogleSignIn (with scopes: email, profile, openid)
    ↓
[Web: Try signInSilently() first]
    ↓
googleSignIn.signIn() - User selects Google account
    ↓
Get GoogleSignInAuthentication
    ├─ ID Token (Mobile) OR
    └─ Access Token (Web)
    ↓
[Web Only: Fetch user info from Google API using access token]
    ↓
Send to Backend: POST /public/google-signin
    ├─ {id_token: "..."} OR
    └─ {access_token: "...", user_info: {...}}
    ↓
UserManagementModule.google_signin()
    ↓
Verify Token (ID token or access token)
    ↓
Extract User Info (email, name, picture, etc.)
    ↓
Check for Existing User by Email
    ├─ If exists: Link Google account (update auth_providers)
    └─ If not: Create new user account
    ↓
Generate JWT Tokens (access + refresh)
    ↓
Response: JWT Tokens + User Data
    ↓
Frontend: Store Tokens & User Data
    ↓
User Logged In
```

### Account Linking

**Behavior**: If a user signs in with Google using an email that already exists in the system (from email/password registration), the system automatically links the Google account to the existing user account.

**Process**:
1. User signs in with Google
2. Backend extracts email from Google token
3. Backend checks if user exists with that email
4. If exists:
   - Updates `auth_providers` field to include `'google'`
   - Returns existing user account
   - Issues JWT tokens
5. If not exists:
   - Creates new user account
   - Sets `auth_providers: ['google']`
   - Issues JWT tokens

**User Document Update**:
```python
auth_providers = existing_user.get('auth_providers', [])
if 'google' not in auth_providers:
    auth_providers.append('google')
    self.db_manager.update("users", {"_id": existing_user['_id']}, {
        "auth_providers": auth_providers
    })
```

### Platform-Specific Handling

#### Web Platform

**Requirements**:
- Explicit `clientId` must be provided to `GoogleSignIn` constructor
- Client ID stored in `Config.googleClientId`
- JavaScript origins must be registered in Google Cloud Console

**Token Handling**:
- Web may not always return ID tokens
- Fallback to access token + user info API call
- Access token verified via Google's tokeninfo endpoint

**Configuration**:
```dart
// In flutter_base_05/lib/utils/consts/config.dart
static const String googleClientId = String.fromEnvironment(
  'GOOGLE_CLIENT_ID',
  defaultValue: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
);
```

#### Mobile Platforms (Android/iOS)

**Requirements**:
- Client ID configured in platform-specific files
- Android: SHA fingerprints in Google Cloud Console
- iOS: Reversed client ID in Info.plist

**Token Handling**:
- ID tokens are reliably available
- No fallback needed

### API Endpoints

#### Google Sign-In

**Endpoint**: `POST /public/google-signin`

**Request Body (ID Token)**:
```json
{
  "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6Ij..."
}
```

**Request Body (Access Token - Web)**:
```json
{
  "access_token": "ya29.a0AfH6SMC...",
  "user_info": {
    "id": "114551541773982562267",
    "email": "user@example.com",
    "verified_email": true,
    "name": "John Doe",
    "picture": "https://...",
    "given_name": "John",
    "family_name": "Doe"
  }
}
```

**Success Response (200 OK)**:
```json
{
  "success": true,
  "message": "Google Sign-In successful",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "_id": "ObjectId",
      "username": "johndoe",
      "email": "user@example.com",
      "auth_providers": ["google"]
    }
  }
}
```

**Error Response (400 Bad Request)**:
```json
{
  "success": false,
  "error": "Google ID token or access token is required"
}
```

**Error Response (401 Unauthorized)**:
```json
{
  "success": false,
  "error": "Invalid or expired Google token"
}
```

**Error Response (503 Service Unavailable)**:
```json
{
  "success": false,
  "error": "Google Sign-In is not available. Please install google-auth package."
}
```

### Data Structures

#### User Document with Google Authentication

**Additional Field**:
```json
{
  "_id": "ObjectId",
  "username": "johndoe",
  "email": "user@example.com",
  "auth_providers": ["google"],  // NEW FIELD
  "status": "active",
  // ... rest same as regular user
}
```

**Auth Providers Field**:
- **Type**: Array of strings
- **Values**: `['email']`, `['google']`, or `['email', 'google']`
- **Purpose**: Tracks which authentication methods are linked to the account
- **Default**: `['email']` for regular registration, `['google']` for Google-only accounts

### Security Features

#### 1. Token Verification

**ID Token Verification**:
- Uses `google-auth` Python library
- Verifies token signature
- Validates token issuer (accounts.google.com)
- Checks token expiration
- Verifies audience (client ID)

**Access Token Verification (Web)**:
- Calls Google's tokeninfo endpoint
- Verifies token validity
- Validates client ID (audience)
- Checks email match between token and user info

#### 2. Account Linking Security

**Email Verification**:
- Only links accounts with matching verified emails
- Prevents unauthorized account linking
- Requires email verification from Google

#### 3. Error Handling

**Security-Conscious Error Messages**:
- Generic error messages for invalid tokens
- No disclosure of internal verification details
- Proper HTTP status codes

### Error Handling

#### Common Errors

**1. "Sign-in cancelled"**:
- User cancelled the Google Sign-In flow
- Normal behavior, not an error

**2. "Error 400: redirect_uri_mismatch"**:
- **Cause**: JavaScript origin not registered in Google Cloud Console
- **Fix**: Add origin (e.g., `http://localhost:3002`) to Authorized JavaScript origins

**3. "Error 403: People API has not been used"**:
- **Cause**: People API not enabled in Google Cloud Console
- **Fix**: Enable People API in APIs & Services → Library

**4. "No ID token received"**:
- **Cause**: Web platform may not return ID tokens
- **Fix**: System automatically falls back to access token method

**5. "Invalid or expired Google token"**:
- **Cause**: Token verification failed
- **Fix**: User should try signing in again

### Configuration Requirements

#### Google Cloud Console Setup

**Required Steps**:
1. Create OAuth 2.0 Client ID for Web
2. Create OAuth 2.0 Client ID for Android (with SHA fingerprints)
3. Create OAuth 2.0 Client ID for iOS (with bundle ID)
4. Enable People API
5. Add authorized JavaScript origins (for web)
6. Configure OAuth consent screen

#### Backend Configuration

**Required Environment Variables/Secrets**:
- `GOOGLE_CLIENT_ID`: Web Client ID (for token verification)
- `GOOGLE_CLIENT_SECRET`: Client Secret (optional, for future use)

**Configuration Priority**:
1. HashiCorp Vault (`flask-app/google-oauth`)
2. Secret files (`secrets/google_client_id`, `secrets/google_client_secret`)
3. Environment variables (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`)
4. Default values (empty strings)

#### Frontend Configuration

**Required**:
- Web Client ID in `Config.googleClientId` (for web platform)
- Platform-specific configurations (Android SHA, iOS bundle ID)

### Related Files

**Frontend**:
- `flutter_base_05/lib/screens/account_screen/account_screen.dart`
  - Google Sign-In button UI
  - Button handler

- `flutter_base_05/lib/modules/login_module/login_module.dart`
  - `signInWithGoogle()` method
  - Token handling
  - Error handling

- `flutter_base_05/lib/utils/consts/config.dart`
  - `googleClientId` constant

- `flutter_base_05/pubspec.yaml`
  - `google_sign_in: ^6.2.1` dependency

**Backend**:
- `python_base_04/core/modules/user_management_module/user_management_main.py`
  - `google_signin()` method
  - Token verification
  - Account linking logic
  - User creation from Google

- `python_base_04/core/services/google_auth_service.py`
  - `GoogleAuthService` class
  - ID token verification
  - User info extraction

- `python_base_04/utils/config/config.py`
  - `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` configuration

- `python_base_04/requirements.txt`
  - `google-auth==2.23.4` dependency

### Future Improvements

#### 1. Additional OAuth Providers

**Proposed Enhancement**:
- Facebook Sign-In
- Apple Sign-In
- GitHub Sign-In
- Twitter/X Sign-In

#### 2. Profile Picture Sync

**Proposed Enhancement**:
- Automatically sync Google profile picture
- Store in user profile
- Update on each Google Sign-In

#### 3. Enhanced Account Linking

**Proposed Enhancement**:
- Allow users to manually link/unlink accounts
- UI for managing connected accounts
- Security verification for unlinking

#### 4. Google Account Disconnection

**Proposed Enhancement**:
- Allow users to disconnect Google account
- Prevent disconnection if it's the only auth method
- Require password setup before disconnection

---

## Data Structures

### User Document Structure

**MongoDB Collection**: `users`

**Document Schema**:

```json
{
  "_id": "ObjectId",
  "username": "string (encrypted: det_... or gAAAAAB...)",
  "email": "string (encrypted: det_... or gAAAAAB...)",
  "password": "string (bcrypt hashed, NOT encrypted)",
  "status": "string ('active' | 'inactive' | 'suspended')",
  "created_at": "ISO 8601 timestamp",
  "updated_at": "ISO 8601 timestamp",
  "last_login": "ISO 8601 timestamp | null",
  "login_count": "integer",
  
  "profile": {
    "first_name": "string",
    "last_name": "string",
    "phone": "string (encrypted: gAAAAAB... if provided)",
    "timezone": "string (default: 'UTC')",
    "language": "string (default: 'en')"
  },
  
  "preferences": {
    "notifications": {
      "email": "boolean (default: true)",
      "sms": "boolean (default: false)",
      "push": "boolean (default: true)"
    },
    "privacy": {
      "profile_visible": "boolean (default: true)",
      "activity_visible": "boolean (default: false)"
    }
  },
  
  "modules": {
    "wallet": {
      "enabled": "boolean (default: true)",
      "balance": "integer (default: 0)",
      "currency": "string (default: 'credits')",
      "last_updated": "ISO 8601 timestamp"
    },
    "subscription": {
      "enabled": "boolean (default: false)",
      "plan": "string | null",
      "expires_at": "ISO 8601 timestamp | null"
    },
    "referrals": {
      "enabled": "boolean (default: true)",
      "referral_code": "string (format: '{USERNAME}{YYYYMM}')",
      "referrals_count": "integer (default: 0)"
    },
    "cleco_game": {
      "enabled": "boolean (default: true)",
      "wins": "integer (default: 0)",
      "losses": "integer (default: 0)",
      "total_matches": "integer (default: 0)",
      "points": "integer (default: 0)",
      "level": "integer (default: 1)",
      "rank": "string (default: 'beginner')",
      "win_rate": "float (default: 0.0)",
      "subscription_tier": "string (default: 'promotional')",
      "coins": "integer (default: 0)",
      "last_match_date": "ISO 8601 timestamp | null",
      "last_updated": "ISO 8601 timestamp"
    }
  },
  
  "audit": {
    "last_login": "ISO 8601 timestamp | null",
    "login_count": "integer",
    "password_changed_at": "ISO 8601 timestamp",
    "profile_updated_at": "ISO 8601 timestamp"
  }
}
```

**Subscription Tier System (cleco_game module):**
- **subscription_tier**: Determines coin requirements for Cleco game
  - `'promotional'` (default): Free play - no coin check required, no coins deducted during gameplay
  - `'free'`: Requires coins - coin check and deduction applies
  - `'regular'`: Requires coins - coin check and deduction applies
- **coins**: Starting coin balance (default: 0)
- Both fields are initialized during user registration (both guest and regular accounts)
- Subscription tier affects coin validation before game creation/join and coin deduction when games start
- See `COIN_AVAILABILITY_LOGIC.md` for detailed information on how subscription tier affects gameplay
```

### API Request Payload

**Endpoint**: `POST /public/register`

**Request Body**:
```json
{
  "username": "string (required, 3-20 chars)",
  "email": "string (required, valid email format)",
  "password": "string (required, min 8 chars)",
  "first_name": "string (optional)",
  "last_name": "string (optional)",
  "phone": "string (optional)",
  "timezone": "string (optional, default: 'UTC')",
  "language": "string (optional, default: 'en')",
  "notifications_email": "boolean (optional, default: true)",
  "notifications_sms": "boolean (optional, default: false)",
  "notifications_push": "boolean (optional, default: true)",
  "profile_visible": "boolean (optional, default: true)",
  "activity_visible": "boolean (optional, default: false)"
}
```

### API Response

**Success Response (201 Created)**:
```json
{
  "success": true,
  "message": "User created successfully",
  "data": {
    "user": {
      "_id": "ObjectId",
      "username": "string",
      "email": "string",
      "status": "active",
      "created_at": "ISO 8601 timestamp",
      "updated_at": "ISO 8601 timestamp",
      "profile": { ... },
      "preferences": { ... },
      "modules": { ... },
      "audit": { ... }
    }
  }
}
```

**Error Response (400 Bad Request)**:
```json
{
  "success": false,
  "error": "Missing required field: username"
}
```

**Error Response (409 Conflict)**:
```json
{
  "success": false,
  "error": "User with this email already exists"
}
```

**Error Response (429 Too Many Requests)**:
```json
{
  "success": false,
  "error": "Too many registration attempts. Please try again later.",
  "status": 429
}
```

**Error Response (500 Internal Server Error)**:
```json
{
  "success": false,
  "error": "Internal server error"
}
```

---

## Validation Rules

### Frontend Validation

**Username**:
- Minimum length: 3 characters
- Maximum length: 20 characters
- Pattern: `^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$`
- Cannot contain consecutive special characters (`--`, `__`, `-_`, `_-`)
- Cannot start or end with special characters (`_`, `-`)

**Email**:
- Format: `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`
- Must contain `@` symbol
- Must have valid domain with TLD

**Password**:
- Minimum length: 8 characters
- No maximum length enforced
- No complexity requirements (letters, numbers, special characters)

### Backend Validation

**Username**:
- Same rules as frontend
- Additional check: Must be unique in database

**Email**:
- Same format validation as frontend
- Additional check: Must be unique in database

**Password**:
- Minimum length: 8 characters
- Hashed using bcrypt before storage

### Validation Error Messages

| Validation | Error Message |
|-----------|---------------|
| Missing username | "Missing required field: username" |
| Missing email | "Missing required field: email" |
| Missing password | "Missing required field: password" |
| Invalid email format | "Invalid email format" |
| Password too short | "Password must be at least 8 characters long" |
| Email already exists | "User with this email already exists" |
| Username already taken | "Username already taken" |
| Username too short | "Username must be at least 3 characters long" |
| Username too long | "Username cannot be longer than 20 characters" |
| Invalid username format | "Username can only contain letters, numbers, underscores, and hyphens" |
| Consecutive special chars | "Username cannot contain consecutive special characters" |
| Leading/trailing special chars | "Username cannot start or end with special characters" |

---

## Security Features

### 1. Password Security

**Hashing**:
- Algorithm: bcrypt
- Salt: Auto-generated by bcrypt
- Storage: Hashed password stored in database (never plain text)

**Password Handling**:
- Password never logged
- Password removed from API responses
- Password not included in hook data

### 2. Data Encryption at Rest

**Automatic Encryption**:
- All sensitive fields are automatically encrypted by `DatabaseManager` before database insertion
- Encryption happens transparently during `db_manager.insert()` operation
- No manual encryption required in registration code

**Encryption Process**:
```python
# In DatabaseManager._execute_insert()
encrypted_data = self._encrypt_sensitive_fields(data)
result = self.db[collection].insert_one(encrypted_data)
```

**Sensitive Fields Encrypted**:
Fields defined in `Config.SENSITIVE_FIELDS` are automatically encrypted:
- `email` - Deterministic encryption (searchable)
- `username` - Deterministic encryption (searchable)
- `phone` - Fernet encryption (non-deterministic)
- `user_id` - Fernet encryption
- `address` - Fernet encryption
- `credit_balance` - Fernet encryption
- `transaction_history` - Fernet encryption

**Encryption Methods**:

**Deterministic Encryption** (for `email` and `username`):
- **Purpose**: Allows searching/querying encrypted fields
- **Method**: SHA-256 hash with prefix
- **Format**: `det_{sha256_hash}`
- **Implementation**:
  ```python
  combined = ENCRYPTION_KEY.encode() + data.encode()
  encrypted_data = hashlib.sha256(combined).hexdigest()
  return f"det_{encrypted_data}"
  ```
- **Characteristics**:
  - Same input always produces same output
  - Enables exact-match queries on encrypted data
  - Less secure than Fernet (hash-based, not true encryption)
  - Used for fields that need to be searchable

**Fernet Encryption** (for other sensitive fields):
- **Purpose**: Strong encryption for non-searchable sensitive data
- **Method**: Fernet (AES-128 in CBC mode with HMAC)
- **Format**: Base64 string starting with `gAAAAAB`
- **Implementation**:
  ```python
  # Key derivation using PBKDF2
  kdf = PBKDF2HMAC(
      algorithm=hashes.SHA256(),
      length=32,
      salt=ENCRYPTION_SALT.encode(),
      iterations=100000
  )
  derived_key = base64.urlsafe_b64encode(kdf.derive(ENCRYPTION_KEY.encode()))
  fernet = Fernet(derived_key)
  encrypted_data = fernet.encrypt(data.encode())
  ```
- **Characteristics**:
  - Random IV each time (non-deterministic)
  - Strong encryption with authentication
  - Cannot search encrypted values directly
  - Used for fields that don't need searching

**Encryption Key Management**:
- **Primary Source**: HashiCorp Vault (`flask-app/app` → `encryption_key`)
- **Fallback**: Environment variable `ENCRYPTION_KEY`
- **Default (Development)**: `"development-encryption-key-change-in-production"`
- **Salt**: `ENCRYPTION_SALT` from Vault/env/default: `"default_salt_123"`

**Encryption During Registration**:
1. User data prepared in `create_user()` method
2. Data passed to `db_manager.insert("users", user_data)`
3. `DatabaseManager` automatically encrypts sensitive fields:
   - `email` → Deterministic hash (`det_...`)
   - `username` → Deterministic hash (`det_...`)
   - `phone` (if provided) → Fernet encryption (`gAAAAAB...`)
4. Encrypted data inserted into MongoDB
5. On retrieval, `DatabaseManager` automatically decrypts fields

**Decryption on Read**:
- `DatabaseManager` automatically decrypts sensitive fields when reading from database
- Methods like `find_one()` and `find()` return decrypted data
- Encryption/decryption is transparent to application code

**Example Encrypted Values**:
```json
{
  "_id": "ObjectId(...)",
  "email": "det_ef688dcc40b4be2528428e52b827e2b704130f966168c3da0c54db84f5fa0619",
  "username": "det_a1b2c3d4e5f6...",
  "phone": "gAAAAABobl2Vc5sJXbNwtPnHS7r74FBeKM3vIVJwU7p-KgEVyPueOfbNUWSx6r2m60aDUbafaV8FiBBQkPYt68GPZYjnEKdlbgWMutswXeYsVhEKSJWbWWE=",
  "password": "$2b$12$..."  // bcrypt hash (not encrypted)
}
```

**Security Considerations**:
- **Deterministic Encryption Trade-off**: Less secure but enables searching
- **Key Management**: Encryption keys stored securely in Vault
- **Key Rotation**: Changing encryption key requires re-encryption of all data
- **Backup Security**: Encrypted data remains secure in backups
- **Performance**: Minimal overhead (encryption happens during insert/update)

### 2. Input Validation

**Multi-Layer Validation**:
- Frontend validation (client-side)
- Backend validation (server-side)
- Database constraints (if applicable)

**Sanitization**:
- Username trimmed
- Email trimmed and lowercased (if needed)
- SQL injection prevention (using parameterized queries)

### 4. Duplicate Prevention

**Uniqueness Checks**:
- Email uniqueness enforced
- Username uniqueness enforced
- Database-level constraints (if configured)

### 4. Error Handling

**Security-Conscious Error Messages**:
- Generic error messages to avoid information leakage
- No disclosure of existing usernames/emails in error messages
- Internal server errors return generic messages

### 6. Rate Limiting

**Protection**:
- Rate limiting applied at API level
- Prevents brute force registration attempts
- Returns 429 status code when limit exceeded

### 6. Authentication

**Public Endpoint**:
- `/public/register` requires no authentication
- No JWT token needed
- Accessible to unauthenticated users

---

## Error Handling

### Error Scenarios

#### 1. Missing Required Fields

**Status**: 400 Bad Request

**Response**:
```json
{
  "success": false,
  "error": "Missing required field: {field_name}"
}
```

**Handling**:
- Frontend: Display error message to user
- Backend: Return 400 status code

#### 2. Invalid Email Format

**Status**: 400 Bad Request

**Response**:
```json
{
  "success": false,
  "error": "Invalid email format"
}
```

**Handling**:
- Frontend: Show validation error before submission
- Backend: Validate again and return error if invalid

#### 3. Password Too Short

**Status**: 400 Bad Request

**Response**:
```json
{
  "success": false,
  "error": "Password must be at least 8 characters long"
}
```

**Handling**:
- Frontend: Show validation error before submission
- Backend: Validate again and return error if invalid

#### 4. Email Already Exists

**Status**: 409 Conflict

**Response**:
```json
{
  "success": false,
  "error": "User with this email already exists"
}
```

**Handling**:
- Frontend: Display error message
- Backend: Check database before insertion

#### 5. Username Already Taken

**Status**: 409 Conflict

**Response**:
```json
{
  "success": false,
  "error": "Username already taken"
}
```

**Handling**:
- Frontend: Display error message
- Backend: Check database before insertion

#### 6. Database Error

**Status**: 500 Internal Server Error

**Response**:
```json
{
  "success": false,
  "error": "Internal server error"
}
```

**Handling**:
- Frontend: Display generic error message
- Backend: Log error details, return generic message

#### 7. Rate Limiting

**Status**: 429 Too Many Requests

**Response**:
```json
{
  "success": false,
  "error": "Too many registration attempts. Please try again later.",
  "status": 429
}
```

**Handling**:
- Frontend: Display rate limit message
- Backend: Rate limiter middleware handles this

#### 8. Network Error

**Status**: N/A (Client-side error)

**Response**:
```json
{
  "error": "Server error. Check network connection."
}
```

**Handling**:
- Frontend: Display network error message
- Backend: N/A (request never reached server)

### Error Flow

```
Error Occurs
    ↓
Backend: Return Error Response
    ↓
Frontend: Receive Error Response
    ↓
LoginModule: Parse Error
    ↓
AccountScreen: Display Error Message
    ↓
User: See Error and Can Retry
```

---

## Hook System

### User Created Hook

**Hook Name**: `user_created`

**Triggered**: After successful user creation in database

**Hook Data**:
```python
{
    'user_id': user_id,
    'username': username,
    'email': email,  # Raw email from request
    'user_data': user_data,  # Complete user document (without password)
    'created_at': current_time.isoformat(),
    'app_id': Config.APP_ID,
    'app_name': Config.APP_NAME,
    'source': 'external_app'
}
```

### Hook Listeners

#### CreditSystemModule

**Location**: `python_base_04/core/modules/credit_system_module/credit_system_main.py`

**Method**: `_on_user_created()`

**Priority**: 15

**Process**:
1. Receives `user_created` hook with user data
2. Prepares credit system user data:
   - Maps profile fields
   - Adds app-specific metadata
   - Sets up multi-tenant structure
3. Creates user in credit system (if integrated)
4. Sets up initial wallet/credits

**Hook Registration**:
```python
self.app_manager.register_hook_callback(
    "user_created", 
    self._on_user_created, 
    priority=15, 
    context="credit_system"
)
```

### Hook Flow

```
User Created in Database
    ↓
Hook Triggered: user_created
    ↓
Hook Data Prepared
    ↓
All Registered Listeners Called (by priority)
    ↓
CreditSystemModule._on_user_created()
    ↓
Credit System User Created
    ↓
Initial Wallet/Credits Setup
```

---

## Related Files

### Frontend Files

**UI Components**:
- `flutter_base_05/lib/screens/account_screen/account_screen.dart`
  - Registration form UI
  - Form validation
  - Error/success message display
  - Mode switching (login/register)

**Business Logic**:
- `flutter_base_05/lib/modules/login_module/login_module.dart`
  - `registerUser()` method
  - Client-side validation
  - API request handling
  - Response processing

**HTTP Client**:
- `flutter_base_05/lib/modules/connections_api_module/connections_api_module.dart`
  - `sendPostRequest()` method
  - HTTP request construction
  - Response processing
  - Error handling

**Interceptors**:
- `flutter_base_05/lib/modules/connections_api_module/interceptor.dart`
  - `AuthInterceptor` (not used for registration)
  - Request/response interceptors

### Backend Files

**Module**:
- `python_base_04/core/modules/user_management_module/user_management_main.py`
  - `UserManagementModule` class
  - `create_user()` method
  - Route registration
  - Validation logic
  - Database operations
  - Hook triggering

**Base Module**:
- `python_base_04/core/modules/base_module.py`
  - `BaseModule` class
  - `_register_auth_route_helper()` method
  - Route registration helpers

**Hook Listener**:
- `python_base_04/core/modules/credit_system_module/credit_system_main.py`
  - `CreditSystemModule` class
  - `_on_user_created()` method
  - Hook registration

**Managers**:
- `python_base_04/core/managers/database_manager.py`
  - Database operations
  - User document insertion
  - Automatic encryption/decryption of sensitive fields
  - `_encrypt_sensitive_fields()` method
  - `_decrypt_sensitive_fields()` method

- `python_base_04/core/managers/encryption_manager.py`
  - Encryption/decryption logic
  - Deterministic encryption (for searchable fields)
  - Fernet encryption (for non-searchable fields)
  - Key derivation using PBKDF2

- `python_base_04/core/managers/hooks_manager.py`
  - Hook system
  - Hook triggering
  - Hook callback registration

**Configuration**:
- `python_base_04/utils/config/config.py`
  - App configuration
  - APP_ID, APP_NAME constants

---

## Future Improvements

### 1. Email Verification

**Current State**: No email verification required

**Proposed Enhancement**:
- Send verification email after registration
- Require email verification before account activation
- Add `email_verified` field to user document
- Implement verification token system

### 2. Password Strength Requirements

**Current State**: Only minimum length (8 characters)

**Proposed Enhancement**:
- Require uppercase letters
- Require lowercase letters
- Require numbers
- Require special characters
- Password strength meter in UI

### 3. Username Availability Check

**Current State**: Checked only on form submission

**Proposed Enhancement**:
- Real-time username availability check
- API endpoint: `GET /public/check-username?username={username}`
- Debounced input validation
- Visual feedback (available/unavailable indicator)

### 4. Registration Analytics

**Current State**: No analytics tracking

**Proposed Enhancement**:
- Track registration attempts
- Track successful registrations
- Track failed registrations (with reasons)
- Track registration source (web, mobile, etc.)

### 5. CAPTCHA Integration

**Current State**: No bot protection

**Proposed Enhancement**:
- Add CAPTCHA to registration form
- Verify CAPTCHA on backend
- Prevent automated registration attempts

### 6. Additional Social Registration Providers

**Current State**: Google Sign-In implemented

**Proposed Enhancement**:
- Facebook OAuth registration
- Apple Sign-In registration
- GitHub OAuth registration
- Twitter/X OAuth registration

### 7. Two-Factor Authentication Setup

**Current State**: No 2FA

**Proposed Enhancement**:
- Optional 2FA setup during registration
- SMS verification
- Authenticator app support
- Backup codes generation

### 8. Terms of Service and Privacy Policy

**Current State**: No explicit acceptance

**Proposed Enhancement**:
- Terms of Service checkbox
- Privacy Policy checkbox
- Store acceptance timestamp
- Link to full documents

### 9. Referral System Integration

**Current State**: Referral code generated but not used

**Proposed Enhancement**:
- Allow users to enter referral code during registration
- Track referral source
- Award referral bonuses
- Referral tracking in user document

### 10. Registration Confirmation Email

**Current State**: No confirmation email

**Proposed Enhancement**:
- Send welcome email after registration
- Include account details
- Include next steps
- Include support contact information

---

## Summary

The user registration process is a comprehensive system that handles user account creation from the Flutter frontend through the Python backend to MongoDB storage. Key features include:

- **Multi-layer validation** (frontend and backend)
- **Secure password hashing** (bcrypt)
- **Automatic data encryption** (email, username, phone, and other sensitive fields)
  - Deterministic encryption for searchable fields (email, username)
  - Fernet encryption for non-searchable sensitive fields
- **Duplicate prevention** (email and username uniqueness)
- **Comprehensive user data structure** (profile, preferences, modules, audit)
- **Hook system** for post-registration actions
- **Error handling** with security-conscious messages
- **Rate limiting** protection

The system is designed to be secure, scalable, and extensible, with clear separation of concerns between frontend and backend components. All sensitive data is automatically encrypted at rest by the DatabaseManager before storage.

---

---

## Summary

The user registration process is a comprehensive system that handles user account creation from the Flutter frontend through the Python backend to MongoDB storage. The system now includes three registration methods:

### Regular Registration (Email/Password)
- **Multi-layer validation** (frontend and backend)
- **Secure password hashing** (bcrypt)
- **Automatic data encryption** (email, username, phone encrypted at rest)
- **Duplicate prevention** (email and username uniqueness)
- **Comprehensive user data structure** (profile, preferences, modules, audit)
- **Cleco game module initialization** (subscription_tier: 'promotional', coins: 0)
- **Hook system** for post-registration actions
- **Error handling** with security-conscious messages
- **Rate limiting** protection

### Guest Registration
- **Zero-friction registration** (no user input required)
- **Auto-generated credentials** (username, email, password)
- **Automatic data encryption** (same encryption as regular accounts)
- **Persistent credentials** (survive logout and app restarts)
- **Seamless re-login** (auto-population and one-click login)
- **Full account functionality** (same features as regular accounts)
- **Secure credential generation** (cryptographically secure randomness)
- **Account type distinction** (marked as 'guest' in database)
- **Cleco game module initialization** (subscription_tier: 'promotional', coins: 0)

### Google Sign-In Registration
- **One-click authentication** with Google account
- **Automatic account creation** for new users
- **Account linking** for existing users (by email)
- **Token verification** (ID tokens on mobile, access tokens on web)
- **Platform-specific handling** (Web, Android, iOS)
- **Same JWT token system** as email/password login
- **Auth providers tracking** (auth_providers field in user document)
- **Cleco game module initialization** (subscription_tier: 'promotional', coins: 0)

### Subscription Tier System
- **Default tier**: All new users (guest and regular) start with `subscription_tier: 'promotional'`
- **Promotional tier**: Free play - no coin check required, no coins deducted
- **Free/Regular tier**: Requires coins - coin check and deduction applies
- **Location**: Stored in `modules.cleco_game.subscription_tier`
- **Impact**: Affects coin validation before game creation/join and coin deduction when games start

The system is designed to be secure, scalable, and extensible, with clear separation of concerns between frontend and backend components. Guest registration provides a low-friction entry point while maintaining the same security and functionality standards as regular registration. All sensitive user data (email, username, phone) is automatically encrypted at rest using deterministic encryption for searchable fields and Fernet encryption for other sensitive data.

---

**Last Updated**: 2025-12-12 (Added Google Sign-In authentication feature)

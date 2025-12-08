# User Registration Process Documentation

## Overview

This document describes the complete user registration process in the Recall application. The registration flow spans from the Flutter frontend through the Python backend to database storage and hook processing. This is a comprehensive guide covering all aspects of the registration system.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Frontend Flow](#frontend-flow)
3. [Backend Flow](#backend-flow)
4. [Guest Registration](#guest-registration)
5. [Data Structures](#data-structures)
6. [Validation Rules](#validation-rules)
7. [Security Features](#security-features)
8. [Error Handling](#error-handling)
9. [Hook System](#hook-system)
10. [Related Files](#related-files)
11. [Future Improvements](#future-improvements)

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
Database Insert (MongoDB)
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

**Username Uniqueness**:
```python
existing_username = self.db_manager.find_one("users", {"username": username})
if existing_username:
    return jsonify({
        "success": False,
        "error": "Username already taken"
    }), 409
```

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
Database Insert (MongoDB)
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

## Data Structures

### User Document Structure

**MongoDB Collection**: `users`

**Document Schema**:

```json
{
  "_id": "ObjectId",
  "username": "string",
  "email": "string",
  "password": "string (bcrypt hashed)",
  "status": "string ('active' | 'inactive' | 'suspended')",
  "created_at": "ISO 8601 timestamp",
  "updated_at": "ISO 8601 timestamp",
  "last_login": "ISO 8601 timestamp | null",
  "login_count": "integer",
  
  "profile": {
    "first_name": "string",
    "last_name": "string",
    "phone": "string",
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
    }
  },
  
  "audit": {
    "last_login": "ISO 8601 timestamp | null",
    "login_count": "integer (default: 0)",
    "password_changed_at": "ISO 8601 timestamp",
    "profile_updated_at": "ISO 8601 timestamp"
  }
}
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

### 2. Input Validation

**Multi-Layer Validation**:
- Frontend validation (client-side)
- Backend validation (server-side)
- Database constraints (if applicable)

**Sanitization**:
- Username trimmed
- Email trimmed and lowercased (if needed)
- SQL injection prevention (using parameterized queries)

### 3. Duplicate Prevention

**Uniqueness Checks**:
- Email uniqueness enforced
- Username uniqueness enforced
- Database-level constraints (if configured)

### 4. Error Handling

**Security-Conscious Error Messages**:
- Generic error messages to avoid information leakage
- No disclosure of existing usernames/emails in error messages
- Internal server errors return generic messages

### 5. Rate Limiting

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

### 6. Social Registration

**Current State**: Only email/password registration

**Proposed Enhancement**:
- Google OAuth registration
- Facebook OAuth registration
- Apple Sign-In registration
- Link social accounts to existing accounts

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
- **Duplicate prevention** (email and username uniqueness)
- **Comprehensive user data structure** (profile, preferences, modules, audit)
- **Hook system** for post-registration actions
- **Error handling** with security-conscious messages
- **Rate limiting** protection

The system is designed to be secure, scalable, and extensible, with clear separation of concerns between frontend and backend components.

---

---

## Summary

The user registration process is a comprehensive system that handles user account creation from the Flutter frontend through the Python backend to MongoDB storage. The system now includes both regular and guest registration options:

### Regular Registration
- **Multi-layer validation** (frontend and backend)
- **Secure password hashing** (bcrypt)
- **Duplicate prevention** (email and username uniqueness)
- **Comprehensive user data structure** (profile, preferences, modules, audit)
- **Hook system** for post-registration actions
- **Error handling** with security-conscious messages
- **Rate limiting** protection

### Guest Registration
- **Zero-friction registration** (no user input required)
- **Auto-generated credentials** (username, email, password)
- **Persistent credentials** (survive logout and app restarts)
- **Seamless re-login** (auto-population and one-click login)
- **Full account functionality** (same features as regular accounts)
- **Secure credential generation** (cryptographically secure randomness)
- **Account type distinction** (marked as 'guest' in database)

The system is designed to be secure, scalable, and extensible, with clear separation of concerns between frontend and backend components. Guest registration provides a low-friction entry point while maintaining the same security and functionality standards as regular registration.

---

**Last Updated**: 2025-01-XX (Added Guest Registration feature)

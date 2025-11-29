# Security and Authentication System Documentation

## Overview

The application implements a comprehensive multi-layered security system across three codebases:
- **Python Backend** (`python_base_04`) - Main API server with JWT, API keys, encryption
- **Dart Backend** (`dart_bkend_base_01`) - WebSocket server with token validation
- **Flutter Frontend** (`flutter_base_05`) - Mobile/Web client with secure token storage

### Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Client                            │
│  ┌────────────────────────────────────────────────────┐    │
│  │  AuthManager (Secure Token Storage)                │    │
│  │  - FlutterSecureStorage                            │    │
│  │  - State-aware token refresh                       │    │
│  │  - Auto token injection via Interceptor            │    │
│  └────────────────────────────────────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS/WSS
                       │ JWT Tokens
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Python Backend (Flask)                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   JWT        │  │   API Key    │  │   Rate       │     │
│  │   Manager    │  │   Manager    │  │   Limiter    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Encryption   │  │  Security    │  │   CORS       │     │
│  │  Manager     │  │   Headers    │  │   Config     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│            Dart Backend (WebSocket Server)                   │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Token Validation via Python API                   │    │
│  │  - Session-based authentication                    │    │
│  │  - Room access control                             │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## Authentication Systems

### 1. JWT (JSON Web Token) Authentication

**Purpose**: User authentication for API endpoints and WebSocket connections

**Implementation**: `core/managers/jwt_manager.py`

#### Token Types

The system supports three token types:

```python
class TokenType(Enum):
    ACCESS = "access"      # Short-lived token for API access
    REFRESH = "refresh"    # Long-lived token for refreshing access tokens
    WEBSOCKET = "websocket" # Token for WebSocket connections
```

#### Token Configuration

- **Algorithm**: HS256 (HMAC-SHA256)
- **Access Token TTL**: 3600 seconds (1 hour) - Configurable
- **Refresh Token TTL**: 604800 seconds (7 days) - Configurable
- **Secret Key**: From `Config.JWT_SECRET_KEY` (Vault/File/Env priority)

#### Token Creation

```python
# Create access token
access_token = jwt_manager.create_access_token({
    'user_id': user_id,
    'username': username,
    'email': email
})

# Create refresh token
refresh_token = jwt_manager.create_refresh_token({
    'user_id': user_id
})
```

**Token Features**:
- ✅ **Client Fingerprinting**: IP + User-Agent hash for token binding
- ✅ **Redis Storage**: Tokens stored in Redis for revocation capability
- ✅ **State-aware TTL**: Token refresh delayed during game states
- ✅ **Comprehensive Validation**: Expiration, signature, claims, fingerprint

#### Token Verification

```python
# Verify token
payload = jwt_manager.verify_token(token, TokenType.ACCESS)
if payload:
    user_id = payload.get('user_id')
    # Token is valid
```

**Verification Process**:
1. Decode JWT token
2. Check if token is revoked (Redis lookup)
3. Verify client fingerprint (IP + User-Agent)
4. Validate token type matches expected type
5. Validate claims (exp, iat, custom claims)
6. Return payload if all checks pass

#### Token Revocation

```python
# Revoke a token
jwt_manager.revoke_token(token)
```

- Tokens are stored in Redis with TTL matching expiration
- Revocation removes token from Redis
- Revoked tokens fail verification immediately

#### Client Fingerprinting

**Purpose**: Bind tokens to specific client to prevent token theft

**Implementation**:
```python
fingerprint = hashlib.sha256(f"{ip}-{user_agent}".encode()).hexdigest()
```

**Features**:
- Uses client IP address (handles X-Forwarded-For for proxies)
- Uses User-Agent string
- SHA-256 hash of combined values
- Stored in token payload
- Validated on every token verification

**Exception**: Server-to-server calls (User-Agent contains 'Dart') skip fingerprint validation

#### State-Aware Token Refresh

**Purpose**: Prevent token refresh during critical game states

**Game States** (refresh delayed):
- `active_game`
- `pre_game`
- `post_game`

**Normal States** (refresh allowed):
- `idle`
- `busy`
- `maintenance`

When in game state, token refresh is queued and resumed when game ends.

---

### 2. API Key Authentication

**Purpose**: Service-to-service authentication (e.g., external apps, credit system)

**Implementation**: `core/managers/api_key_manager.py`

#### API Key Generation

**Note**: External apps request API keys from the credit system, they don't generate them locally.

```python
# Request API key from credit system
api_key = api_key_manager.generate_api_key_from_credit_system(
    app_id="external_app_001",
    app_name="External Application",
    permissions=["read", "write"]
)
```

#### API Key Storage

- **Redis**: Primary storage with metadata
- **Secret Files**: Backup storage in `/app/secrets/`
- **TTL**: 30 days (2592000 seconds)

#### API Key Validation

```python
# Validate API key
key_data = api_key_manager.validate_api_key(api_key)
if key_data:
    app_id = key_data.get('app_id')
    permissions = key_data.get('permissions')
    # API key is valid
```

**Validation Process**:
1. Check Redis for API key
2. Verify key is active (not revoked)
3. Update last used timestamp
4. Return key metadata (app_id, permissions, etc.)

#### API Key Revocation

```python
# Revoke API key
api_key_manager.revoke_api_key(api_key)
```

- Sets `is_active = False` in Redis
- Records revocation timestamp
- Invalidates all related cache entries
- Atomic operation for consistency

#### API Key Metadata

Each API key stores:
- `app_id`: Application identifier
- `app_name`: Application name
- `permissions`: List of allowed permissions
- `is_active`: Active status
- `created_at`: Creation timestamp
- `last_used`: Last usage timestamp
- `revoked_at`: Revocation timestamp (if revoked)

---

### 3. Password Security

**Purpose**: Secure password storage and verification

**Implementation**: `bcrypt` hashing

#### Password Hashing

```python
import bcrypt

# Hash password
hashed_password = bcrypt.hashpw(
    password.encode('utf-8'),
    bcrypt.gensalt()
).decode('utf-8')
```

**Features**:
- ✅ **bcrypt**: Industry-standard password hashing
- ✅ **Automatic Salt**: Unique salt per password
- ✅ **Cost Factor**: Configurable (default: 12 rounds)

#### Password Verification

```python
# Verify password
check_result = bcrypt.checkpw(
    password.encode('utf-8'),
    stored_password.encode('utf-8')
)
```

**Security**:
- Constant-time comparison (prevents timing attacks)
- Secure against rainbow table attacks
- Resistant to brute force attacks

---

## Database Security

### Encryption at Rest

**Purpose**: Encrypt sensitive fields before storing in MongoDB

**Implementation**: `core/managers/encryption_manager.py`

#### Encryption Method

- **Algorithm**: Fernet (AES-128 in CBC mode)
- **Key Derivation**: PBKDF2-HMAC-SHA256
- **Iterations**: 100,000
- **Key Length**: 32 bytes

#### Sensitive Fields

Automatically encrypted fields (from `Config.SENSITIVE_FIELDS`):
- `user_id`
- `email`
- `phone`
- `address`
- `credit_balance`
- `transaction_history`

#### Encryption Types

**1. Standard Encryption** (Random IV):
- Used for: Most sensitive fields
- Security: High (random IV per encryption)
- Searchable: No

**2. Deterministic Encryption** (Hash-based):
- Used for: `email`, `username` (searchable fields)
- Method: SHA-256 hash with HMAC
- Security: Medium (allows searching)
- Searchable: Yes

#### Encryption Flow

```
User Data → Identify Sensitive Fields → Encrypt (Standard/Deterministic) → Store in MongoDB
```

**Decryption Flow** (automatic on retrieval):
```
MongoDB → Retrieve Document → Decrypt Sensitive Fields → Return to Application
```

#### Database Connection Security

**MongoDB Authentication**:
- Username/password authentication
- URL-encoded credentials in connection string
- Authentication database: `external_system`
- Connection options:
  - `readConcernLevel: 'majority'`
  - `w: 'majority'` (write concern)
  - `retryWrites: True`
  - `retryReads: True`

**Connection String Format**:
```
mongodb://{encoded_user}:{encoded_password}@{host}:{port}/{database}?authSource={database}
```

---

## WebSocket Security

### Authentication Flow

**Python Backend** (`core/managers/websockets/websocket_manager.py`):

1. **Connection**: Client connects to WebSocket
2. **Token Validation**: Token provided via:
   - Query parameter: `?token=...`
   - Authorization header: `Authorization: Bearer ...`
   - Socket.IO auth data
3. **JWT Verification**: Token validated using JWTManager
4. **Session Creation**: Session data stored in Redis
5. **Room Access**: Room access checked based on user roles

**Dart Backend** (`dart_bkend_base_01/lib/server/websocket_server.dart`):

1. **Connection**: Client connects to WebSocket
2. **Token in Message**: Token sent in first message: `{'token': '...', 'event': 'authenticate'}`
3. **Python API Validation**: Token validated via Python backend API
4. **Session Authentication**: Session marked as authenticated
5. **User Mapping**: Session mapped to user_id

**Flutter Client** (`flutter_base_05/lib/core/managers/websockets/websocket_manager.dart`):

1. **Token Retrieval**: Gets JWT token from AuthManager
2. **Connection**: Connects with token in connection options
3. **Auto-authentication**: Token automatically included in connection

### WebSocket Session Management

**Session Data** (stored in Redis):
- `session_id`: Unique session identifier
- `user_id`: Authenticated user ID
- `username`: User username
- `user_roles`: Set of user roles
- `rooms`: Set of room IDs user is in
- `connected_at`: Connection timestamp
- `last_activity`: Last activity timestamp
- `status`: Session status

**Session TTL**: 3600 seconds (1 hour) - Configurable

### Room Access Control

```python
def check_room_access(self, room_id: str, user_id: str, user_roles: List[str]) -> bool:
    """Check if user has access to room."""
    # Room access logic based on roles and permissions
```

**Access Control**:
- Role-based room access
- Permission checking
- Room creator privileges
- Room size limits

### WebSocket Rate Limiting

**Limits**:
- **Connections**: 100 per window (configurable)
- **Messages**: 1000 per window (configurable)
- **Window**: 60 seconds (configurable)

**Implementation**: Redis-based rate limiting with sliding window

---

## Rate Limiting

**Purpose**: Protect API from abuse and DoS attacks

**Implementation**: `core/managers/rate_limiter_manager.py`

### Rate Limit Types

**1. IP-based Rate Limiting**:
- **Default**: 100 requests per 60 seconds
- **Redis Key**: `rate_limit:ip:{ip_address}`
- **Identifier**: Client IP address

**2. User-based Rate Limiting**:
- **Default**: 1000 requests per 3600 seconds
- **Redis Key**: `rate_limit:user:{user_id}`
- **Identifier**: User ID from JWT token

**3. API Key-based Rate Limiting**:
- **Default**: 10000 requests per 3600 seconds
- **Redis Key**: `rate_limit:api_key:{api_key}`
- **Identifier**: API key from header

### Rate Limit Configuration

```python
config = {
    'ip': {
        'requests': 100,
        'window': 60,
        'enabled': True
    },
    'user': {
        'requests': 1000,
        'window': 3600,
        'enabled': True
    },
    'api_key': {
        'requests': 10000,
        'window': 3600,
        'enabled': True
    }
}
```

### Auto-Ban System

**Purpose**: Automatically ban clients that repeatedly violate rate limits

**Configuration**:
- **Enabled**: `Config.AUTO_BAN_ENABLED` (default: true)
- **Violations Threshold**: 5 violations (configurable)
- **Ban Duration**: 3600 seconds (1 hour) - Configurable
- **Violation Window**: 300 seconds (5 minutes) - Configurable

**Process**:
1. Track violations per identifier
2. When threshold reached, ban identifier
3. Ban stored in Redis with TTL
4. Banned identifiers rejected immediately

### Rate Limit Headers

**Response Headers** (if enabled):
- `X-RateLimit-IP-Limit`: Maximum requests allowed
- `X-RateLimit-IP-Remaining`: Remaining requests
- `X-RateLimit-IP-Reset`: Reset timestamp
- Similar headers for `USER` and `API_KEY` types

---

## Security Headers

**Purpose**: Protect against common web vulnerabilities

**Implementation**: `core/managers/app_manager.py` - `_setup_authentication()`

### Headers Applied

All responses include:

```python
response.headers['X-Content-Type-Options'] = 'nosniff'
response.headers['X-Frame-Options'] = 'DENY'
response.headers['X-XSS-Protection'] = '1; mode=block'
response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
```

**Header Purposes**:
- **X-Content-Type-Options**: Prevents MIME type sniffing
- **X-Frame-Options**: Prevents clickjacking attacks
- **X-XSS-Protection**: Enables XSS filtering
- **Strict-Transport-Security**: Forces HTTPS connections
- **Referrer-Policy**: Controls referrer information
- **Content-Security-Policy**: Restricts resource loading

---

## CORS Configuration

**Purpose**: Control cross-origin resource sharing

**Implementation**: Flask-CORS in `app.py` and `app.debug.py`

### Development Configuration

```python
CORS(app, 
    origins=[
        "http://localhost:3000",
        "http://localhost:3001",
        # ... more localhost ports
    ], 
    supports_credentials=True,
    allow_headers=["*"],
    methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    expose_headers=["*"]
)
```

### Production Considerations

- ✅ **Specific Origins**: List allowed origins explicitly
- ✅ **Credentials**: `supports_credentials=True` for cookies/auth
- ✅ **Methods**: Specify allowed HTTP methods
- ✅ **Headers**: Control allowed request headers

---

## Route-Based Authentication

**Purpose**: Different authentication requirements for different routes

**Implementation**: `core/managers/app_manager.py` - `authenticate_request()`

### Route Prefixes

**1. `/userauth/*`** - JWT Authentication Required:
- Requires: `Authorization: Bearer <token>` header
- Validates: JWT access token
- Sets: `request.user_id`, `request.user_payload`

**2. `/keyauth/*`** - API Key Authentication Required:
- Requires: `X-API-Key: <api_key>` header
- Validates: API key via APIKeyManager
- Sets: `request.app_id`, `request.app_permissions`

**3. `/public/*`** - No Authentication Required:
- Public endpoints
- No authentication check

**4. Default Routes** - Public by Default:
- No authentication required
- Can be overridden per route

---

## Flutter Client Security

### Secure Token Storage

**Implementation**: `flutter_base_05/lib/core/managers/auth_manager.dart`

**Storage Method**: `flutter_secure_storage` package

**Stored Data**:
- `access_token`: JWT access token
- `refresh_token`: JWT refresh token
- `token_stored_at`: Timestamp when tokens were stored
- `access_token_ttl`: Access token time-to-live
- `refresh_token_ttl`: Refresh token time-to-live

**Platform-Specific Storage**:
- **iOS**: Keychain
- **Android**: EncryptedSharedPreferences (AES-256)
- **Web**: Encrypted cookies/localStorage
- **macOS**: Keychain
- **Linux**: libsecret
- **Windows**: DPAPI

### Automatic Token Injection

**Implementation**: `flutter_base_05/lib/modules/connections_api_module/interceptor.dart`

**Process**:
1. HTTP interceptor intercepts all requests
2. Retrieves current valid token from AuthManager
3. Adds `Authorization: Bearer <token>` header
4. Skips token addition for refresh endpoints (prevents loops)

### State-Aware Token Refresh

**Purpose**: Prevent token refresh during critical game states

**Game States** (refresh delayed):
- `active_game`
- `pre_game`
- `post_game`

**Implementation**:
```dart
Future<String?> _performStateAwareTokenRefresh(String? currentToken) async {
  final mainState = stateManager.getMainAppState<String>("main_state");
  
  if (mainState == "active_game" || mainState == "pre_game" || mainState == "post_game") {
    _queueTokenRefreshForNonGameState();
    return currentToken; // Return existing token
  }
  
  // Perform refresh when not in game state
  return await refreshAccessToken(refreshToken);
}
```

### Token Validation

**Process**:
1. Check if token exists in secure storage
2. Check if token is likely expired (based on TTL)
3. If expired, attempt refresh (if not in game state)
4. Return valid token or null

---

## Dart Backend Security

### Token Validation

**Implementation**: `dart_bkend_base_01/lib/services/python_api_client.dart`

**Process**:
1. Receives token from WebSocket client
2. Sends token to Python backend: `POST /api/auth/validate`
3. Python backend validates token
4. Returns validation result with user_id

**API Endpoint**:
```dart
POST http://python-backend/api/auth/validate
Body: {'token': 'jwt_token_here'}
Response: {'valid': true, 'user_id': '...'} or {'valid': false, 'error': '...'}
```

### Session Authentication

**Implementation**: `dart_bkend_base_01/lib/server/websocket_server.dart`

**Session Tracking**:
- `_authenticatedSessions`: Map of session_id → authenticated status
- `_sessionToUser`: Map of session_id → user_id

**Authentication Flow**:
1. Client sends token in message: `{'token': '...', 'event': 'authenticate'}`
2. Server validates token via Python API
3. If valid, mark session as authenticated
4. Map session to user_id
5. Send confirmation: `{'event': 'authenticated', 'user_id': '...'}`

---

## Configuration Management

### Security Configuration Priority

**1. Secret Files** (Kubernetes/Local):
- `/run/secrets/{secret_name}` (Kubernetes)
- `/app/secrets/{secret_name}` (Local development)

**2. HashiCorp Vault** (Production):
- Path: `flask-app/app` or `flask-app/mongodb`
- Keys: `secret_key`, `encryption_key`, `root_password`, etc.

**3. Environment Variables**:
- `JWT_SECRET_KEY`
- `ENCRYPTION_KEY`
- `MONGODB_PASSWORD`
- etc.

**4. Default Values** (Development fallback)

### Critical Security Values

**Sensitive Config Values** (Vault priority):
- `JWT_SECRET_KEY`: JWT signing secret
- `ENCRYPTION_KEY`: Data encryption key
- `ENCRYPTION_SALT`: Encryption salt
- `MONGODB_PASSWORD`: Database password
- `REDIS_PASSWORD`: Redis password
- `STRIPE_SECRET_KEY`: Payment processing key

**Validation**: System validates critical values are available before startup

---

## Security Best Practices

### 1. Token Management

✅ **Do**:
- Store tokens in secure storage (FlutterSecureStorage)
- Use short-lived access tokens (1 hour)
- Use long-lived refresh tokens (7 days)
- Revoke tokens on logout
- Validate tokens on every request

❌ **Don't**:
- Store tokens in plain text
- Use tokens with infinite expiration
- Share tokens between clients
- Log tokens in plain text

### 2. Password Security

✅ **Do**:
- Use bcrypt for password hashing
- Never store plain text passwords
- Use strong password requirements
- Implement password reset flow

❌ **Don't**:
- Store passwords in plain text
- Use weak hashing algorithms (MD5, SHA1)
- Send passwords in URLs
- Log passwords

### 3. API Security

✅ **Do**:
- Use HTTPS in production
- Implement rate limiting
- Validate all inputs
- Use parameterized queries
- Implement CORS properly

❌ **Don't**:
- Expose sensitive endpoints publicly
- Allow unlimited requests
- Trust client-side validation only
- Use string concatenation for queries

### 4. Database Security

✅ **Do**:
- Encrypt sensitive fields
- Use connection authentication
- Implement role-based access
- Use connection pooling
- Monitor database access

❌ **Don't**:
- Store sensitive data unencrypted
- Use default credentials
- Expose database ports publicly
- Allow SQL injection vulnerabilities

### 5. WebSocket Security

✅ **Do**:
- Authenticate all connections
- Validate tokens on connection
- Implement room access control
- Rate limit WebSocket messages
- Monitor connection patterns

❌ **Don't**:
- Allow unauthenticated connections
- Trust client-provided user IDs
- Allow unlimited room joins
- Ignore connection anomalies

---

## Security Monitoring

### Token Revocation Tracking

- Tokens stored in Redis with TTL
- Revocation removes token immediately
- Revoked tokens fail verification

### Rate Limit Monitoring

- Violations tracked in Redis
- Auto-ban system for repeat offenders
- Rate limit headers in responses

### Session Monitoring

- Session data stored in Redis
- TTL-based session expiration
- Stale session cleanup

### Audit Logging

- User actions logged in `user_audit_logs` collection
- Includes: action, user_id, timestamp, IP address
- Module-specific audit trails

---

## Security Endpoints

### Authentication Endpoints

**Login**:
```
POST /public/login
Body: {"email": "...", "password": "..."}
Response: {
    "success": true,
    "data": {
        "user": {...},
        "access_token": "...",
        "refresh_token": "...",
        "expires_in": 3600,
        "refresh_expires_in": 604800
    }
}
```

**Refresh Token**:
```
POST /public/refresh
Body: {"refresh_token": "..."}
Response: {
    "success": true,
    "data": {
        "access_token": "...",
        "refresh_token": "...",
        "expires_in": 3600,
        "refresh_expires_in": 604800
    }
}
```

**Logout**:
```
POST /userauth/logout
Headers: Authorization: Bearer <token>
Response: {"success": true, "message": "Logged out successfully"}
```

**Get Current User**:
```
GET /userauth/current-user
Headers: Authorization: Bearer <token>
Response: {
    "success": true,
    "data": {
        "user": {...},
        "wallet": {...}
    }
}
```

### API Key Endpoints

**Validate API Key**:
```
POST /keyauth/api-keys/validate
Headers: X-API-Key: <api_key>
Body: {"api_key": "..."}
Response: {
    "success": true,
    "valid": true,
    "app_id": "...",
    "permissions": [...]
}
```

**Revoke API Key**:
```
POST /keyauth/api-keys/revoke
Headers: X-API-Key: <api_key>
Body: {"api_key": "..."}
Response: {"success": true, "message": "API key revoked"}
```

---

## Security Flow Diagrams

### Login Flow

```
1. Client → POST /public/login (email, password)
   │
   ├─> Backend validates credentials
   │   │
   │   ├─> Query user from database (email)
   │   │
   │   ├─> Verify password (bcrypt)
   │   │
   │   └─> Check user status (active)
   │
   ├─> Create JWT tokens
   │   │
   │   ├─> Access token (1 hour TTL)
   │   │   └─> Includes: user_id, username, email, fingerprint
   │   │
   │   └─> Refresh token (7 days TTL)
   │       └─> Includes: user_id
   │
   ├─> Store tokens in Redis
   │
   └─> Return tokens to client
       │
       └─> Client stores in FlutterSecureStorage
```

### API Request Flow

```
1. Client makes API request
   │
   ├─> HTTP Interceptor intercepts
   │   │
   │   ├─> Get token from AuthManager
   │   │   │
   │   │   ├─> Check if token expired
   │   │   │   │
   │   │   │   ├─> If expired: Refresh token (if not in game state)
   │   │   │   │
   │   │   │   └─> If not expired: Use existing token
   │   │   │
   │   │   └─> Add Authorization header
   │   │
   ├─> Request sent to backend
   │   │
   ├─> Backend authentication middleware
   │   │
   │   ├─> Check route prefix
   │   │   │
   │   │   ├─> /userauth/* → JWT validation
   │   │   │   │
   │   │   │   ├─> Extract token from header
   │   │   │   │
   │   │   │   ├─> Verify token (JWTManager)
   │   │   │   │   │
   │   │   │   │   ├─> Decode token
   │   │   │   │   │
   │   │   │   │   ├─> Check revocation (Redis)
   │   │   │   │   │
   │   │   │   │   ├─> Verify fingerprint
   │   │   │   │   │
   │   │   │   │   ├─> Validate claims
   │   │   │   │   │
   │   │   │   │   └─> Return payload
   │   │   │   │
   │   │   │   └─> Set request.user_id
   │   │   │
   │   │   ├─> /keyauth/* → API key validation
   │   │   │   │
   │   │   │   ├─> Extract API key from header
   │   │   │   │
   │   │   │   ├─> Validate API key (Redis)
   │   │   │   │
   │   │   │   └─> Set request.app_id
   │   │   │
   │   │   └─> /public/* → No authentication
   │   │
   ├─> Rate limiting check
   │   │
   │   ├─> Check IP rate limit
   │   │
   │   ├─> Check user rate limit (if authenticated)
   │   │
   │   └─> Check API key rate limit (if using API key)
   │
   └─> Process request
```

### WebSocket Authentication Flow

```
1. Client connects to WebSocket
   │
   ├─> Flutter: Get token from AuthManager
   │   │
   │   └─> Include token in connection options
   │
   ├─> Python Backend: Connection event
   │   │
   │   ├─> Extract token from:
   │   │   │
   │   │   ├─> Query parameter (?token=...)
   │   │   │
   │   │   ├─> Authorization header
   │   │   │
   │   │   └─> Socket.IO auth data
   │   │
   │   ├─> Validate token (JWTManager)
   │   │
   │   ├─> Create session in Redis
   │   │   │
   │   │   └─> Store: user_id, username, roles, rooms
   │   │
   │   └─> Join default room (if applicable)
   │
   ├─> Dart Backend: Connection event
   │   │
   │   ├─> Wait for authentication message
   │   │   │
   │   │   └─> Message: {'token': '...', 'event': 'authenticate'}
   │   │
   │   ├─> Validate token via Python API
   │   │   │
   │   │   └─> POST /api/auth/validate
   │   │
   │   ├─> Mark session as authenticated
   │   │
   │   └─> Map session to user_id
   │
   └─> Client receives: {'event': 'authenticated', 'user_id': '...'}
```

---

## Security Considerations

### Token Security

**Threats**:
- Token theft (XSS, man-in-the-middle)
- Token replay attacks
- Token expiration bypass

**Mitigations**:
- ✅ Client fingerprinting (binds token to client)
- ✅ Short token expiration (1 hour)
- ✅ Token revocation capability
- ✅ HTTPS/WSS encryption
- ✅ Secure token storage (FlutterSecureStorage)

### Password Security

**Threats**:
- Password theft
- Brute force attacks
- Rainbow table attacks

**Mitigations**:
- ✅ bcrypt hashing with salt
- ✅ Rate limiting on login endpoints
- ✅ Account lockout after failed attempts
- ✅ Strong password requirements

### Database Security

**Threats**:
- Data breach
- Unauthorized access
- Data leakage

**Mitigations**:
- ✅ Field-level encryption
- ✅ Connection authentication
- ✅ Role-based access control
- ✅ Encrypted sensitive fields
- ✅ Secure credential storage (Vault)

### API Security

**Threats**:
- DoS attacks
- Brute force attacks
- Unauthorized access

**Mitigations**:
- ✅ Multi-level rate limiting (IP, user, API key)
- ✅ Auto-ban system
- ✅ Route-based authentication
- ✅ Security headers
- ✅ CORS configuration

### WebSocket Security

**Threats**:
- Unauthenticated connections
- Message flooding
- Room access abuse

**Mitigations**:
- ✅ Token-based authentication
- ✅ Session management
- ✅ Room access control
- ✅ Rate limiting
- ✅ Message validation

---

## Security Configuration Reference

### JWT Configuration

```python
# Config values
JWT_SECRET_KEY = "..."  # From Vault/File/Env
JWT_ALGORITHM = "HS256"
JWT_ACCESS_TOKEN_EXPIRES = 3600  # 1 hour
JWT_REFRESH_TOKEN_EXPIRES = 604800  # 7 days
```

### Encryption Configuration

```python
ENCRYPTION_KEY = "..."  # From Vault/File/Env
ENCRYPTION_SALT = "..."  # From Vault/File/Env
SENSITIVE_FIELDS = [
    "user_id", "email", "phone", "address",
    "credit_balance", "transaction_history"
]
```

### Rate Limiting Configuration

```python
RATE_LIMIT_ENABLED = True
RATE_LIMIT_IP_REQUESTS = 100
RATE_LIMIT_IP_WINDOW = 60
RATE_LIMIT_USER_REQUESTS = 1000
RATE_LIMIT_USER_WINDOW = 3600
RATE_LIMIT_API_KEY_REQUESTS = 10000
RATE_LIMIT_API_KEY_WINDOW = 3600
```

### Auto-Ban Configuration

```python
AUTO_BAN_ENABLED = True
AUTO_BAN_VIOLATIONS_THRESHOLD = 5
AUTO_BAN_DURATION = 3600  # 1 hour
AUTO_BAN_WINDOW = 300  # 5 minutes
```

### WebSocket Configuration

```python
WS_RATE_LIMIT_CONNECTIONS = 100
WS_RATE_LIMIT_MESSAGES = 1000
WS_RATE_LIMIT_WINDOW = 60
WS_ROOM_SIZE_LIMIT = 6
WS_PING_TIMEOUT = 60
WS_PING_INTERVAL = 25
WS_SESSION_TTL = 3600
```

---

## Security Testing

### Token Validation Testing

```python
# Test valid token
token = jwt_manager.create_access_token({'user_id': '123'})
payload = jwt_manager.verify_token(token, TokenType.ACCESS)
assert payload is not None

# Test revoked token
jwt_manager.revoke_token(token)
payload = jwt_manager.verify_token(token, TokenType.ACCESS)
assert payload is None

# Test expired token
# (Wait for expiration or use expired token)
payload = jwt_manager.verify_token(expired_token, TokenType.ACCESS)
assert payload is None
```

### Rate Limiting Testing

```python
# Test rate limit
for i in range(101):  # Exceed limit
    result = rate_limiter.check_rate_limit(['ip'])
    if i < 100:
        assert result['allowed'] == True
    else:
        assert result['allowed'] == False
```

### Encryption Testing

```python
# Test encryption
encrypted = encryption_manager.encrypt_data("sensitive_data")
decrypted = encryption_manager.decrypt_data(encrypted)
assert decrypted == "sensitive_data"
```

---

## Security Checklist

### Development

- [ ] Use HTTPS in production
- [ ] Store secrets in Vault or secret files
- [ ] Never commit secrets to version control
- [ ] Use strong encryption keys
- [ ] Implement rate limiting
- [ ] Add security headers
- [ ] Configure CORS properly
- [ ] Test authentication flows
- [ ] Test token revocation
- [ ] Test rate limiting

### Production

- [ ] Rotate JWT secret keys regularly
- [ ] Rotate encryption keys regularly
- [ ] Monitor rate limit violations
- [ ] Monitor failed authentication attempts
- [ ] Review audit logs regularly
- [ ] Update dependencies regularly
- [ ] Use strong passwords for database
- [ ] Enable MongoDB authentication
- [ ] Use TLS for database connections
- [ ] Implement backup encryption

---

## Troubleshooting

### Token Validation Failures

**Problem**: Token validation fails unexpectedly

**Solutions**:
1. Check JWT secret key matches between environments
2. Verify token expiration hasn't passed
3. Check if token was revoked
4. Verify client fingerprint matches (if enabled)
5. Check token type matches expected type

### Rate Limit Issues

**Problem**: Legitimate requests being rate limited

**Solutions**:
1. Check rate limit configuration
2. Verify identifier extraction (IP, user_id, API key)
3. Check if client is banned
4. Review rate limit headers in response
5. Adjust rate limit thresholds if needed

### Encryption Issues

**Problem**: Cannot decrypt data

**Solutions**:
1. Verify encryption key matches
2. Check encryption salt matches
3. Verify data was encrypted with same key
4. Check for key rotation issues
5. Handle legacy unencrypted data gracefully

### WebSocket Authentication Issues

**Problem**: WebSocket connections fail authentication

**Solutions**:
1. Verify token is included in connection
2. Check token format (Bearer prefix)
3. Verify token is valid (not expired/revoked)
4. Check Python API is accessible from Dart backend
5. Review WebSocket connection logs

---

## References

### Related Files

**Python Backend**:
- `core/managers/jwt_manager.py` - JWT token management
- `core/managers/api_key_manager.py` - API key management
- `core/managers/encryption_manager.py` - Data encryption
- `core/managers/rate_limiter_manager.py` - Rate limiting
- `core/managers/websockets/websocket_manager.py` - WebSocket security
- `core/managers/app_manager.py` - Authentication middleware
- `core/modules/user_management_module/user_management_main.py` - Login/logout

**Flutter Client**:
- `lib/core/managers/auth_manager.dart` - Token storage and management
- `lib/modules/login_module/login_module.dart` - Login flow
- `lib/modules/connections_api_module/interceptor.dart` - Token injection

**Dart Backend**:
- `lib/server/websocket_server.dart` - WebSocket authentication
- `lib/services/python_api_client.dart` - Token validation

### External Documentation

- [JWT.io](https://jwt.io/) - JWT specification and tools
- [bcrypt](https://github.com/pyca/bcrypt/) - Password hashing
- [Fernet](https://cryptography.io/en/latest/fernet/) - Symmetric encryption
- [Flutter Secure Storage](https://pub.dev/packages/flutter_secure_storage) - Secure storage

---

## Changelog

### Version 1.0.0 (Current)
- JWT authentication with client fingerprinting
- API key management system
- Database field encryption
- Multi-level rate limiting with auto-ban
- WebSocket authentication
- Security headers implementation
- Flutter secure token storage
- State-aware token refresh
- Token revocation system
- Comprehensive audit logging

---

**Last Updated**: 2024
**Maintained By**: Development Team


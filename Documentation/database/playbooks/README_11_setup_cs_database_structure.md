# Multi-Tenant Modular Credit System Database Structure

## Overview

This document describes the MongoDB database structure for a **multi-tenant modular credit system** that supports multiple external applications connecting to the same user data with different permissions and settings.

## Architecture Principles

### 🎯 **Multi-Tenant Design**
- **Single user record** per email address (shared across all apps)
- **App-specific connections** with independent permissions and settings
- **App-specific user data** (usernames, display names, preferences)
- **Shared core data** (email, password, wallet balance, subscription)

### 🔧 **Modular Structure**
- **Embedded module data** in user documents for fast access
- **Module registry** for managing available modules
- **Extensible design** for adding new modules without restructuring

### 🔒 **Security & Audit**
- **App-specific permissions** and rate limiting
- **Complete audit trail** with app identification
- **Encrypted API keys** per app connection

## Database Collections

### 1. `users` Collection (Core User Data)

**Purpose**: Single source of truth for user data, shared across all applications.

**Structure**:
```javascript
{
  "_id": ObjectId,
  "email": "john.doe@example.com",        // Unique identifier
  "username": "johndoe",                  // Core username
  "password": "hashed_password",          // Shared password
  "status": "active",                     // Account status
  "created_at": Date,
  "updated_at": Date,
  
  // Shared profile data
  "profile": {
    "first_name": "John",
    "last_name": "Doe",
    "picture": "https://lh3.googleusercontent.com/...",  // Profile picture URL (from Google Sign-In or other OAuth)
    "phone": "+1234567890",
    "timezone": "America/New_York",
    "language": "en"
  },
  
  // User preferences
  "preferences": {
    "notifications": {
      "email": true,
      "sms": false,
      "push": true
    },
    "privacy": {
      "profile_visible": true,
      "activity_visible": false
    }
  },
  
  // Modular extensions (shared across apps)
  "modules": {
    "wallet": {
      "enabled": true,
      "balance": 1500,
      "currency": "credits",
      "last_updated": Date
    },
    "subscription": {
      "enabled": false,
      "plan": null,
      "expires_at": null
    },
    "referrals": {
      "enabled": true,
      "referral_code": "JOHN123",
      "referrals_count": 0
    }
  },
  
  // Audit information
  "audit": {
    "last_login": Date,
    "login_count": 15,
    "password_changed_at": Date,
    "profile_updated_at": Date
  }
}
```

**Indexes**:
- `email` (unique)
- `username`
- `status`
- `created_at`
- `updated_at`

### 2. `user_apps` Collection (Multi-Tenant App Connections)

**Purpose**: Manages connections between users and external applications with app-specific data and settings.

**Structure**:
```javascript
{
  "_id": ObjectId,
  "user_id": ObjectId,                    // Reference to user
  "app_id": "external_app_001",           // External app identifier
  "app_name": "External Application",     // Human-readable app name
  "app_version": "1.0.0",                // App version
  "app_username": "johndoe_ext",         // App-specific username
  "app_display_name": "John D.",         // App-specific display name
  
  // App-specific profile data
  "app_profile": {
    "nickname": "JD",
    "avatar_url": "https://app.com/avatar.jpg",
    "preferences": {
      "theme": "dark",
      "language": "en",
      "notifications": true
    },
    "custom_fields": {
      "department": "Engineering",
      "employee_id": "EMP001"
    }
  },
  
  "connection_status": "active",          // active, inactive, suspended
  "permissions": ["read", "write", "wallet_access"], // App permissions
  "api_key": "encrypted_api_key_123",    // Encrypted API key
  "sync_frequency": "realtime",          // realtime, batch, manual
  "connected_at": Date,                   // When app connected
  "last_sync": Date,                      // Last data sync
  
  // Sync settings per app
  "sync_settings": {
    "wallet_updates": true,
    "profile_updates": true,
    "transaction_history": true
  },
  
  // Rate limiting per app
  "rate_limits": {
    "requests_per_minute": 100,
    "requests_per_hour": 1000
  }
}
```

**Indexes**:
- `user_id`
- `app_id`
- `user_id + app_id` (unique compound)
- `connection_status`
- `connected_at`
- `last_sync`

### 3. `user_modules` Collection (Module Registry)

**Purpose**: Registry of available modules and their schemas for the modular system.

**Structure**:
```javascript
{
  "_id": ObjectId,
  "module_name": "wallet",               // Module identifier
  "display_name": "Wallet Module",       // Human-readable name
  "description": "Credit balance and transaction management",
  "status": "active",                    // active, inactive, deprecated
  "version": "1.0.0",                   // Module version
  "schema": {                           // Module data schema
    "enabled": "boolean",
    "balance": "number",
    "currency": "string",
    "last_updated": "date"
  },
  "created_at": Date,
  "updated_at": Date
}
```

**Indexes**:
- `module_name` (unique)
- `status`
- `created_at`

### 4. `user_audit_logs` Collection (Audit Trail)

**Purpose**: Complete audit trail for all user changes with app identification.

**Structure**:
```javascript
{
  "_id": ObjectId,
  "user_id": ObjectId,                   // User who made the change
  "app_id": "external_app_001",          // App that made the change
  "action": "profile_updated",           // Action performed
  "module": "core",                      // Module affected
  "changes": {                           // What changed
    "profile.first_name": { "old": "John", "new": "John" },
    "profile.last_name": { "old": "Doe", "new": "Doe" }
  },
  "timestamp": Date,                     // When change occurred
  "ip_address": "192.168.1.100"         // IP address of change
}
```

**Indexes**:
- `user_id`
- `action`
- `timestamp`
- `module`
- `app_id`

## Data Relationships

### User → Apps (One-to-Many)
```
User (john.doe@example.com)
├── App Connection 1: external_app_001
│   ├── app_username: "johndoe_ext"
│   ├── permissions: ["read", "write", "wallet_access"]
│   └── sync_settings: { wallet_updates: true }
└── App Connection 2: mobile_app_002
    ├── app_username: "john_mobile"
    ├── permissions: ["read", "wallet_access"]
    └── sync_settings: { wallet_updates: true }
```

### User → Modules (One-to-Many)
```
User (john.doe@example.com)
├── Wallet Module: { balance: 1500, enabled: true }
├── Subscription Module: { plan: "premium", enabled: true }
└── Referrals Module: { referral_code: "JOHN123", enabled: true }
```

## Use Cases

### 1. New User Registration
```javascript
// User creates account via external app
{
  // Create user record
  "email": "newuser@example.com",
  "username": "newuser",
  "password": "hashed_password",
  "modules": { "wallet": { "enabled": true, "balance": 0 } }
}

// Create app connection
{
  "user_id": user_id,
  "app_id": "external_app_001",
  "app_username": "newuser_ext",
  "permissions": ["read", "write"]
}
```

### 2. Existing User Connects to New App
```javascript
// User already exists, just create app connection
{
  "user_id": existing_user_id,
  "app_id": "mobile_app_002",
  "app_username": "existinguser_mobile",
  "permissions": ["read", "wallet_access"]
}
```

### 3. App-Specific Data Updates
```javascript
// Update app-specific username
db.user_apps.updateOne(
  { "user_id": user_id, "app_id": "external_app_001" },
  { "$set": { "app_username": "new_username" } }
)

// Update shared wallet balance
db.users.updateOne(
  { "_id": user_id },
  { "$set": { "modules.wallet.balance": 2000 } }
)
```

## Security Features

### 🔐 **App-Specific Permissions**
- **Read**: Can read user data
- **Write**: Can update user data
- **wallet_access**: Can access wallet module
- **subscription_access**: Can access subscription module

### 🚦 **Rate Limiting**
- **Per-app limits**: Different limits per app connection
- **Time-based**: Requests per minute/hour
- **Configurable**: Can be adjusted per app

### 📝 **Audit Trail**
- **App identification**: Every change tracked with app_id
- **Change tracking**: Old vs new values recorded
- **IP tracking**: Source IP address logged
- **Timestamp**: Precise timing of changes

## Performance Considerations

### 📊 **Indexing Strategy**
- **Unique constraints**: email, user_id+app_id
- **Query optimization**: Indexes on frequently queried fields
- **Compound indexes**: For complex queries

### 🔄 **Data Access Patterns**
- **User lookups**: By email (unique)
- **App connections**: By user_id + app_id
- **Audit queries**: By user_id, timestamp, app_id
- **Module queries**: By module_name

### 💾 **Storage Optimization**
- **Embedded data**: Module data embedded in user documents
- **Separate collections**: App connections and audit logs separate
- **Efficient queries**: Minimize joins across collections

## Migration & Maintenance

### 🔄 **Adding New Modules**
1. Add module to `user_modules` collection
2. Update user documents with new module data
3. Update app connections with new permissions

### 📈 **Scaling Considerations**
- **Horizontal scaling**: MongoDB sharding by user_id
- **Read replicas**: For audit log queries
- **Connection pooling**: For high-traffic apps

### 🛠 **Backup Strategy**
- **Regular backups**: Daily backups of all collections
- **Point-in-time recovery**: Using MongoDB oplog
- **Cross-region replication**: For disaster recovery

## API Integration Examples

### Get User Data for Specific App
```python
def get_user_for_app(user_id, app_id):
    # Get shared user data
    user = db.users.find_one({"_id": user_id})
    
    # Get app-specific data
    app_connection = db.user_apps.find_one({
        "user_id": user_id,
        "app_id": app_id,
        "connection_status": "active"
    })
    
    # Combine and return
    return {
        "shared": user,
        "app_specific": app_connection
    }
```

### Update User Data with App Context
```python
def update_user_data(app_id, user_id, update_data):
    # Check app permissions
    app_connection = db.user_apps.find_one({
        "user_id": user_id,
        "app_id": app_id,
        "connection_status": "active"
    })
    
    if not app_connection or "write" not in app_connection["permissions"]:
        raise PermissionError("App doesn't have write permissions")
    
    # Update user data
    db.users.update_one(
        {"_id": user_id},
        {"$set": {"updated_at": datetime.utcnow(), **update_data}}
    )
    
    # Log audit trail
    db.user_audit_logs.insert_one({
        "user_id": user_id,
        "app_id": app_id,
        "action": "user_updated",
        "module": "core",
        "changes": update_data,
        "timestamp": datetime.utcnow()
    })
```

## Conclusion

This multi-tenant modular database structure provides:

- ✅ **Scalability**: Handle multiple apps per user
- ✅ **Security**: App-specific permissions and audit trails
- ✅ **Flexibility**: App-specific data and settings
- ✅ **Consistency**: Shared user identity across apps
- ✅ **Performance**: Optimized indexes and queries
- ✅ **Maintainability**: Clear separation of concerns

The structure supports complex multi-tenant scenarios while maintaining data integrity and providing comprehensive audit capabilities. 
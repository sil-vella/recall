# Database Structure Setup - Playbook 10

## Overview

This playbook (`10_setup_database_structure.yml`) sets up a **modular MongoDB database structure** for the Credit System application. It creates a flexible, extensible database design that focuses on basic user details while allowing easy addition of new features without restructuring.

## 🎯 Purpose

- **Initialize** MongoDB database with modular user structure
- **Create** core collections for user management
- **Establish** module registry for feature management
- **Set up** comprehensive audit trail system
- **Provide** dummy data for development and testing

## 📋 Prerequisites

### Required Components
- Docker running locally
- MongoDB container named `credit_system_mongodb`
- Ansible installed on local machine
- Access to MongoDB container via Docker

### Container Setup
```bash
# Ensure MongoDB container is running
docker ps | grep credit_system_mongodb

# If not running, start it (example)
docker run -d --name credit_system_mongodb \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin123 \
  mongo:latest
```

## 🗄️ Database Structure

### Core Collections

#### 1. **users** Collection
The main user document with modular structure:

```javascript
{
  "_id": ObjectId("..."),
  
  // Core Fields (Required)
  "email": "user@example.com",              // Unique identifier
  "username": "username",                   // Display name
  "password": "$2b$12$...",                // Bcrypt hash
  "status": "active",                       // active/inactive/suspended
  "created_at": ISODate("..."),
  "updated_at": ISODate("..."),
  
  // Modular Sections (Extensible)
  "profile": {                              // Personal Information
    "first_name": "John",
    "last_name": "Doe",
    "picture": "https://lh3.googleusercontent.com/...",  // Profile picture URL (from Google Sign-In or other OAuth)
    "phone": "+1234567890",
    "timezone": "America/New_York",
    "language": "en"
  },
  
  "preferences": {                          // User Settings
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
  
  "modules": {                              // Feature Modules
    "wallet": {
      "enabled": true,
      "balance": 1500,
      "currency": "credits",
      "last_updated": ISODate("...")
    },
    "subscription": {
      "enabled": false,
      "plan": null,
      "expires_at": null
    },
    "referrals": {
      "enabled": true,
      "referral_code": "USER123",
      "referrals_count": 0
    }
  },
  
  "audit": {                                // Activity Tracking
    "last_login": ISODate("..."),
    "login_count": 15,
    "password_changed_at": ISODate("..."),
    "profile_updated_at": ISODate("...")
  }
}
```

**Indexes:**
- `email` (unique)
- `username`
- `status`
- `created_at`
- `updated_at`

#### 2. **user_modules** Collection
Registry of available modules and their schemas:

```javascript
{
  "_id": ObjectId("..."),
  "module_name": "wallet",                  // Unique module identifier
  "display_name": "Wallet Module",          // Human-readable name
  "description": "Credit balance management",
  "status": "active",                       // active/inactive/deprecated
  "version": "1.0.0",                      // Module version
  "schema": {                               // Module data structure
    "enabled": "boolean",
    "balance": "number",
    "currency": "string",
    "last_updated": "date"
  },
  "created_at": ISODate("..."),
  "updated_at": ISODate("...")
}
```

**Indexes:**
- `module_name` (unique)
- `status`
- `created_at`

#### 3. **user_audit_logs** Collection
Complete audit trail for all user changes:

```javascript
{
  "_id": ObjectId("..."),
  "user_id": ObjectId("..."),              // References users._id
  "action": "profile_updated",              // Action performed
  "module": "core",                         // Module affected
  "changes": {                              // What changed
    "profile.first_name": {
      "old": "John",
      "new": "Johnny"
    }
  },
  "timestamp": ISODate("..."),
  "ip_address": "192.168.1.100"            // User's IP
}
```

**Indexes:**
- `user_id`
- `action`
- `timestamp`
- `module`

## 🔧 Modular Design Benefits

### 1. **Easy Extension**
- Add new modules without restructuring existing data
- Register modules in `user_modules` collection
- Embed module data in user's `modules` object

### 2. **Performance Optimization**
- All user data in single document (no joins)
- Embedded module data for fast access
- Strategic indexing on frequently queried fields

### 3. **Schema Management**
- Module schemas defined and versioned
- Validation against registered schemas
- Backward compatibility support

### 4. **Complete Audit Trail**
- All changes tracked with before/after values
- Module-specific audit entries
- IP address and timestamp tracking

## 🚀 Usage

### Running the Playbook

```bash
# Navigate to playbooks directory
cd playbooks/00_local/

# Run the playbook
ansible-playbook 10_setup_database_structure.yml

# Run with verbose output
ansible-playbook 10_setup_database_structure.yml -v

# Run with extra variables
ansible-playbook 10_setup_database_structure.yml \
  -e "mongodb_container_name=custom_mongodb"
```

### Verification

After running the playbook, verify the setup:

```bash
# Connect to MongoDB container
docker exec -it credit_system_mongodb mongosh

# Switch to database
use credit_system

# Check collections
show collections

# Verify user data
db.users.find().pretty()

# Check module registry
db.user_modules.find().pretty()

# View audit logs
db.user_audit_logs.find().pretty()
```

## 📊 Sample Data Created

### Users (3 records)
- **John Doe**: Basic user with wallet and referrals enabled
- **Jane Smith**: Premium user with subscription active
- **Bob Wilson**: Active user with referrals and wallet

### Modules (3 registered)
- **Wallet**: Credit balance management
- **Subscription**: Premium subscription handling
- **Referrals**: User referral system

### Audit Logs (3 records)
- Profile updates
- Module enablement
- Wallet balance changes

## 🔄 Adding New Modules

### Step 1: Register Module
```javascript
// Add to user_modules collection
{
  "module_name": "messaging",
  "display_name": "Messaging Module",
  "description": "User messaging system",
  "status": "active",
  "version": "1.0.0",
  "schema": {
    "enabled": "boolean",
    "unread_count": "number",
    "last_message_at": "date"
  }
}
```

### Step 2: Add to User Document
```javascript
// Add to user's modules object
"modules": {
  "messaging": {
    "enabled": true,
    "unread_count": 0,
    "last_message_at": null
  }
}
```

### Step 3: Update Audit Logs
```javascript
// Log the module addition
{
  "user_id": ObjectId("..."),
  "action": "module_enabled",
  "module": "messaging",
  "changes": {
    "modules.messaging.enabled": { "old": false, "new": true }
  }
}
```

## 🛠️ Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `mongodb_container_name` | `credit_system_mongodb` | Docker container name |
| `database_name` | `credit_system` | MongoDB database name |
| `app_user` | `credit_app_user` | Database user |
| `app_password` | `6R3jjsvVhIRP20zMiHdkBzNKx` | Database password |
| `mongodb_host` | `localhost` | MongoDB host |
| `mongodb_port` | `27017` | MongoDB port |
| `mongodb_auth_db` | `credit_system` | Authentication database |

## 🔍 Troubleshooting

### Common Issues

#### 1. **MongoDB Container Not Ready**
```bash
# Check container status
docker ps | grep mongodb

# Check container logs
docker logs credit_system_mongodb

# Restart container if needed
docker restart credit_system_mongodb
```

#### 2. **Authentication Failed**
```bash
# Verify credentials
docker exec credit_system_mongodb mongosh \
  -u credit_app_user \
  -p "6R3jjsvVhIRP20zMiHdkBzNKx" \
  --authenticationDatabase credit_system
```

#### 3. **Database Already Exists**
The playbook will automatically empty the database before setup. If you want to preserve existing data, modify the "Empty database completely" task.

### Debug Mode
```bash
# Run with maximum verbosity
ansible-playbook 10_setup_database_structure.yml -vvv

# Check specific task
ansible-playbook 10_setup_database_structure.yml \
  --start-at-task="Wait for MongoDB container to be ready"
```

## 📈 Performance Considerations

### Indexing Strategy
- **Unique indexes** on email and module_name
- **Compound indexes** for common query patterns
- **TTL indexes** for audit logs (optional)

### Data Size Optimization
- **Embedded documents** for frequently accessed data
- **Separate collections** for large datasets
- **Pagination** for audit log queries

### Scaling Considerations
- **Sharding** by user_id for large datasets
- **Read replicas** for high-traffic applications
- **Connection pooling** for application connections

## 🔐 Security Features

### Authentication
- **Bcrypt password hashing**
- **Database-level authentication**
- **IP-based audit logging**

### Data Protection
- **No plaintext passwords**
- **Encrypted connections** (recommended)
- **Audit trail** for all changes

### Access Control
- **Dedicated database user**
- **Limited permissions** for application
- **Admin user** for maintenance

## 📚 Related Documentation

- [MongoDB Documentation](https://docs.mongodb.com/)
- [Ansible Playbook Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Docker MongoDB Setup](https://hub.docker.com/_/mongo)

## 🤝 Contributing

When modifying this playbook:

1. **Test changes** in development environment
2. **Update documentation** for new features
3. **Maintain backward compatibility**
4. **Add appropriate audit logging**
5. **Update module registry** if adding new modules

## 📝 Changelog

### Version 1.0.0
- Initial modular database structure
- Core user management
- Module registry system
- Comprehensive audit trail
- Sample data for development

---

**Last Updated**: March 2024  
**Maintainer**: Development Team  
**Version**: 1.0.0 
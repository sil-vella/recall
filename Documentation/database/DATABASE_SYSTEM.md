# Database System Documentation

## Overview

The database system in `python_base_04` is built on **MongoDB 7.0** and provides a robust, production-ready database management layer with automatic encryption, queue-based operations, and role-based access control.

### Key Features

- ✅ **MongoDB 7.0** (Bitnami image) running in Docker
- ✅ **Singleton DatabaseManager** with centralized connection management
- ✅ **Queue-based operations** for async processing
- ✅ **Automatic encryption** of sensitive fields at rest
- ✅ **Role-based access control** (read_write, read_only, admin)
- ✅ **Configuration management** with Vault/File/Env priority
- ✅ **Health monitoring** and connection verification
- ✅ **Thread-safe** operations with background worker
- ✅ **Ansible playbook** for automated database structure setup

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│  (Modules, Services, API Endpoints)                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    DatabaseManager                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Queue      │  │  Encryption  │  │   Role       │      │
│  │   System     │  │   Manager    │  │   Control    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              MongoDB Client (PyMongo)                        │
│  - Connection Pooling                                        │
│  - Retry Logic                                               │
│  - Read/Write Concerns                                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         MongoDB 7.0 Container (external_app_mongodb)        │
│  - Database: external_system                                 │
│  - Port: 27018:27017                                         │
│  - Persistent Volume: mongodb_external_data                  │
└─────────────────────────────────────────────────────────────┘
```

### Database Container

**Container Details:**
- **Name**: `external_app_mongodb`
- **Image**: `bitnami/mongodb:7.0`
- **Port Mapping**: `27018:27017` (host:container)
- **Database Name**: `external_system`
- **Network**: `app-network`

**Credentials:**
- **Root User**: `mongodb_admin`
- **Application User**: `external_app_user`
- **Authentication Database**: `external_system`

---

## Connection Management

### DatabaseManager Singleton

The `DatabaseManager` follows a singleton pattern, ensuring a single connection pool is shared across the entire application.

**Location**: `core/managers/database_manager.py`

**Initialization**:
```python
from core.managers.database_manager import DatabaseManager

# Singleton instance - same instance returned every time
db_manager = DatabaseManager(role="read_write")
```

### Connection Setup

The connection is established during `DatabaseManager` initialization:

1. **Configuration Retrieval**: Gets MongoDB credentials from Config system
2. **URI Construction**: Builds MongoDB connection URI with encoded credentials
3. **Client Creation**: Creates PyMongo client with connection options
4. **Verification**: Tests connection and verifies write access (if read_write role)

**Connection Options**:
- `readPreference`: `primary` (read_write) or `primaryPreferred` (read_only)
- `readConcernLevel`: `majority`
- `w`: `majority` (write concern)
- `retryWrites`: `True`
- `retryReads`: `True`

### Connection String Format

```
mongodb://{encoded_user}:{encoded_password}@{host}:{port}/{database}?authSource={database}
```

**Example**:
```
mongodb://external_app_user:6R3jjsvVhIRP20zMiHdkBzNKx@mongodb-external:27017/external_system?authSource=external_system
```

---

## Configuration System

### Configuration Priority

The system uses a multi-tier configuration approach with the following priority:

1. **Secret Files** (Kubernetes/Local)
   - `/run/secrets/{secret_name}` (Kubernetes)
   - `/app/secrets/{secret_name}` (Local development)
   - `./secrets/{secret_name}` (Relative path fallback)

2. **HashiCorp Vault** (Production)
   - Path: `flask-app/mongodb`
   - Keys: `service_name`, `user`, `user_password`, `database_name`, `port`

3. **Environment Variables**
   - `MONGODB_SERVICE_NAME`
   - `MONGODB_USER`
   - `MONGODB_PASSWORD`
   - `MONGODB_DB_NAME`
   - `MONGODB_PORT`

4. **Default Values** (Development fallback)

### MongoDB Configuration Values

| Config Key | Description | Default | Source |
|------------|-------------|---------|--------|
| `MONGODB_SERVICE_NAME` | Service hostname | `mongodb` | Config |
| `MONGODB_USER` | Application username | `external_app_user` | Config |
| `MONGODB_PASSWORD` | Application password | `external_app_password` | Sensitive Config |
| `MONGODB_DB_NAME` | Database name | `external_system` | Config |
| `MONGODB_PORT` | Database port | `27017` | Config |

### Docker Configuration

The MongoDB container is configured in `docker-compose.yml`:

```yaml
mongodb-external:
  image: bitnami/mongodb:7.0
  container_name: external_app_mongodb
  environment:
    - MONGODB_ROOT_USER=mongodb_admin
    - MONGODB_ROOT_PASSWORD=MongoAdmin123!@#SecurePass
    - MONGODB_DATABASE=external_system
    - MONGODB_USERNAME=external_app_user
    - MONGODB_PASSWORD=6R3jjsvVhIRP20zMiHdkBzNKx
  ports:
    - "27018:27017"
  volumes:
    - mongodb_external_data:/bitnami/mongodb
  networks:
    - app-network
```

---

## Database Operations

### Available Operations

All database operations go through the queue system for async processing:

#### Insert

```python
# Insert a single document
document_id = db_manager.insert("users", {
    "email": "user@example.com",
    "name": "John Doe",
    "status": "active"
})
# Returns: ObjectId as string
```

#### Find

```python
# Find multiple documents
users = db_manager.find("users", {"status": "active"})
# Returns: List of documents (ObjectIds converted to strings)

# Find one document
user = db_manager.find_one("users", {"email": "user@example.com"})
# Returns: Single document or None
```

#### Update

```python
# Update documents
modified_count = db_manager.update(
    "users",
    {"email": "user@example.com"},
    {"status": "inactive", "updated_at": datetime.now()}
)
# Returns: Number of modified documents
```

#### Delete

```python
# Delete documents
deleted_count = db_manager.delete("users", {"status": "inactive"})
# Returns: Number of deleted documents
```

### Legacy Methods (Backward Compatibility)

For backward compatibility, these methods are also available:

- `insert_one()` → Alias for `insert()`
- `update_one()` → Alias for `update()`
- `delete_one()` → Alias for `delete()`
- `find_many()` → Alias for `find()`

### ObjectId Handling

The system automatically converts:
- **On Insert**: String IDs are accepted
- **On Query**: String `_id` values are converted to ObjectId for MongoDB queries
- **On Return**: ObjectId values are converted to strings for JSON serialization

---

## Queue System

### Architecture

The queue system provides async processing of database operations:

```
┌──────────────┐
│   Request    │
│  (insert,    │
│   find, etc) │
└──────┬───────┘
       │
       ▼
┌─────────────────┐
│  Request Queue  │
│  (max: 1000)    │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Worker Thread  │
│  (Background)   │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Execute Op     │
│  (MongoDB)      │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Result Store   │
│  (Thread-safe)  │
└─────────────────┘
```

### Queue Configuration

- **Max Queue Size**: 1000 requests
- **Worker Timeout**: 1 second (polling interval)
- **Result Timeout**: 60 seconds (max wait for result)
- **Thread Safety**: Lock-protected result store

### Queue Status

Check queue status:

```python
status = db_manager.get_queue_status()
# Returns:
# {
#     'queue_size': 5,
#     'max_queue_size': 1000,
#     'worker_alive': True,
#     'queue_enabled': True,
#     'pending_results': 2
# }
```

### Queue Control

```python
# Disable queue (operations will fail)
db_manager.disable_queue()

# Enable queue
db_manager.enable_queue()
```

---

## Encryption System

### Automatic Field Encryption

Sensitive fields are automatically encrypted before storage and decrypted when retrieved.

**Sensitive Fields** (from `Config.SENSITIVE_FIELDS`):
- `user_id`
- `email`
- `phone`
- `address`
- `credit_balance`
- `transaction_history`

### Encryption Types

#### 1. Standard Encryption (Random IV)
- Used for: Most sensitive fields
- Method: Fernet (AES-256)
- Security: High (random IV per encryption)
- Searchable: No

#### 2. Deterministic Encryption (Hash-based)
- Used for: `email`, `username` (searchable fields)
- Method: SHA-256 hash with HMAC
- Security: Medium (allows searching)
- Searchable: Yes

### Encryption Manager

**Location**: `core/managers/encryption_manager.py`

**Encryption Key Derivation**:
- Algorithm: PBKDF2-HMAC-SHA256
- Iterations: 100,000
- Key Length: 32 bytes
- Salt: From `Config.ENCRYPTION_SALT`

### Encryption Flow

```
┌──────────────┐
│  User Data   │
└──────┬───────┘
       │
       ▼
┌─────────────────┐
│  Identify       │
│  Sensitive      │
│  Fields         │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Encrypt        │
│  (Standard or   │
│   Deterministic)│
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│  Store in       │
│  MongoDB        │
└─────────────────┘
```

**Decryption Flow** (reverse process on retrieval)

---

## Role-Based Access Control

### Available Roles

1. **read_write** (Default)
   - Full read and write access
   - Can perform: insert, update, delete, find operations
   - Use case: Application operations

2. **read_only** (Planned)
   - Read-only access
   - Can perform: find operations only
   - Use case: Analytics, reporting

3. **admin** (Planned)
   - Administrative access
   - Can perform: All operations + admin commands
   - Use case: Database administration

### Role Usage

```python
# Get read_write manager (default)
db_manager = app_manager.get_db_manager(role="read_write")

# Get read_only manager (for analytics)
analytics_db = app_manager.get_db_manager(role="read_only")

# Get admin manager (for administration)
admin_db = app_manager.get_db_manager(role="admin")
```

**Note**: Currently, all roles use the same singleton instance. Future implementation will support separate connections per role.

---

## Health Monitoring

### Connection Health Check

```python
# Check if database is available
is_healthy = db_manager.check_connection()
# Returns: True if connected, False otherwise
```

### Connection Count

```python
# Get number of active connections
connection_count = db_manager.get_connection_count()
# Returns: Number of active MongoDB connections
```

### Health Endpoint

The application provides a `/health` endpoint that checks database connectivity:

```python
GET /health

Response:
{
    "status": "healthy",
    "modules_initialized": 5,
    "total_modules": 5,
    "state_manager": {...}
}
```

**Health Check Flow**:
1. Verify AppManager initialization
2. Check database connection
3. Check Redis connection
4. Check StateManager health
5. Check module health status

---

## Usage Examples

### Basic Usage

```python
from core.managers.app_manager import AppManager

# Get database manager from AppManager
app_manager = AppManager()
app_manager.initialize(flask_app)

db_manager = app_manager.get_db_manager(role="read_write")

# Insert a user
user_id = db_manager.insert("users", {
    "email": "john@example.com",
    "name": "John Doe",
    "status": "active"
})

# Find user
user = db_manager.find_one("users", {"email": "john@example.com"})

# Update user
db_manager.update(
    "users",
    {"_id": user_id},
    {"status": "inactive"}
)

# Delete user
db_manager.delete("users", {"_id": user_id})
```

### Module Integration

```python
class UserModule(BaseModule):
    def __init__(self, app_manager):
        super().__init__(app_manager)
        self.db_manager = app_manager.get_db_manager()
    
    def create_user(self, user_data):
        """Create a new user."""
        return self.db_manager.insert("users", user_data)
    
    def get_user(self, user_id):
        """Get user by ID."""
        return self.db_manager.find_one("users", {"_id": user_id})
```

### Error Handling

```python
try:
    user = db_manager.find_one("users", {"email": "user@example.com"})
    if not user:
        # Handle user not found
        pass
except Exception as e:
    # Handle database error
    logger.error(f"Database error: {e}")
```

---

## Initialization Flow

### Application Startup

```
1. Database Setup (One-time, two-step process)
   │
   ├─> Step 1: Docker Compose
   │   │
   │   ├─> docker-compose up -d mongodb-external
   │   │   │
   │   │   ├─> Downloads MongoDB image (if needed)
   │   │   │
   │   │   ├─> Creates Docker container
   │   │   │
   │   │   └─> Starts MongoDB service
   │   │
   ├─> Step 2: Ansible Playbook
   │   │
   │   ├─> Run: 10_setup_apps_database_structure.yml
   │   │   │
   │   │   ├─> Waits for container to be ready
   │   │   │
   │   │   ├─> Creates collections (users, user_modules, user_audit_logs)
   │   │   │
   │   │   ├─> Creates indexes for optimal performance
   │   │   │
   │   │   └─> Inserts initial seed data
   │
2. app.py starts
   │
   ├─> Creates AppManager instance
   │
   ├─> AppManager.initialize(flask_app)
   │   │
   │   ├─> Creates DatabaseManager singleton
   │   │   │
   │   │   ├─> Loads configuration (Vault/File/Env)
   │   │   │
   │   │   ├─> Sets up MongoDB connection
   │   │   │   │
   │   │   │   ├─> Constructs connection URI
   │   │   │   │
   │   │   │   ├─> Creates PyMongo client
   │   │   │   │
   │   │   │   └─> Verifies connection
   │   │   │
   │   │   ├─> Initializes EncryptionManager
   │   │   │
   │   │   └─> Starts queue worker thread
   │   │
   │   └─> Registers database manager with AppManager
   │
   └─> Application ready
```

**Note**: 
- **Docker Compose** must be run first to create and start the MongoDB container
- **Ansible playbook** should be run **after** the container is running, and **before** starting the application for the first time
- The Ansible playbook can be re-run when you need to reset/reinitialize the database structure

### Module Access

```python
# In any module or service
db_manager = app_manager.get_db_manager(role="read_write")

# All operations go through queue system
result = db_manager.find("collection", {"field": "value"})
```

---

## Database Initialization

### Complete Setup Process

The database setup involves **two separate steps**:

1. **Docker Compose** - Creates and starts the MongoDB container
2. **Ansible Playbook** - Sets up the database structure inside the running container

### Step 1: MongoDB Container Setup (Docker Compose)

**MongoDB installation and container creation is handled by Docker Compose**, not the Ansible playbook.

**What Docker Compose Does**:
- ✅ Downloads MongoDB image (`bitnami/mongodb:7.0`) if not present
- ✅ Creates the Docker container (`external_app_mongodb`)
- ✅ Configures network, volumes, and environment variables
- ✅ Starts the MongoDB service
- ✅ Sets up authentication users and database

**How to Start MongoDB Container**:
```bash
# Start MongoDB container (and other services)
docker-compose up -d mongodb-external

# Or start all services
docker-compose up -d

# Verify container is running
docker ps | grep external_app_mongodb
```

**Container Configuration** (from `docker-compose.yml`):
```yaml
mongodb-external:
  image: bitnami/mongodb:7.0
  container_name: external_app_mongodb
  environment:
    - MONGODB_ROOT_USER=mongodb_admin
    - MONGODB_ROOT_PASSWORD=MongoAdmin123!@#SecurePass
    - MONGODB_DATABASE=external_system
    - MONGODB_USERNAME=external_app_user
    - MONGODB_PASSWORD=6R3jjsvVhIRP20zMiHdkBzNKx
  ports:
    - "27018:27017"
  volumes:
    - mongodb_external_data:/bitnami/mongodb
  networks:
    - app-network
```

**Important**: The Ansible playbook **requires** the MongoDB container to already be running. It will fail if the container doesn't exist.

### Step 2: Database Structure Setup (Ansible Playbooks)

Once the MongoDB container is running, use one of the **Ansible playbooks** to set up or update the database structure.

#### Available Playbooks

**Playbook 09 - Update Existing Database (Non-Destructive)**:
- **Location**: `playbooks/00_local/09_setup_apps_database_structure(update_existing).yml`
- **Purpose**: Adds missing modules to existing users without erasing data
- **Use Case**: Update existing database with new modules (dutch_game, in_app_purchases)
- **Safety**: ✅ Preserves all existing data

**Playbook 10 - Fresh Database Setup**:
- **Location**: `playbooks/00_local/10_setup_apps_database_structure.yml`
- **Purpose**: Creates a fresh database structure from scratch
- **Use Case**: Initial setup or complete database reset
- **Safety**: ⚠️ Erases all existing data

#### Playbook 09: Update Existing Database

**What Playbook 09 Does**:
1. ✅ Waits for MongoDB container to be ready
2. ✅ Adds missing modules to `user_modules` registry
3. ✅ Updates existing users with missing modules (dutch_game, in_app_purchases)
4. ✅ Preserves all existing user data
5. ✅ Provides detailed update summary

**What Playbook 09 Does NOT Do**:
- ❌ Drop any collections
- ❌ Erase any data
- ❌ Modify existing module data
- ❌ Create new collections

**When to Use Playbook 09**:
- You have existing users and want to add new modules
- You want to update database structure without losing data
- You need to add modules to production/staging databases
- You want to ensure all users have the latest modules

**Running Playbook 09**:
```bash
cd playbooks/00_local
ansible-playbook "09_setup_apps_database_structure(update_existing).yml"
```

**Documentation**: See `playbooks/00_local/README_09_setup_apps_database_structure(update_existing).yml.md` for detailed information.

#### Playbook 10: Fresh Database Setup

**What Playbook 10 Does**:
1. ✅ Waits for MongoDB container to be ready
2. ✅ Empties existing database completely
3. ✅ Creates core collections with proper structure
4. ✅ Creates all required indexes for optimal performance
5. ✅ Inserts dummy data for development and testing

**What Playbook 10 Does NOT Do**:
- ❌ Download or install MongoDB
- ❌ Create Docker container
- ❌ Start Docker container
- ❌ Configure Docker networks/volumes

**When to Use Playbook 10**:
- Initial database setup
- Complete database reset
- Development/testing environment setup
- When you want a clean slate

**Collections Created by Playbook 10**:
- `users` - Core user data with modular structure (includes all 5 modules)
- `user_modules` - Registry of available modules and their schemas
- `user_audit_logs` - Complete audit trail system

**Indexes Created**:
- **users**: `email` (unique), `username`, `status`, `created_at`, `updated_at`
- **user_modules**: `module_name` (unique), `status`, `created_at`
- **user_audit_logs**: `user_id`, `action`, `timestamp`, `module`

### Running the Complete Setup

**Step 1: Start MongoDB Container** (if not already running):
```bash
# Start MongoDB container
docker-compose up -d mongodb-external

# Wait a few seconds for MongoDB to initialize
sleep 5

# Verify container is running
docker ps | grep external_app_mongodb
```

**Step 2: Run Ansible Playbook**:

**For Fresh Setup (Playbook 10)**:
```bash
# From the playbooks/00_local directory
cd playbooks/00_local
ansible-playbook 10_setup_apps_database_structure.yml

# With verbose output
ansible-playbook 10_setup_apps_database_structure.yml -v

# With extra verbose output for debugging
ansible-playbook 10_setup_apps_database_structure.yml -vvv
```

**For Updating Existing Database (Playbook 09)**:
```bash
# From the playbooks/00_local directory
cd playbooks/00_local
ansible-playbook "09_setup_apps_database_structure(update_existing).yml"

# With verbose output
ansible-playbook "09_setup_apps_database_structure(update_existing).yml" -v
```

**Prerequisites**:
- ✅ Docker installed and running locally
- ✅ MongoDB container `external_app_mongodb` must be **already running** (created via docker-compose)
- ✅ Ansible installed on local machine
- ✅ Access to MongoDB container via Docker

**Note**: If you get an error that the container doesn't exist, run `docker-compose up -d mongodb-external` first.

**Configuration**:
The playbook is pre-configured for the `external_app_mongodb` container:
- Container: `external_app_mongodb`
- Database: `external_system`
- User: `external_app_user`
- Port: `27017`

**Documentation**: 
- Playbook 09: `playbooks/00_local/README_09_setup_apps_database_structure(update_existing).yml.md`
- Playbook 10: `playbooks/00_local/README_10_setup_apps_database_structure.md`

### Setup Order Summary

**Fresh Database Setup Flow (Playbook 10)**:
```
1. docker-compose up -d mongodb-external
   └─> Downloads MongoDB image (if needed)
   └─> Creates and starts container
   └─> MongoDB service running

2. ansible-playbook 10_setup_apps_database_structure.yml
   └─> Waits for container to be ready
   └─> Empties existing database
   └─> Creates collections
   └─> Creates indexes
   └─> Inserts seed data

3. Application can now connect and use database
```

**Update Existing Database Flow (Playbook 09)**:
```
1. Ensure MongoDB container is running
   └─> docker ps | grep external_app_mongodb

2. ansible-playbook 09_setup_apps_database_structure(update_existing).yml
   └─> Waits for container to be ready
   └─> Adds missing modules to registry
   └─> Updates existing users with missing modules
   └─> Preserves all existing data

3. Database updated without data loss
```

### Automatic Collection Creation

While the Ansible playbook sets up the initial structure, MongoDB also automatically creates collections when you first write to them. However, **indexes are NOT created automatically** - they must be set up via the playbook or manually.

**Important**: 
- For **first-time setup**, always run both Docker Compose AND Playbook 10
- For **updating existing databases**, use Playbook 09 to preserve data
- For **production deployments**, use Playbook 09 to add new modules without downtime
- Playbook 10 can be re-run safely (it will empty and recreate the database structure)
- Playbook 09 is idempotent and can be run multiple times safely

---

## Database Structure

### Collections

The database uses a **modular structure** that supports:

- **Modular user structure**: Flexible user documents with embedded modules
- **App-specific connections**: Multi-tenant app connections
- **Audit logging**: Complete audit trail for all changes
- **Module registry**: Registry of available modules and schemas

**Core Collections** (Created by Ansible Playbook):
- `users` - User accounts with embedded module data
- `user_modules` - Registry of available modules and their schemas
- `user_audit_logs` - Complete audit trail for all user changes

**User Modules** (Embedded in users collection):
The `users` collection includes embedded module data for:
1. **wallet** - Credit balance and transaction management
2. **subscription** - Premium subscription management
3. **referrals** - User referral system
4. **in_app_purchases** - In-app purchase and subscription management
5. **dutch_game** - Dutch card game statistics and progression

Each module contains module-specific fields and settings. See the playbook documentation for complete module schemas.

**Computer Players**:
The `users` collection includes a special field `is_comp_player` to identify computer-controlled players:
- `is_comp_player: false` - Human players (default for all users)
- `is_comp_player: true` - Computer players used in multiplayer games

**Predefined Computer Players** (created by database setup playbook):
- `alex.morris87` (alex.morris87@cp.com)
- `lena_kay` (lena_kay@cp.com)
- `jordanrivers` (jordanrivers@cp.com)
- `samuel.b` (samuel.b@cp.com)
- `nina_holt` (nina_holt@cp.com)

Each computer player has:
- Initial coins: 1000 in `modules.dutch_game.coins`
- Status: `active`
- Password: `comp_player_pass` (bcrypt hashed)
- Full user structure with all modules enabled

**Additional Collections** (Created by Application):
- `notifications` - User notifications
- `wallets` - Wallet data (if separate from user documents)
- `user_purchases` - Purchase history
- `states` - Application state management
- `sync_history` - Data synchronization history
- `store_products` - Product catalog

### Indexes

**Indexes are created automatically by the Ansible playbook**. The following indexes are set up:

**users Collection**:
```javascript
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "username": 1 });
db.users.createIndex({ "status": 1 });
db.users.createIndex({ "created_at": 1 });
db.users.createIndex({ "updated_at": 1 });
db.users.createIndex({ "is_comp_player": 1 });  // For computer player queries
```

**user_modules Collection**:
```javascript
db.user_modules.createIndex({ "module_name": 1 }, { unique: true });
db.user_modules.createIndex({ "status": 1 });
db.user_modules.createIndex({ "created_at": 1 });
```

**user_audit_logs Collection**:
```javascript
db.user_audit_logs.createIndex({ "user_id": 1 });
db.user_audit_logs.createIndex({ "action": 1 });
db.user_audit_logs.createIndex({ "timestamp": 1 });
db.user_audit_logs.createIndex({ "module": 1 });
```

**Note**: If you need to add new indexes, either:
1. Modify the Ansible playbook and re-run it
2. Create them manually via MongoDB shell
3. Use a migration script

---

## Troubleshooting

### Database Structure Issues

**Problem**: Collections or indexes are missing

**Solutions**:
1. **Ensure MongoDB container is running**:
   ```bash
   docker ps | grep external_app_mongodb
   # If not running, start it:
   docker-compose up -d mongodb-external
   ```

2. **Run the appropriate Ansible playbook**:
   ```bash
   cd playbooks/00_local
   
   # For fresh setup (erases data)
   ansible-playbook 10_setup_apps_database_structure.yml
   
   # For updating existing database (preserves data)
   ansible-playbook "09_setup_apps_database_structure(update_existing).yml"
   ```

3. **Verify collections exist**:
   ```bash
   docker exec external_app_mongodb mongosh -u external_app_user -p "6R3jjsvVhIRP20zMiHdkBzNKx" --authenticationDatabase external_system --eval "db = db.getSiblingDB('external_system'); db.getCollectionNames()"
   ```

4. **Check indexes**:
   ```bash
   docker exec external_app_mongodb mongosh -u external_app_user -p "6R3jjsvVhIRP20zMiHdkBzNKx" --authenticationDatabase external_system --eval "db = db.getSiblingDB('external_system'); db.users.getIndexes()"
   ```

5. **Re-run playbook if needed** (it will empty and recreate the database structure)

### Container Not Found Issues

**Problem**: Ansible playbook fails with "container not found" error

**Solutions**:
1. **Check if container exists**:
   ```bash
   docker ps -a | grep external_app_mongodb
   ```

2. **Create and start container using Docker Compose**:
   ```bash
   docker-compose up -d mongodb-external
   ```

3. **Wait for MongoDB to initialize** (may take 10-30 seconds):
   ```bash
   docker logs external_app_mongodb
   # Look for "MongoDB init process complete" or similar message
   ```

4. **Then run the appropriate Ansible playbook**:
   ```bash
   cd playbooks/00_local
   
   # For fresh setup
   ansible-playbook 10_setup_apps_database_structure.yml
   
   # For updating existing database
   ansible-playbook "09_setup_apps_database_structure(update_existing).yml"
   ```

### Connection Issues

**Problem**: Database connection fails

**Solutions**:
1. Check MongoDB container is running:
   ```bash
   docker ps | grep external_app_mongodb
   ```

2. Verify network connectivity:
   ```bash
   docker exec external_app_flask ping mongodb-external
   ```

3. Check credentials in configuration:
   ```python
   from utils.config.config import Config
   print(f"User: {Config.MONGODB_USER}")
   print(f"Host: {Config.MONGODB_SERVICE_NAME}")
   print(f"Port: {Config.MONGODB_PORT}")
   ```

4. Test connection manually:
   ```python
   from pymongo import MongoClient
   client = MongoClient("mongodb://external_app_user:password@mongodb-external:27017/external_system")
   client.server_info()
   ```

### Queue Issues

**Problem**: Queue is full or operations timeout

**Solutions**:
1. Check queue status:
   ```python
   status = db_manager.get_queue_status()
   print(status)
   ```

2. Increase queue size (if needed):
   ```python
   db_manager.max_queue_size = 2000
   ```

3. Check worker thread:
   ```python
   status = db_manager.get_queue_status()
   if not status['worker_alive']:
       # Worker thread died, restart application
   ```

### Encryption Issues

**Problem**: Cannot decrypt data

**Solutions**:
1. Verify encryption key:
   ```python
   from utils.config.config import Config
   print(f"Encryption key set: {bool(Config.ENCRYPTION_KEY)}")
   ```

2. Check encryption key consistency:
   - Ensure same key is used for encryption and decryption
   - Verify key hasn't changed between deployments

3. Handle legacy unencrypted data:
   - System gracefully handles unencrypted data
   - Returns original value if decryption fails

### Performance Issues

**Problem**: Slow database operations

**Solutions**:
1. Check connection pool:
   ```python
   connection_count = db_manager.get_connection_count()
   ```

2. Monitor queue size:
   ```python
   status = db_manager.get_queue_status()
   if status['queue_size'] > 100:
       # Queue is backing up
   ```

3. Add indexes for frequently queried fields
4. Consider read-only replica for analytics queries

---

## Best Practices

### 1. Always Use DatabaseManager

❌ **Don't** create direct MongoDB connections:
```python
# BAD
from pymongo import MongoClient
client = MongoClient("mongodb://...")
```

✅ **Do** use DatabaseManager:
```python
# GOOD
db_manager = app_manager.get_db_manager()
```

### 2. Handle Errors Gracefully

```python
try:
    result = db_manager.find_one("users", {"email": email})
except Exception as e:
    logger.error(f"Database error: {e}")
    # Handle error appropriately
```

### 3. Use Appropriate Roles

```python
# For read operations in analytics
analytics_db = app_manager.get_db_manager(role="read_only")

# For write operations
db_manager = app_manager.get_db_manager(role="read_write")
```

### 4. Monitor Queue Status

```python
# In health checks or monitoring
status = db_manager.get_queue_status()
if status['queue_size'] > status['max_queue_size'] * 0.8:
    # Alert: Queue is getting full
```

### 5. Complete Setup Process

✅ **Do** follow the complete setup process:
```bash
# Step 1: Start MongoDB container
docker-compose up -d mongodb-external

# Step 2: Run appropriate Ansible playbook
cd playbooks/00_local

# For fresh setup (erases data)
ansible-playbook 10_setup_apps_database_structure.yml

# OR for updating existing database (preserves data)
ansible-playbook "09_setup_apps_database_structure(update_existing).yml"
```

❌ **Don't** try to run the Ansible playbook before starting the MongoDB container - it will fail.

❌ **Don't** manually create collections and indexes if the playbook exists - use the playbook for consistency.

✅ **Do** use Playbook 09 when you have existing data you want to preserve.

❌ **Don't** use Playbook 10 on production databases with important data - it will erase everything.

### 6. Index Frequently Queried Fields

The Ansible playbook already creates essential indexes. If you need additional indexes:

```javascript
// Create indexes for common queries
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "status": 1, "created_at": -1 });
```

**Note**: Consider adding new indexes to the Ansible playbook for future deployments.

---

## Security Considerations

### 1. Credential Management

- ✅ Use Vault for production credentials
- ✅ Never commit credentials to version control
- ✅ Use secret files for Kubernetes deployments
- ✅ Rotate credentials regularly

### 2. Encryption

- ✅ Sensitive fields are automatically encrypted
- ✅ Use deterministic encryption only for searchable fields
- ✅ Keep encryption keys secure and rotated

### 3. Access Control

- ✅ Use role-based access control
- ✅ Limit write access to necessary operations
- ✅ Use read-only connections for analytics

### 4. Network Security

- ✅ Use Docker networks for container communication
- ✅ Don't expose MongoDB port publicly
- ✅ Use TLS/SSL in production (when configured)

---

## Future Enhancements

### Planned Features

1. **Read-Only Replicas**: Separate connections for read-only operations
2. **Connection Pooling**: Configurable pool sizes per role
3. **Query Caching**: Redis-based query result caching
4. **Migration System**: Database schema migration tools
5. **Backup Integration**: Automated backup scheduling
6. **Performance Monitoring**: Query performance tracking
7. **TLS/SSL Support**: Encrypted connections to MongoDB

---

## References

### Related Files

- **DatabaseManager**: `core/managers/database_manager.py`
- **EncryptionManager**: `core/managers/encryption_manager.py`
- **Config System**: `utils/config/config.py`
- **AppManager**: `core/managers/app_manager.py`
- **Docker Compose**: `docker-compose.yml`
- **Ansible Playbook 09** (Update Existing): `playbooks/00_local/09_setup_apps_database_structure(update_existing).yml`
- **Ansible Playbook 10** (Fresh Setup): `playbooks/00_local/10_setup_apps_database_structure.yml`
- **Playbook 09 README**: `playbooks/00_local/README_09_setup_apps_database_structure(update_existing).yml.md`
- **Playbook 10 README**: `playbooks/00_local/README_10_setup_apps_database_structure.md`

### External Documentation

- [MongoDB Documentation](https://docs.mongodb.com/)
- [PyMongo Documentation](https://pymongo.readthedocs.io/)
- [Fernet Encryption](https://cryptography.io/en/latest/fernet/)

---

## Changelog

### Version 1.2.0 (December 2025)
- Added `is_comp_player` field to users collection
  - Boolean field to identify computer-controlled players
  - Index created for efficient queries
  - Default value: `false` for all existing users
- Added computer player creation to database setup playbooks
  - Creates 5 predefined computer players with realistic usernames
  - Each with 1000 initial coins and full module structure
  - Usernames: alex.morris87, lena_kay, jordanrivers, samuel.b, nina_holt
- Updated game end logic to handle comp player statistics
  - Comp players from database have their statistics updated
  - Simulated CPU players (fallback) are still skipped

### Version 1.1.0 (December 2025)
- Added Playbook 09 for non-destructive database updates
- Added `dutch_game` module to user schema
  - Tracks game statistics: wins, losses, total_matches, points, level, rank, win_rate
- Added `in_app_purchases` module to user schema
  - Manages in-app purchases and subscriptions
- Updated all existing users with new modules via Playbook 09
- Enhanced module registry with 5 total modules (wallet, subscription, referrals, in_app_purchases, dutch_game)
- Improved documentation for database update workflows

### Version 1.0.0 (2024)
- Initial database system implementation
- Singleton DatabaseManager with queue system
- Automatic field encryption
- Role-based access control (read_write)
- Health monitoring
- Docker container setup
- Ansible playbook for automated database structure setup
- Modular database structure with embedded module data
- Comprehensive audit trail system

---

**Last Updated**: December 2025
**Maintained By**: Development Team


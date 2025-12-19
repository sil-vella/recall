# Add Missing Modules to Existing Database - Playbook 09

## Overview

This playbook (`09_add_missing_modules.yml`) **safely adds missing modules** to existing users in the MongoDB database **without erasing any data**. It's designed to update your database structure while preserving all existing user data.

## 🎯 Purpose

- **Add missing modules** to existing user documents
- **Register new modules** in the user_modules collection
- **Preserve all existing data** - no collections are dropped
- **Update users incrementally** - only adds what's missing

## ⚠️ Key Difference from Playbook 10

| Feature | Playbook 09 (This) | Playbook 10 |
|---------|-------------------|-------------|
| **Data Safety** | ✅ Preserves all data | ❌ Erases all data |
| **Use Case** | Update existing DB | Fresh setup |
| **Collections** | Updates existing | Creates new |
| **Users** | Updates existing | Creates dummy users |

## 📋 Prerequisites

### Required Components
- Docker running locally
- MongoDB container named `external_app_mongodb` **must be running**
- Ansible installed on local machine
- Access to MongoDB container via Docker

### Container Setup
```bash
# Ensure MongoDB container is running
docker ps | grep external_app_mongodb

# If not running, start it
docker-compose up -d mongodb-external
```

## 🗄️ What This Playbook Does

### Step 1: Update Module Registry
- Checks if `in_app_purchases` module exists in `user_modules` collection
- Checks if `cleco_game` module exists in `user_modules` collection
- Adds missing modules to the registry with proper schema definitions

### Step 2: Update Existing Users
- Finds all users in the database
- For each user, checks if they have:
  - `modules.in_app_purchases` module
  - `modules.cleco_game` module
- Adds missing modules with default values:
  - **in_app_purchases**: enabled, empty purchases, no subscription
  - **cleco_game**: enabled, 0 wins/losses, beginner rank, level 1

### Step 3: Add is_comp_player Field
- Creates index on `is_comp_player` field for efficient queries
- Adds `is_comp_player: false` to all existing users that don't have it
- Verifies all users have the field

### Step 4: Create Computer Players
- Checks if computer players already exist (target: 5 players)
- Creates 5 computer players with predefined usernames:
  - `alex.morris87` (alex.morris87@cp.com)
  - `lena_kay` (lena_kay@cp.com)
  - `jordanrivers` (jordanrivers@cp.com)
  - `samuel.b` (samuel.b@cp.com)
  - `nina_holt` (nina_holt@cp.com)
- Each computer player has:
  - Initial coins: 1000 in `modules.cleco_game.coins`
  - Status: `active`
  - Password: `comp_player_pass` (bcrypt hashed)
  - `is_comp_player: true`
  - Full user structure with all modules enabled

### Step 5: Verification
- Counts users with each module
- Lists all registered modules
- Counts computer players vs human players
- Lists all computer players with their details
- Provides summary statistics

## 🚀 Usage

### Running the Playbook

```bash
# From the playbooks/00_local directory
cd playbooks/00_local

# Run the playbook
ansible-playbook 09_add_missing_modules.yml

# With verbose output
ansible-playbook 09_add_missing_modules.yml -v

# With extra verbose output for debugging
ansible-playbook 09_add_missing_modules.yml -vvv
```

### Expected Output

```
🔧 Adding Missing Modules to Existing Database...
=============================================

📋 Step 1: Updating user_modules registry...
  ➕ Adding in_app_purchases module to registry...
  ✅ in_app_purchases module added to registry
  ➕ Adding cleco_game module to registry...
  ✅ cleco_game module added to registry

👥 Step 2: Updating existing users with missing modules...
  Found 3 users to check
  ➕ Adding in_app_purchases to user: johndoe (john.doe@example.com)
  ➕ Adding cleco_game to user: johndoe (john.doe@example.com)
  ...

  ✅ Users updated: 3
  ✓ Users already up-to-date: 0

🤖 Step 3: Adding is_comp_player field to users...
  ✅ Created index on is_comp_player field
  ✅ Added is_comp_player: false to 3 users
  📊 Users with is_comp_player field: 3 / 3

🤖 Step 4: Creating computer players...
  Found 0 existing computer player(s)
  ➕ Creating 5 new computer player(s)...
  ➕ Prepared computer player: alex.morris87 (alex.morris87@cp.com)
  ➕ Prepared computer player: lena_kay (lena_kay@cp.com)
  ➕ Prepared computer player: jordanrivers (jordanrivers@cp.com)
  ➕ Prepared computer player: samuel.b (samuel.b@cp.com)
  ➕ Prepared computer player: nina_holt (nina_holt@cp.com)
  ✅ Created 5 computer player(s)
  📊 Total computer players in database: 5

🎉 MODULE UPDATE COMPLETE!
```

## 📊 What Gets Added

### Computer Player Field

**is_comp_player** field:
- Added to all users (default: `false`)
- Index created for efficient queries
- Used to identify computer-controlled players for multiplayer games

### Computer Players Created

Five predefined computer players are created:
- `alex.morris87` (alex.morris87@cp.com) - 1000 coins
- `lena_kay` (lena_kay@cp.com) - 1000 coins
- `jordanrivers` (jordanrivers@cp.com) - 1000 coins
- `samuel.b` (samuel.b@cp.com) - 1000 coins
- `nina_holt` (nina_holt@cp.com) - 1000 coins

Each computer player has:
- Full user structure with all modules
- Initial coins: 1000 in `modules.cleco_game.coins`
- Status: `active`
- `is_comp_player: true`
- Password: `comp_player_pass` (bcrypt hashed)

## 📊 Modules Added

### 1. in_app_purchases Module
```javascript
{
  "enabled": true,
  "active_purchases": [],
  "subscription_status": "none",
  "last_purchase_date": null,
  "total_spent": 0,
  "currency": "USD",
  "last_updated": ISODate
}
```

### 2. cleco_game Module
```javascript
{
  "enabled": true,
  "wins": 0,
  "losses": 0,
  "total_matches": 0,
  "points": 0,
  "level": 1,
  "rank": "beginner",
  "win_rate": 0.0,
  "last_match_date": null,
  "last_updated": ISODate
}
```

## 🔒 Safety Features

### Data Preservation
- ✅ **No collections are dropped**
- ✅ **No existing data is modified** (only additions)
- ✅ **Existing module data is preserved**
- ✅ **User profiles remain unchanged**

### Idempotent Operation
- ✅ Can be run multiple times safely
- ✅ Only adds missing modules
- ✅ Skips users that already have all modules
- ✅ Won't duplicate module registry entries

## 🔧 Configuration

The playbook is pre-configured for the `external_app_mongodb` container:
- **Container**: `external_app_mongodb`
- **Database**: `external_system`
- **User**: `external_app_user`
- **Port**: `27017` (internal, via docker exec)

## 📝 When to Use This Playbook

### ✅ Use This Playbook When:
- You have existing users and want to add new modules
- You want to update database structure without losing data
- You need to add modules to production/staging databases
- You want to ensure all users have the latest modules

### ❌ Don't Use This Playbook When:
- You want a completely fresh database (use Playbook 10 instead)
- You want to reset all data (use Playbook 10 instead)
- You're setting up for the first time (use Playbook 10 instead)

## 🔄 Workflow Comparison

### Fresh Setup (Playbook 10)
```
1. Empty database completely
2. Create collections
3. Create indexes
4. Insert dummy data
```

### Update Existing (Playbook 09 - This)
```
1. Check module registry
2. Add missing modules to registry
3. Find all users
4. Add missing modules to each user
5. Verify updates
```

## 🐛 Troubleshooting

### Container Not Running
```bash
# Check if container exists
docker ps -a | grep external_app_mongodb

# Start container if stopped
docker-compose up -d mongodb-external
```

### Authentication Errors
- Verify credentials in playbook match your MongoDB setup
- Check that the user has write permissions

### No Users Found
- This is normal if the database is empty
- The playbook will still register modules in the registry
- Consider using Playbook 10 for initial setup

## 📚 Related Documentation

- **Playbook 10**: `README_10_setup_apps_database_structure.md` - Fresh database setup
- **Database System**: `Documentation/database/DATABASE_SYSTEM.md` - Overall database architecture

## ✅ Summary

This playbook provides a **safe, non-destructive way** to add missing modules to your existing database. It's perfect for updating production or staging environments without losing any data.

**Key Benefits:**
- 🛡️ Data-safe operation
- 🔄 Idempotent (can run multiple times)
- 📊 Detailed reporting
- ✅ Preserves all existing data

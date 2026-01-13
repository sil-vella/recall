#!/usr/bin/env python3
"""
Add computer players to MongoDB database from JSON file (Local Docker).

This script reads player data from templates/comp_players.json and creates
computer player accounts in the local MongoDB Docker container with proper module structure.

Usage:
    python3 11_add_players.py [--json-file templates/comp_players.json]
"""

import json
import sys
import os
import argparse
import subprocess
from datetime import datetime
from typing import Dict, Any, List

# Bcrypt hash for password "comp_player_pass"
COMP_PLAYER_PASSWORD = "$2b$12$PHGvsjOG3/fjNuEZQP1Szu5/igAj8pppp8XoAFeVyzDbj2EBh3o82"

# MongoDB connection details (local Docker container)
MONGODB_CONTAINER = "dutch_external_app_mongodb"
MONGODB_DATABASE = "external_system"
MONGODB_USER = "external_app_user"
MONGODB_PASSWORD = "6R3jjsvVhIRP20zMiHdkBzNKx"
MONGODB_AUTH_DB = "external_system"


def extract_name_from_username(username: str) -> tuple[str, str]:
    """Extract first and last name from username."""
    firstName = username.split('.')[0].split('_')[0]
    firstName = firstName.capitalize()
    
    lastName = ""
    if '.' in username:
        import re
        parts = username.split('.')
        lastName = re.sub(r'\d+', '', parts[1])  # Remove numbers
        if lastName:
            lastName = lastName.capitalize()
    elif '_' in username:
        parts = username.split('_')
        if len(parts) > 1:
            lastName = parts[1].capitalize()
    
    return firstName, lastName


def create_player_document(player_json: Dict[str, Any], current_time: datetime) -> Dict[str, Any]:
    """Create a MongoDB player document from JSON data."""
    # Convert datetime to ISO format string for JSON serialization
    time_str = current_time.isoformat() + 'Z'
    username = player_json.get('username', '')
    email = player_json.get('email', f"{username}@cp.com")
    level = player_json.get('level', 1)
    rank = player_json.get('rank', 'beginner').lower()
    coins = player_json.get('coins', 1000)
    
    # Use first_name and last_name from JSON if available, otherwise extract from username
    firstName = player_json.get('first_name', '')
    lastName = player_json.get('last_name', '')
    if not firstName or not lastName:
        extracted_first, extracted_last = extract_name_from_username(username)
        if not firstName:
            firstName = extracted_first
        if not lastName:
            lastName = extracted_last
    
    # Use picture from JSON if available, otherwise use empty string
    picture = player_json.get('picture', '')
    
    return {
        "username": username,
        "email": email,
        "password": COMP_PLAYER_PASSWORD,
        "status": "active",
        "is_comp_player": True,
        "created_at": time_str,
        "updated_at": time_str,
        "profile": {
            "first_name": firstName,
            "last_name": lastName,
            "picture": picture,
            "timezone": "UTC",
            "language": "en"
        },
        "preferences": {
            "notifications": {
                "email": False,
                "sms": False,
                "push": False
            },
            "privacy": {
                "profile_visible": False,
                "activity_visible": False
            }
        },
        "modules": {
            "in_app_purchases": {
                "enabled": False,
                "active_purchases": [],
                "subscription_status": "none",
                "last_purchase_date": None,
                "total_spent": 0,
                "currency": "USD",
                "last_updated": time_str
            },
            "dutch_game": {
                "enabled": True,
                "wins": 0,
                "losses": 0,
                "total_matches": 0,
                "points": 0,
                "coins": coins,
                "level": level,
                "rank": rank,
                "win_rate": 0.0,
                "subscription_tier": "promotional",
                "last_match_date": None,
                "last_updated": time_str
            }
        },
        "audit": {
            "last_login": None,
            "login_count": 0,
            "password_changed_at": None,
            "profile_updated_at": None
        }
    }


def upsert_players(players: List[Dict[str, Any]], batch_size: int = 50):
    """Upsert players into MongoDB in batches (local Docker) - inserts new or updates existing."""
    total_upserted = 0
    total_inserted = 0
    total_updated = 0
    failed = 0
    
    for i in range(0, len(players), batch_size):
        batch = players[i:i + batch_size]
        batch_num = i // batch_size + 1
        
        # Create JavaScript file with upsert operations
        js_file = '/tmp/upsert_players_batch.js'
        with open(js_file, 'w') as f:
            f.write(f'db = db.getSiblingDB("{MONGODB_DATABASE}");\n')
            f.write(f'var players = {json.dumps(batch)};\n')
            f.write('var inserted = 0;\n')
            f.write('var updated = 0;\n')
            f.write('players.forEach(function(player) {\n')
            f.write('  var result = db.users.updateOne(\n')
            f.write('    { email: player.email },\n')
            f.write('    { $set: player },\n')
            f.write('    { upsert: true }\n')
            f.write('  );\n')
            f.write('  if (result.upsertedId) {\n')
            f.write('    inserted++;\n')
            f.write('  } else if (result.modifiedCount > 0) {\n')
            f.write('    updated++;\n')
            f.write('  }\n')
            f.write('});\n')
            f.write('print("Inserted: " + inserted + ", Updated: " + updated);\n')
        
        # Copy file into MongoDB container
        copy_to_container_cmd = f'docker cp {js_file} {MONGODB_CONTAINER}:/tmp/upsert_players_batch.js'
        try:
            subprocess.run(copy_to_container_cmd, shell=True, check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            print(f"⚠️  Error copying batch {batch_num} to container: {e.stderr.decode() if e.stderr else str(e)}", file=sys.stderr)
            failed += len(batch)
            # Clean up local file
            try:
                os.remove(js_file)
            except:
                pass
            continue
        
        # Execute the JavaScript file
        mongosh_cmd = f'docker exec {MONGODB_CONTAINER} mongosh -u {MONGODB_USER} -p "{MONGODB_PASSWORD}" --authenticationDatabase {MONGODB_AUTH_DB} /tmp/upsert_players_batch.js'
        
        try:
            result = subprocess.run(
                mongosh_cmd,
                shell=True,
                capture_output=True,
                text=True,
                check=True
            )
            
            # Parse inserted and updated counts
            for line in result.stdout.split('\n'):
                if 'Inserted:' in line and 'Updated:' in line and not line.startswith('Mongo'):
                    try:
                        parts = line.split(',')
                        inserted_count = int(parts[0].split(':')[1].strip())
                        updated_count = int(parts[1].split(':')[1].strip())
                        total_inserted += inserted_count
                        total_updated += updated_count
                        total_upserted += inserted_count + updated_count
                        print(f"  ✅ Batch {batch_num}: Inserted {inserted_count}, Updated {updated_count} players")
                    except (ValueError, IndexError):
                        pass
        except subprocess.CalledProcessError as e:
            print(f"⚠️  Error upserting batch {batch_num}: {e.stderr[:200] if e.stderr else str(e)}", file=sys.stderr)
            failed += len(batch)
        
        # Clean up local file
        try:
            os.remove(js_file)
        except:
            pass
    
    return total_upserted, total_inserted, total_updated, failed


def main():
    parser = argparse.ArgumentParser(description='Add computer players to MongoDB (Local Docker)')
    parser.add_argument('--json-file', default='templates/comp_players.json', help='Path to players JSON file')
    
    args = parser.parse_args()
    
    # Read JSON file
    json_path = os.path.join(os.path.dirname(__file__), args.json_file)
    if not os.path.exists(json_path):
        print(f"❌ JSON file not found: {json_path}", file=sys.stderr)
        sys.exit(1)
    
    with open(json_path, 'r') as f:
        players_data = json.load(f)
    
    print(f"📋 Loaded {len(players_data)} players from {args.json_file}")
    
    # Check if MongoDB container is running
    check_container_cmd = f'docker ps --filter "name={MONGODB_CONTAINER}" --format "{{{{.Names}}}}"'
    try:
        result = subprocess.run(check_container_cmd, shell=True, capture_output=True, text=True, check=True)
        if MONGODB_CONTAINER not in result.stdout:
            print(f"❌ MongoDB container '{MONGODB_CONTAINER}' is not running", file=sys.stderr)
            sys.exit(1)
    except subprocess.CalledProcessError:
        print(f"❌ Error checking MongoDB container status", file=sys.stderr)
        sys.exit(1)
    
    print("🔍 Preparing players for insertion...")
    
    # Create all player documents
    players_to_create = []
    current_time = datetime.utcnow()
    
    for player_json in players_data:
        player_doc = create_player_document(player_json, current_time)
        players_to_create.append(player_doc)
    
    if not players_to_create:
        print(f"✅ All {len(players_data)} players already exist in database")
        return
    
    print(f"\n➕ Upserting {len(players_to_create)} players (insert new or update existing)...")
    
    # Upsert players (insert new or update existing)
    total_upserted, total_inserted, total_updated, failed = upsert_players(players_to_create)
    
    # Summary by rank
    rank_summary = {}
    for player in players_to_create:
        rank = player['modules']['dutch_game']['rank']
        rank_summary[rank] = rank_summary.get(rank, 0) + 1
    
    print(f"\n✅ Upserted {total_upserted} computer player(s)")
    if total_inserted > 0:
        print(f"  ➕ Inserted {total_inserted} new player(s)")
    if total_updated > 0:
        print(f"  🔄 Updated {total_updated} existing player(s) with new profile data")
    if failed > 0:
        print(f"  ❌ Failed to upsert {failed} player(s)")
    
    print("\n📊 Created players by rank:")
    for rank, count in sorted(rank_summary.items()):
        print(f"  - {rank}: {count} players")
    
    # Verify final count
    verify_script = f'''db = db.getSiblingDB('{MONGODB_DATABASE}'); var count = db.users.countDocuments({{"is_comp_player": true}}); print("Total comp players in database: " + count);'''
    
    mongosh_cmd = f'docker exec {MONGODB_CONTAINER} mongosh -u {MONGODB_USER} -p "{MONGODB_PASSWORD}" --authenticationDatabase {MONGODB_AUTH_DB} --eval "{verify_script}"'
    
    try:
        result = subprocess.run(
            mongosh_cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        for line in result.stdout.split('\n'):
            if 'Total comp players' in line:
                print(f"\n📊 {line}")
    except subprocess.CalledProcessError:
        pass


if __name__ == '__main__':
    main()

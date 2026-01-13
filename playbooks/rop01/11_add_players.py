#!/usr/bin/env python3
"""
Add computer players to MongoDB database from JSON file.

This script reads player data from templates/comp_players.json and creates
computer player accounts in the MongoDB database with proper module structure.

Usage:
    python3 11_add_players.py [--vm-name rop01] [--json-file templates/comp_players.json]
"""

import json
import sys
import os
import argparse
import subprocess
from datetime import datetime
from typing import Dict, Any, List, Set
from pathlib import Path

# Bcrypt hash for password "comp_player_pass"
COMP_PLAYER_PASSWORD = "$2b$12$PHGvsjOG3/fjNuEZQP1Szu5/igAj8pppp8XoAFeVyzDbj2EBh3o82"

# MongoDB connection details (from playbook)
MONGODB_CONTAINER = "dutch_external_app_mongodb"
MONGODB_DATABASE = "external_system"
MONGODB_USER = "external_app_user"
MONGODB_PASSWORD = "6R3jjsvVhIRP20zMiHdkBzNKx"
MONGODB_AUTH_DB = "external_system"

# VPS image directory configuration
VPS_IMAGE_DIR = "/var/www/dutch.reignofplay.com/sim_players/images"
LOCAL_IMAGE_DIR = None  # Will be set based on project root


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


def check_existing_players(ssh_base: str, players_data: List[Dict[str, Any]]) -> set:
    """Check which players already exist in the database."""
    existing = set()
    
    # Build query to check for existing usernames and emails
    usernames = [p.get('username') for p in players_data if p.get('username')]
    emails = [p.get('email', f"{p.get('username')}@cp.com") for p in players_data if p.get('username')]
    
    if not usernames:
        return existing
    
    # Create MongoDB query to check existing players
    query = {
        "$or": [
            {"username": {"$in": usernames}},
            {"email": {"$in": emails}}
        ]
    }
    
    query_str = json.dumps(query).replace('"', '\\"')
    
    check_script = f'''db = db.getSiblingDB('{MONGODB_DATABASE}'); var existing = db.users.find({query_str}, {{username: 1, email: 1}}).toArray(); existing.forEach(function(u) {{ print(u.username + "|" + u.email); }});'''
    
    mongosh_cmd = f'docker exec {MONGODB_CONTAINER} mongosh -u {MONGODB_USER} -p "{MONGODB_PASSWORD}" --authenticationDatabase {MONGODB_AUTH_DB} --eval "{check_script}"'
    
    full_cmd = f'{ssh_base} "{mongosh_cmd}"'
    
    try:
        result = subprocess.run(
            full_cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        
        for line in result.stdout.strip().split('\n'):
            if '|' in line and not line.startswith('Mongo'):
                username, email = line.split('|', 1)
                existing.add(username)
                existing.add(email)
    except subprocess.CalledProcessError as e:
        print(f"⚠️  Error checking existing players: {e.stderr}", file=sys.stderr)
    
    return existing


def extract_image_filename(picture_url: str) -> str:
    """Extract image filename from picture URL."""
    if not picture_url:
        return None
    # Extract filename from URL like https://dutch.reignofplay.com/sim_players/images/img000.jpg
    if '/sim_players/images/' in picture_url:
        return picture_url.split('/sim_players/images/')[-1]
    # Or if it's just a filename like img000.jpg
    if picture_url.startswith('img') and picture_url.endswith('.jpg'):
        return picture_url
    return None


def check_existing_images(ssh_base: str) -> Set[str]:
    """Check which images already exist on the VPS."""
    existing = set()
    
    # List files in the remote directory
    list_cmd = f'ls -1 {VPS_IMAGE_DIR} 2>/dev/null || echo ""'
    full_cmd = f'{ssh_base} "{list_cmd}"'
    
    try:
        result = subprocess.run(
            full_cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        
        for line in result.stdout.strip().split('\n'):
            filename = line.strip()
            if filename and filename.endswith('.jpg'):
                existing.add(filename)
    except subprocess.CalledProcessError:
        # Directory might not exist yet, that's okay
        pass
    
    return existing


def upload_images(ssh_base: str, players_data: List[Dict[str, Any]], local_image_dir: Path, ssh_key: str, ssh_user: str, ssh_host: str):
    """Upload player profile images to VPS, skipping if they already exist."""
    if not local_image_dir or not local_image_dir.exists():
        print(f"⚠️  Local image directory not found: {local_image_dir}")
        print("   Skipping image upload...")
        return
    
    # Extract unique image filenames from players
    image_files = {}
    for player in players_data:
        picture_url = player.get('picture', '')
        if picture_url:
            filename = extract_image_filename(picture_url)
            if filename:
                local_path = local_image_dir / filename
                if local_path.exists():
                    image_files[filename] = local_path
    
    if not image_files:
        print("ℹ️  No images found in player data to upload")
        return
    
    print(f"\n📸 Found {len(image_files)} unique images to upload")
    
    # Check existing images on VPS
    existing_images = check_existing_images(ssh_base)
    print(f"   {len(existing_images)} images already exist on VPS")
    
    # Filter out images that already exist
    images_to_upload = {fname: path for fname, path in image_files.items() if fname not in existing_images}
    
    if not images_to_upload:
        print("✅ All images already exist on VPS, skipping upload")
        return
    
    print(f"   Uploading {len(images_to_upload)} new images...")
    
    uploaded = 0
    failed = 0
    
    for filename, local_path in images_to_upload.items():
        remote_tmp = f'/tmp/{filename}'
        remote_final = f'{VPS_IMAGE_DIR}/{filename}'
        
        # Step 1: Upload to temporary location
        scp_cmd = [
            'scp',
            '-i', ssh_key,
            str(local_path),
            f'{ssh_user}@{ssh_host}:{remote_tmp}'
        ]
        
        try:
            subprocess.run(scp_cmd, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if isinstance(e.stderr, str) else (e.stderr.decode() if e.stderr else 'Unknown error')
            print(f"  ❌ Failed to upload {filename}: {error_msg}", file=sys.stderr)
            failed += 1
            continue
        
        # Step 2: Move to final location and set permissions
        ssh_cmd = f'sudo mkdir -p {VPS_IMAGE_DIR} && sudo mv {remote_tmp} {remote_final} && sudo chown www-data:www-data {remote_final} && sudo chmod 644 {remote_final}'
        full_cmd = f'{ssh_base} "{ssh_cmd}"'
        
        try:
            subprocess.run(full_cmd, shell=True, check=True, capture_output=True, text=True)
            uploaded += 1
            if uploaded % 10 == 0:
                print(f"   Progress: {uploaded}/{len(images_to_upload)} uploaded...")
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if isinstance(e.stderr, str) else (e.stderr.decode() if e.stderr else 'Unknown error')
            print(f"  ❌ Failed to move {filename} to final location: {error_msg}", file=sys.stderr)
            # Try to clean up temp file
            cleanup_cmd = f'{ssh_base} "rm -f {remote_tmp}"'
            subprocess.run(cleanup_cmd, shell=True, check=False)
            failed += 1
    
    print(f"\n✅ Image upload complete: {uploaded} uploaded, {failed} failed")
    if uploaded > 0:
        print(f"   Images available at: https://dutch.reignofplay.com/sim_players/images/")


def upsert_players(ssh_base: str, players: List[Dict[str, Any]], batch_size: int = 50):
    """Upsert players into MongoDB in batches (insert new or update existing)."""
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
        
        # Copy JS file to remote server
        copy_cmd = f'scp -i {os.path.expanduser("~/.ssh/rop01_key")} {js_file} rop01_user@65.181.125.135:/tmp/upsert_players_batch.js'
        try:
            subprocess.run(copy_cmd, shell=True, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if isinstance(e.stderr, str) else (e.stderr.decode() if e.stderr else 'Unknown error')
            print(f"⚠️  Error copying batch {batch_num} to server: {error_msg}", file=sys.stderr)
            failed += len(batch)
            # Clean up local file
            try:
                os.remove(js_file)
            except:
                pass
            continue
        
        # Copy file into MongoDB container
        copy_to_container_cmd = f'{ssh_base} "docker cp /tmp/upsert_players_batch.js {MONGODB_CONTAINER}:/tmp/upsert_players_batch.js"'
        try:
            subprocess.run(copy_to_container_cmd, shell=True, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr if isinstance(e.stderr, str) else (e.stderr.decode() if e.stderr else 'Unknown error')
            print(f"⚠️  Error copying batch {batch_num} to container: {error_msg}", file=sys.stderr)
            failed += len(batch)
            # Clean up local file
            try:
                os.remove(js_file)
            except:
                pass
            continue
        
        # Execute the JavaScript file
        mongosh_cmd = f'docker exec {MONGODB_CONTAINER} mongosh -u {MONGODB_USER} -p "{MONGODB_PASSWORD}" --authenticationDatabase {MONGODB_AUTH_DB} /tmp/upsert_players_batch.js'
        
        full_cmd = f'{ssh_base} "{mongosh_cmd}"'
        
        try:
            result = subprocess.run(
                full_cmd,
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
            error_msg = e.stderr if isinstance(e.stderr, str) else (e.stderr[:200] if e.stderr else 'Unknown error')
            print(f"⚠️  Error upserting batch {batch_num}: {error_msg}", file=sys.stderr)
            failed += len(batch)
        
        # Clean up local file
        try:
            os.remove(js_file)
        except:
            pass
    
    return total_upserted, total_inserted, total_updated, failed


def main():
    parser = argparse.ArgumentParser(description='Add computer players to MongoDB')
    parser.add_argument('--vm-name', default='rop01', help='VM name for SSH connection')
    parser.add_argument('--json-file', default='templates/comp_players.json', help='Path to players JSON file')
    parser.add_argument('--ssh-key', default='~/.ssh/rop01_key', help='SSH key path')
    parser.add_argument('--ssh-user', default='rop01_user', help='SSH user')
    parser.add_argument('--ssh-host', default='65.181.125.135', help='SSH host')
    
    args = parser.parse_args()
    
    # Determine project root (two levels up from playbooks/rop01/)
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent.parent
    
    # Set local image directory
    global LOCAL_IMAGE_DIR
    LOCAL_IMAGE_DIR = project_root / 'assets' / 'players_profile' / 'assigned_images'
    
    # Read JSON file
    json_path = os.path.join(os.path.dirname(__file__), args.json_file)
    if not os.path.exists(json_path):
        print(f"❌ JSON file not found: {json_path}", file=sys.stderr)
        sys.exit(1)
    
    with open(json_path, 'r') as f:
        players_data = json.load(f)
    
    print(f"📋 Loaded {len(players_data)} players from {args.json_file}")
    
    # Build SSH command base (as string for shell execution)
    ssh_key_expanded = os.path.expanduser(args.ssh_key)
    ssh_base = f'ssh -i {ssh_key_expanded} {args.ssh_user}@{args.ssh_host}'
    
    # Upload images first (before inserting players)
    print("\n📸 Checking and uploading player profile images...")
    upload_images(ssh_base, players_data, LOCAL_IMAGE_DIR, ssh_key_expanded, args.ssh_user, args.ssh_host)
    
    # Skip checking existing players (MongoDB will handle duplicates)
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
    total_upserted, total_inserted, total_updated, failed = upsert_players(ssh_base, players_to_create)
    
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
    full_cmd = f'{ssh_base} "{mongosh_cmd}"'
    
    try:
        result = subprocess.run(
            full_cmd,
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

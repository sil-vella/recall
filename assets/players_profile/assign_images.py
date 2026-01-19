#!/usr/bin/env python3
"""
Assign images to players from comp_players.json and rename them to imgXXX.jpg format.
"""

import json
import re
import os
import shutil

# Common male and female first names
MALE_NAMES = {
    'sam', 'ben', 'james', 'ryan', 'lucas', 'harry', 'max', 'jordan', 'leo',
    'alex', 'chris', 'david', 'michael', 'john', 'robert', 'william', 'richard',
    'thomas', 'charles', 'daniel', 'matthew', 'anthony', 'mark', 'donald', 'steven',
    'paul', 'andrew', 'joshua', 'kenneth', 'kevin', 'brian', 'george', 'edward',
    'ronald', 'timothy', 'jason', 'jeffrey', 'jacob', 'gary', 'nicholas',
    'eric', 'stephen', 'jonathan', 'larry', 'justin', 'scott', 'brandon', 'benjamin',
    'samuel', 'frank', 'gregory', 'raymond', 'alexander', 'patrick', 'jack', 'dennis',
    'jerry', 'tyler', 'aaron', 'jose', 'henry', 'adam', 'douglas', 'nathan',
    'zachary', 'peter', 'kyle', 'noah', 'alan', 'ethan', 'jeremy', 'walter',
    'christian', 'terry', 'sean', 'lawrence', 'austin', 'joe', 'wayne'
}

FEMALE_NAMES = {
    'emma', 'zoe', 'ella', 'daisy', 'sophia', 'mia', 'isabella', 'charlotte',
    'amelia', 'harper', 'evelyn', 'abigail', 'emily', 'elizabeth', 'mila', 'avery',
    'sofia', 'camila', 'aria', 'scarlett', 'victoria', 'madison', 'luna', 'grace',
    'chloe', 'penelope', 'layla', 'riley', 'zoey', 'nora', 'lily', 'eleanor',
    'hannah', 'lillian', 'addison', 'aubrey', 'ellie', 'stella', 'natalie', 'leah',
    'hazel', 'violet', 'aurora', 'savannah', 'audrey', 'brooklyn', 'bella', 'claire',
    'skylar', 'lucy', 'paisley', 'everly', 'anna', 'caroline', 'nova', 'genesis',
    'aaliyah', 'kennedy', 'kinsley', 'allison', 'maya', 'sarah', 'madelyn', 'adeline',
    'alexa', 'ariana', 'elena', 'gabriella', 'naomi', 'alice', 'sadie', 'hailey',
    'eva', 'emilia', 'autumn', 'quinn', 'nevaeh', 'piper', 'ruby', 'serenity',
    'willow', 'everleigh', 'cora', 'kaylee', 'lydia', 'aubree', 'arianna', 'eliana',
    'jane', 'jennifer', 'lisa', 'patricia', 'linda', 'barbara', 'susan', 'jessica',
    'karen', 'nancy', 'betty', 'helen', 'sandra', 'donna', 'carol',
    'ruth', 'sharon', 'michelle', 'laura', 'kimberly', 'deborah', 'amy'
}

def determine_gender_from_name(first_name):
    """Determine gender from first name."""
    name_lower = first_name.lower().strip()
    
    # Check against known names
    if name_lower in MALE_NAMES:
        return 'male'
    elif name_lower in FEMALE_NAMES:
        return 'female'
    
    # Heuristic: names ending in 'a' are often female (but not always)
    if name_lower.endswith('a') and name_lower not in ['joshua', 'isaiah']:
        return 'female'
    
    # Default to male if uncertain
    return 'male'

def assign_and_rename_images():
    """Assign images to players and rename them."""
    # Paths
    json_path = '../../playbooks/rop01/templates/comp_players.json'
    source_dir = 'individual_profiles'
    target_dir = 'assigned_images'
    
    # Create target directory
    os.makedirs(target_dir, exist_ok=True)
    
    # Load players
    with open(json_path, 'r') as f:
        players = json.load(f)
    
    # Check which images already exist
    existing_images = set()
    if os.path.exists(target_dir):
        for f in os.listdir(target_dir):
            if f.startswith('img') and f.endswith('.jpg'):
                existing_images.add(f)
    
    # Find the highest existing image number
    max_existing = -1
    for img_file in existing_images:
        match = re.search(r'img(\d+)\.jpg', img_file)
        if match:
            max_existing = max(max_existing, int(match.group(1)))
    
    # Process all players, but skip those that already have images
    print(f"Total players in JSON: {len(players)}")
    print(f"Existing images found: {len(existing_images)} (up to img{max_existing:03d}.jpg)\n")
    
    # Filter to only players that don't have images yet
    players_to_process = []
    for i, player in enumerate(players):
        picture_url = player.get('picture', '')
        img_match = re.search(r'img(\d+)\.jpg', picture_url)
        if img_match:
            img_number = int(img_match.group(1))
            target_filename = f"img{str(img_number).zfill(3)}.jpg"
            if target_filename not in existing_images:
                players_to_process.append((i, player, img_number))
    
    print(f"Players needing images: {len(players_to_process)}\n")
    
    # Count available images
    available_male = len([f for f in os.listdir(source_dir) if f.startswith('male') and f.endswith('.jpg')])
    available_female = len([f for f in os.listdir(source_dir) if f.startswith('female') and f.endswith('.jpg')])
    
    print(f"Available images:")
    print(f"  Male: {available_male}")
    print(f"  Female: {available_female}\n")
    
    # Track image assignments
    male_images_used = 0
    female_images_used = 0
    assignments = []
    errors = []
    
    # First pass: create assignments for players that need images
    for i, player, img_number in players_to_process:
        first_name = player.get('first_name', '')
        last_name = player.get('last_name', '')
        target_filename = f"img{str(img_number).zfill(3)}.jpg"
        
        # Determine gender
        gender = determine_gender_from_name(first_name)
        
        # Get source image (reuse if we run out)
        if gender == 'male':
            source_index = male_images_used % available_male  # Reuse images
            source_filename = f"male{str(source_index).zfill(3)}.jpg"
            male_images_used += 1
        else:
            source_index = female_images_used % available_female  # Reuse images
            source_filename = f"female{str(source_index).zfill(3)}.jpg"
            female_images_used += 1
        
        assignments.append({
            'player': f"{first_name} {last_name}",
            'gender': gender,
            'source': source_filename,
            'target': target_filename,
            'img_number': img_number
        })
    
    # Sort by img_number
    assignments.sort(key=lambda x: x['img_number'])
    
    print(f"Image assignments:")
    print(f"  Male images to use: {male_images_used}")
    print(f"  Female images to use: {female_images_used}")
    print(f"  Total assignments: {len(assignments)}\n")
    
    if errors:
        print(f"⚠️  Errors: {len(errors)}")
        for error in errors:
            print(f"  {error}")
        print()
    
    # Second pass: copy and rename images
    print("Copying and renaming images...\n")
    
    copied = 0
    skipped = 0
    failed = 0
    
    for assignment in assignments:
        source_path = os.path.join(source_dir, assignment['source'])
        target_path = os.path.join(target_dir, assignment['target'])
        
        if not os.path.exists(source_path):
            print(f"⚠️  Source not found: {assignment['source']} (for {assignment['player']})")
            failed += 1
            continue
        
        # Skip if target already exists (don't overwrite existing images)
        if os.path.exists(target_path):
            skipped += 1
            if skipped <= 5 or skipped % 20 == 0:
                print(f"  ⏭️  Skipping {assignment['target']} (already exists)")
            continue
        
        # Copy and rename
        try:
            shutil.copy2(source_path, target_path)
            copied += 1
            if copied <= 10 or copied % 20 == 0:
                print(f"  ✅ {assignment['source']} -> {assignment['target']} ({assignment['player']})")
        except Exception as e:
            print(f"  ❌ Error copying {assignment['source']}: {e}")
            failed += 1
    
    print(f"\n{'='*60}")
    print(f"✅ Complete!")
    print(f"{'='*60}")
    print(f"  Images copied: {copied}")
    print(f"  Images skipped (already exist): {skipped}")
    print(f"  Failed: {failed}")
    print(f"  Saved to: {target_dir}/")
    print(f"\n  Images are named: img000.jpg to img{str(len(assignments)-1).zfill(3)}.jpg")

if __name__ == '__main__':
    assign_and_rename_images()

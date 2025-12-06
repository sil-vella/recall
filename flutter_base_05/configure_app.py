#!/usr/bin/env python3
"""
Flutter App Configuration Script
Automatically replaces app-specific declarations with user input.
"""

import os
import re
import sys
from pathlib import Path

class FlutterAppConfigurator:
    def __init__(self):
        self.project_root = Path(__file__).parent
        self.app_name = ""
        self.domain = ""
        self.app_name_lower = ""
        self.app_name_title_case = ""
        self.old_package_name = ""
        
    def detect_old_package_name(self):
        """Detect the old package name from pubspec.yaml."""
        pubspec_path = self.project_root / "pubspec.yaml"
        if pubspec_path.exists():
            try:
                with open(pubspec_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    match = re.search(r'^name:\s*(\w+)', content, re.MULTILINE)
                    if match:
                        self.old_package_name = match.group(1)
                        return True
            except Exception as e:
                print(f"❌ Error reading pubspec.yaml: {e}")
        return False
    
    def get_user_input(self):
        """Get app name and domain from user input."""
        print("🚀 Flutter App Configuration Script")
        print("=" * 50)
        
        # Detect old package name
        if self.detect_old_package_name():
            print(f"📦 Detected current package name: {self.old_package_name}")
        else:
            print("⚠️  Could not detect current package name")
        
        # Optionally allow user to specify an old package name to replace
        user_old_name = input(f"Enter old package name to replace (press Enter to use detected '{self.old_package_name}' and legacy names): ").strip()
        self.extra_old_package_names = []
        if user_old_name:
            self.extra_old_package_names.append(user_old_name)
        
        # Get app name
        while True:
            self.app_name = input("Enter app name (e.g., MyApp): ").strip()
            if self.app_name:
                break
            print("❌ App name cannot be empty. Please try again.")
        
        # Get domain (optional)
        self.domain = input("Enter domain (press Enter to use example.com): ").strip()
        if not self.domain:
            self.domain = "example.com"
        
        # Generate variations
        self.app_name_lower = self.app_name.lower().replace(" ", "")
        self.app_name_title_case = self.app_name.title().replace(" ", "")
        
        print(f"\n✅ Configuration:")
        print(f"   App Name: {self.app_name}")
        print(f"   App Name (lowercase): {self.app_name_lower}")
        print(f"   App Name (Title Case): {self.app_name_title_case}")
        print(f"   Domain: {self.domain}")
        if self.old_package_name:
            print(f"   Old Package Name: {self.old_package_name}")
            print(f"   New Package Name: {self.app_name_lower}")
        if self.extra_old_package_names:
            print(f"   Extra old package names to replace: {self.extra_old_package_names}")
        
        confirm = input("\nProceed with these settings? (y/N): ").strip().lower()
        if confirm not in ['y', 'yes']:
            print("❌ Configuration cancelled.")
            sys.exit(0)
    
    def update_pubspec_yaml(self):
        """Update pubspec.yaml with new app name and description."""
        file_path = self.project_root / "pubspec.yaml"
        if not file_path.exists():
            print(f"❌ {file_path} not found")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace package name - use detected old name
            if self.old_package_name:
                content = re.sub(
                    rf'^name:\s*{re.escape(self.old_package_name)}',
                    f'name: {self.app_name_lower}',
                    content,
                    flags=re.MULTILINE
                )
            
            # Replace description - more flexible pattern
            content = re.sub(
                rf'^description:\s*".*{re.escape(self.old_package_name)}.*"',
                f'description: "{self.app_name} - A Flutter application."',
                content,
                flags=re.MULTILINE
            )
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated {file_path}")
            return True
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            return False
    
    def update_main_dart(self):
        """Update main.dart with new app title."""
        file_path = self.project_root / "lib" / "main.dart"
        if not file_path.exists():
            print(f"❌ {file_path} not found")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace app title - more flexible pattern
            content = re.sub(
                rf'title:\s*"({re.escape(self.old_package_name)}|cleco|Flutter Base 04)\s*App"',
                f'title: "{self.app_name} App"',
                content
            )
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated {file_path}")
            return True
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            return False
    
    def update_config_dart(self):
        """Update config.dart with new app title."""
        file_path = self.project_root / "lib" / "utils" / "consts" / "config.dart"
        if not file_path.exists():
            print(f"❌ {file_path} not found")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace app title - more flexible pattern
            content = re.sub(
                rf'static const String appTitle = "({re.escape(self.old_package_name)}|Cleco|cleco)";',
                f'static const String appTitle = "{self.app_name}";',
                content
            )
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated {file_path}")
            return True
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            return False
    
    def update_android_manifest(self):
        """Update AndroidManifest.xml with new app label, scheme, and URLs."""
        file_path = self.project_root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
        if not file_path.exists():
            print(f"❌ {file_path} not found")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace app label - more flexible pattern
            content = re.sub(
                rf'android:label="({re.escape(self.old_package_name)}|cleco|Flutter Base 04)"',
                f'android:label="{self.app_name}"',
                content
            )
            
            # Replace deep link scheme - more flexible pattern
            content = re.sub(
                rf'android:scheme="({re.escape(self.old_package_name)}|cleco)"',
                f'android:scheme="{self.app_name_lower}"',
                content
            )
            
            # Replace app link host - more flexible pattern
            content = re.sub(
                r'android:host="[^"]*"',
                f'android:host="{self.domain}"',
                content
            )
            
            # Replace privacy policy URL - more flexible pattern
            content = re.sub(
                r'android:value="https://[^"]*"',
                f'android:value="https://{self.domain}/legal/policy.html"',
                content
            )
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated {file_path}")
            return True
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            return False
    
    def update_ios_info_plist(self):
        """Update iOS Info.plist with new display name."""
        file_path = self.project_root / "ios" / "Runner" / "Info.plist"
        if not file_path.exists():
            print(f"❌ {file_path} not found")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace CFBundleDisplayName - more flexible pattern
            content = re.sub(
                r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>',
                f'<key>CFBundleDisplayName</key>\n\t<string>{self.app_name}</string>',
                content
            )
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated {file_path}")
            return True
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            return False
    
    def update_connections_api_module(self):
        """Update connections_api_module.dart with new domain."""
        file_path = self.project_root / "lib" / "modules" / "connections_api_module" / "connections_api_module.dart"
        if not file_path.exists():
            print(f"❌ {file_path} not found")
            return False
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace HTTP URL - more flexible pattern
            content = re.sub(
                r"'http': 'https://[^']*\$path'",
                f"'http': 'https://{self.domain}\$path'",
                content
            )
            
            # Replace app scheme - more flexible pattern
            content = re.sub(
                rf"'app': '({re.escape(self.old_package_name)}|cleco)://\$path'",
                f"'app': '{self.app_name_lower}://\$path'",
                content
            )
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated {file_path}")
            return True
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            return False
    
    def update_package_imports(self):
        """Update all package imports in Dart files."""
        dart_files = list(self.project_root.rglob("*.dart"))
        updated_files = 0
        
        # Build list of old package names to check
        old_package_names = []
        if self.old_package_name:
            old_package_names.append(self.old_package_name)
        # Add user-specified old names
        if hasattr(self, 'extra_old_package_names'):
            old_package_names.extend(self.extra_old_package_names)
        # Always check for common legacy names
        old_package_names.extend(['cleco', 'flutter_base_04'])
        # Remove duplicates
        old_package_names = list(dict.fromkeys(old_package_names))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                file_updated = False
                # Check for any old package imports
                for old_pkg in old_package_names:
                    old_import_pattern = f"package:{old_pkg}/"
                    if old_import_pattern in content:
                        # Replace all package imports
                        content = content.replace(
                            f"package:{old_pkg}/",
                            f"package:{self.app_name_lower}/"
                        )
                        file_updated = True
                
                if file_updated:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(content)
                    
                    updated_files += 1
                    print(f"✅ Updated imports in {file_path.relative_to(self.project_root)}")
            
            except Exception as e:
                print(f"❌ Error updating {file_path}: {e}")
        
        if updated_files > 0:
            print(f"✅ Updated package imports in {updated_files} files")
        else:
            print("ℹ️  No package imports found to update")
        
        return True
    

    
    def run(self):
        """Run the configuration process."""
        self.get_user_input()
        
        print("\n🔄 Updating files...")
        print("-" * 30)
        
        # Define all update functions
        update_functions = [
            ("pubspec.yaml", self.update_pubspec_yaml),
            ("main.dart", self.update_main_dart),
            ("config.dart", self.update_config_dart),
            ("AndroidManifest.xml", self.update_android_manifest),
            ("Info.plist", self.update_ios_info_plist),
            ("connections_api_module.dart", self.update_connections_api_module),
            ("package imports", self.update_package_imports),
        ]
        
        success_count = 0
        total_files = len(update_functions)
        
        # Update all files
        for name, update_func in update_functions:
            if update_func():
                success_count += 1
        
        print("\n" + "=" * 50)
        print(f"✅ Configuration complete!")
        print(f"   Successfully updated: {success_count}/{total_files} files")
        
        if success_count == total_files:
            print("\n🎉 All files updated successfully!")
            print("\n📋 Summary of changes:")
            print(f"   • App name: {self.app_name}")
            print(f"   • Package name: {self.app_name_lower}")
            print(f"   • Domain: {self.domain}")
            print(f"   • Deep link scheme: {self.app_name_lower}://")
            print(f"   • App link host: {self.domain}")
            if self.old_package_name and self.old_package_name != self.app_name_lower:
                print(f"   • Package name changed: {self.old_package_name} → {self.app_name_lower}")
        else:
            failed_count = total_files - success_count
            print(f"\n⚠️  {failed_count} files failed to update.")
            print("Please check the error messages above and update manually if needed.")

def main():
    """Main function."""
    configurator = FlutterAppConfigurator()
    configurator.run()

if __name__ == "__main__":
    main() 
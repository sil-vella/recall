import os
import shutil
import sys
import subprocess
import tempfile

def convert_png_to_icns(png_path):
    """Convert PNG to ICNS format for macOS"""
    try:
        # Install Pillow if not present
        subprocess.run([sys.executable, "-m", "pip", "install", "pillow"], check=True)
        
        from PIL import Image
        import subprocess
        
        # Create temporary directory for icon conversion
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create iconset directory
            iconset_dir = os.path.join(temp_dir, "icon.iconset")
            os.makedirs(iconset_dir)
            
            # Open and resize image
            img = Image.open(png_path)
            
            # Generate different sizes
            sizes = [16, 32, 64, 128, 256, 512, 1024]
            for size in sizes:
                resized = img.resize((size, size), Image.Resampling.LANCZOS)
                resized.save(os.path.join(iconset_dir, f"icon_{size}x{size}.png"))
                if size <= 512:  # Also create @2x versions
                    resized = img.resize((size*2, size*2), Image.Resampling.LANCZOS)
                    resized.save(os.path.join(iconset_dir, f"icon_{size}x{size}@2x.png"))
            
            # Convert iconset to icns
            icns_path = os.path.join(temp_dir, "icon.icns")
            subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
            
            return icns_path
    except Exception as e:
        print(f"Warning: Could not convert icon: {e}")
        return None

def package_web():
    # Source and destination paths
    source_dir = os.path.join('build', 'web')
    dest_dir = 'cleco_web'
    
    # Check if web build exists
    if not os.path.exists(source_dir):
        print("❌ Web build not found. Please run 'flutter build web' first.")
        return False
    
    # Create destination directory
    if os.path.exists(dest_dir):
        shutil.rmtree(dest_dir)
    os.makedirs(dest_dir)
    
    # Copy web build
    shutil.copytree(source_dir, os.path.join(dest_dir, 'web'))
    
    # Convert icon
    png_icon = os.path.join(dest_dir, 'web', 'favicon.png')
    icns_icon = convert_png_to_icns(png_icon) if os.path.exists(png_icon) else None
    
    # Create run script
    with open(os.path.join(dest_dir, 'run.py'), 'w') as f:
        f.write('''import os
import webbrowser
from http.server import HTTPServer, SimpleHTTPRequestHandler
import time
import sys
import tkinter as tk
from tkinter import messagebox

def resource_path(relative_path):
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")
    return os.path.join(base_path, relative_path)

def main():
    # Create a simple GUI window
    root = tk.Tk()
    root.withdraw()  # Hide the main window
    
    # Start the server
    os.chdir(resource_path('web'))
    server = HTTPServer(('', 8000), SimpleHTTPRequestHandler)
    
    # Open browser
    webbrowser.open('http://localhost:8000')
    
    # Show message
    messagebox.showinfo("cleco Web App", "App is running at http://localhost:8000\\n\\nClick OK to close the app.")
    
    # Cleanup
    server.shutdown()
    root.destroy()

if __name__ == "__main__":
    main()
''')
    
    # Create spec file for PyInstaller
    with open(os.path.join(dest_dir, 'cleco.spec'), 'w') as f:
        f.write(f'''# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['run.py'],
    pathex=[],
    binaries=[],
    datas=[('web', 'web')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={{}},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='cleco',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon={repr(icns_icon) if icns_icon else None}
)

app = BUNDLE(
    exe,
    name='cleco.app',
    icon={repr(icns_icon) if icns_icon else None},
    bundle_identifier='com.cleco.app',
    info_plist={{
        'CFBundleShortVersionString': '1.0.0',
        'CFBundleVersion': '1.0.0',
        'NSHighResolutionCapable': 'True'
    }}
)
''')
    
    print("✅ Creating macOS app...")
    try:
        # Install PyInstaller if not present
        subprocess.run([sys.executable, "-m", "pip", "install", "pyinstaller"], check=True)
        
        # Create app
        subprocess.run([
            sys.executable, 
            "-m", 
            "PyInstaller",
            "--clean",
            "--noconfirm",
            os.path.join(dest_dir, 'cleco.spec')
        ], check=True)
        
        # Move app to dist folder
        shutil.move(
            os.path.join('dist', 'cleco.app'),
            os.path.join(dest_dir, 'cleco.app')
        )
        
        # Cleanup
        shutil.rmtree('build', ignore_errors=True)
        shutil.rmtree('dist', ignore_errors=True)
        os.remove(os.path.join(dest_dir, 'cleco.spec'))
        os.remove(os.path.join(dest_dir, 'run.py'))
        if icns_icon:
            os.remove(icns_icon)
        
        print(f"✅ macOS app created: {os.path.join(dest_dir, 'cleco.app')}")
        print("\nTo distribute:")
        print("1. Copy the 'cleco_web' folder")
        print("2. Share the 'cleco.app' file")
        print("3. Users can just double-click to run!")
        
    except Exception as e:
        print(f"❌ Error creating app: {e}")
        return False
    
    return True

if __name__ == "__main__":
    package_web() 
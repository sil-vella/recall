import subprocess

# Define environment variables dynamically
api_url_local = "http://127.0.0.1:5000"
api_url = "https://fmif.reignofplay.com"
admob_top_banner = "ca-app-pub-3940256099942544/9214589741"
admob_bottom_banner = "ca-app-pub-3940256099942544/9214589741"
admob_interstitial = "ca-app-pub-3940256099942544/1033173712"
admob_rewarded = "ca-app-pub-3940256099942544/5224354917"

# Run the flutter build command
flutter_command = [
    "flutter", "build", "appbundle",
    f"--dart-define=API_URL_LOCAL={api_url_local}",
    f"--dart-define=API_URL={api_url}",
    f"--dart-define=ADMOBS_TOP_BANNER01={admob_top_banner}",
    f"--dart-define=ADMOBS_BOTTOM_BANNER01={admob_bottom_banner}",
    f"--dart-define=ADMOBS_INTERSTITIAL01={admob_interstitial}",
    f"--dart-define=ADMOBS_REWARDED01={admob_rewarded}",
    "--split-debug-info=build/symbols"
]

try:
    subprocess.run(flutter_command, check=True)
    print("✅ Build completed successfully.")
except subprocess.CalledProcessError as e:
    print(f"❌ Build failed: {e}")

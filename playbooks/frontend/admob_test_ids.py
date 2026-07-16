"""Google AdMob demo (test) application + unit ids per platform.

Used by `ios_admob_gad_app_id.sh` and docs. Production unit ids are SSOT in
`.env.local` / `.env.prod` (Flask init-config), not dart-defines.

See https://developers.google.com/admob/ios/test-ads
and https://developers.google.com/admob/android/test-ads
"""

from __future__ import annotations

# iOS test application id uses ~1458002511 (not Android's ~3347511713).
IOS_ADMOB_TEST: dict[str, str] = {
    "ADMOB_APPLICATION_ID": "ca-app-pub-3940256099942544~1458002511",
    "ADMOBS_IOS_TOP_BANNER01": "ca-app-pub-3940256099942544/2934735716",
    "ADMOBS_IOS_BOTTOM_BANNER01": "ca-app-pub-3940256099942544/2934735716",
    "ADMOBS_IOS_INTERSTITIAL01": "ca-app-pub-3940256099942544/4411468910",
    "ADMOBS_IOS_REWARDED01": "ca-app-pub-3940256099942544/1712485313",
}

ANDROID_ADMOB_TEST: dict[str, str] = {
    "ADMOB_APPLICATION_ID": "ca-app-pub-3940256099942544~3347511713",
    "ADMOBS_ANDROID_TOP_BANNER01": "ca-app-pub-3940256099942544/6300978111",
    "ADMOBS_ANDROID_BOTTOM_BANNER01": "ca-app-pub-3940256099942544/6300978111",
    "ADMOBS_ANDROID_INTERSTITIAL01": "ca-app-pub-3940256099942544/1033173712",
    "ADMOBS_ANDROID_REWARDED01": "ca-app-pub-3940256099942544/5224354917",
}

ANDROID_ADMOB_PROD_APP_ID = "ca-app-pub-6524100109992126~6470366151"
IOS_ADMOB_PROD_APP_ID = "ca-app-pub-6524100109992126~6082396455"

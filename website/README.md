# Dutch — static landing (VPS docroot)

Small HTML/CSS/JS site aligned with the Flutter **Dutch** theme (`ThemePreset.dutch` in `flutter_base_05/lib/utils/consts/theme_consts.dart`).

## Paths (on purpose, not generic)

| URL prefix | Local folder |
|------------|----------------|
| `/static_landing_css/` | `website/static_landing_css/` |
| `/static_landing_js/` | `website/static_landing_js/` |
| `/static_landing_images/` | `website/static_landing_images/` (`logo.webp`, `logo_icon.webp` from `flutter_base_05/assets/images/`) |

This avoids `/css/`, `/js/`, and `/images/`, which are easy to confuse with other apps or proxies.

## Nginx (VPS, manual)

Place these **before** any regex that proxies unknown paths to Flask (same idea as `/app_media/`). `^~` stops regex search so these win over the catch-all proxy.

```nginx
# Universal Links + Android App Links (HTTPS, no redirects)
location ^~ /.well-known/ {
    alias /var/www/dutch.reignofplay.com/.well-known/;
    default_type application/json;
    types { }
    add_header Cache-Control "public, max-age=300";
    autoindex off;
}

# Open-in-app links (Universal / App Links): https://dutch.reignofplay.com/gotoapp/<CODE>
location ^~ /gotoapp {
    root /var/www/dutch.reignofplay.com;
    try_files /gotoapp/index.html =404;
    add_header Cache-Control "public, max-age=300";
}

# Social / tracking short links → root landing with ?ref=
# /rl/test → 302 → /?ref=test
location ~ ^/rl/([^/]+)/?$ {
    return 302 /?ref=$1;
}

location ^~ /static_landing_css/ {
    alias /var/www/dutch.reignofplay.com/static_landing_css/;
    autoindex off;
    add_header Cache-Control "public, max-age=3600";
}

location ^~ /static_landing_js/ {
    alias /var/www/dutch.reignofplay.com/static_landing_js/;
    autoindex off;
    add_header Cache-Control "public, max-age=3600";
}

location ^~ /static_landing_images/ {
    alias /var/www/dutch.reignofplay.com/static_landing_images/;
    autoindex off;
    add_header Cache-Control "public, max-age=86400";
    add_header Access-Control-Allow-Origin "*" always;
}
```

Then `sudo nginx -t && sudo systemctl reload nginx`.

If you previously added `/images/`, remove that block and use `/static_landing_images/` only.

## Referral / App Links

### Final workflow

1. **Shlink** short URL ends with `/rl/<REFCODE>` (social / tracking).
2. Nginx **302** → `https://dutch.reignofplay.com/?ref=<REFCODE>`.
3. Root **landing** (`index.html`): if `?ref=` is set, show **GET BONUS COINS**.
4. Button tries **`dutch://gotoapp/<REFCODE>`** first (custom scheme; works from same-site Safari), then falls back to **`/gotoapp/<REFCODE>`**.
5. App receives the code and syncs rewards (see [`Documentation/Referrals/CAMPAIGN_REFERRAL_CODES.md`](../Documentation/Referrals/CAMPAIGN_REFERRAL_CODES.md)).

| URL | Purpose |
|-----|---------|
| Shlink → `…/rl/<CODE>` | Short share / tracking entry |
| `…/rl/<CODE>` | **302** → `/?ref=<CODE>` |
| `/?ref=<CODE>` | Landing; **GET BONUS COINS** → `dutch://` then `/gotoapp/<CODE>` |
| `/gotoapp/<CODE>` | Opens installed app; fallback home → `/?ref=<CODE>` |
| `dutch://gotoapp/<CODE>` | Custom scheme for same-site Safari / simulator |
| `/.well-known/apple-app-site-association` | iOS — paths `/gotoapp/*` only |
| `/.well-known/assetlinks.json` | Android |

Play App Signing SHA-256 is set in `website/.well-known/assetlinks.json` (production).

## Deploy

```bash
cd /path/to/app_dev
ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/17_upload_dutch_landing_site.yml -e vm_name=rop01
```

Updates `index.html`, `app-ads.txt`, `.well-known/`, `gotoapp/index.html`, and the three `static_landing_*` trees — **not** `downloads/`, `app_media/`, or `sim_players/`. Nginx maps `/rl/<CODE>` → `302 /?ref=<CODE>`.

## AdMob `app-ads.txt`

Google requires `https://<your-app-store-domain>/app-ads.txt` for iOS (and Play) app verification. The file must live at the **domain root** that matches **App Store Connect** exactly (e.g. `dutch.reignofplay.com` or `reignofplay.com` — not both unless both are listed).

After deploy, verify:

```bash
curl -s https://dutch.reignofplay.com/app-ads.txt
```

Then in AdMob → Apps → Dutch Card Game (iOS) → **Check for updates**.

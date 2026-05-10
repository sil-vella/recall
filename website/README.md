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

Place these **before** any regex that proxies unknown paths to Flask (same idea as `/sponsors/`). `^~` stops regex search so these win over the catch-all proxy.

```nginx
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

## Deploy

```bash
cd /path/to/app_dev
ansible-playbook -i playbooks/rop01/inventory.ini playbooks/rop01/17_upload_dutch_landing_site.yml -e vm_name=rop01
```

Only updates `index.html` and the three `static_landing_*` trees above — **not** `downloads/`, `sponsors/`, or `sim_players/`.

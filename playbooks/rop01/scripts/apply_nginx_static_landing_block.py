#!/usr/bin/env python3
"""Replace legacy /images/ landing block with static_landing_* locations on VPS dutch.mt vhost."""
from pathlib import Path

PATH = Path("/etc/nginx/sites-available/dutch.mt")

OLD = r"""    # Static landing site images (logo, favicon) — ^~ takes precedence over regex proxy below
    location ^~ /images/ {
        alias /var/www/dutch.reignofplay.com/images/;
        autoindex off;
        expires 7d;
        add_header Cache-Control "public";
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "*" always;
        if ( = OPTIONS) {
            return 204;
        }
    }
"""

NEW = r"""    # Static landing site (prefixed paths — before regex proxy to Flask)
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
        expires 7d;
        add_header Cache-Control "public";
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "*" always;
        if ($request_method = OPTIONS) {
            return 204;
        }
    }
"""


def main() -> None:
    t = PATH.read_text()
    if OLD not in t:
        raise SystemExit("expected old /images/ block not found — edit manually")
    PATH.write_text(t.replace(OLD, NEW, 1))
    print("patched:", PATH)


if __name__ == "__main__":
    main()

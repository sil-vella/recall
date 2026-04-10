# Profile avatar upload (Python API)

## Endpoints

- `POST /userauth/users/profile/avatar` — JWT required. Multipart field name: `file`. Allowed client extensions: `.jpg`, `.jpeg`, `.png`, `.webp`; declared `Content-Type` must match file magic bytes. Max upload size is capped (default 5 MiB, configurable, hard ceiling 10 MiB).
- `GET /public/avatar-media/<filename>` — Serves normalized WebP files (opaque `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.webp` names). Filename must match the strict server pattern.

## Environment / config

| Variable / file key | Purpose |
|---------------------|---------|
| `AVATAR_MAX_UPLOAD_BYTES` | Max raw multipart size (clamped to 10 MiB; default 5242880). |
| `AVATAR_STORAGE_DIR` | Filesystem directory for stored WebP files (default `/tmp/avatar_uploads`). |
| `AVATAR_PUBLIC_BASE_URL` | Optional URL prefix for `profile.picture` (no trailing slash). If empty, `APP_URL` is used. |
| `AVATAR_MAX_EDGE_PX` | Max width and max height of bounding box after resize; aspect ratio preserved (default 100). |
| `AVATAR_MAX_DIMENSION_PX` | Reject decode if width or height exceeds this (default 4096). |
| `AVATAR_MAX_IMAGE_PIXELS` | Pillow decompression bomb guard (default 20000000). |

## Production (nginx / CDN)

1. Set `AVATAR_STORAGE_DIR` to a persistent path (e.g. `/var/lib/app/avatars`).
2. Either:
   - **A)** Keep serving via Flask `GET /public/avatar-media/<filename>` (simplest), or
   - **B)** Serve the same directory with nginx `alias` and set `AVATAR_PUBLIC_BASE_URL` to your CDN or `https://api.example.com` where that location is mapped (e.g. `location /public/avatar-media/ { alias /var/lib/app/avatars/; }` — align URL path with how `profile.picture` is built in code).

## Object storage (optional later)

Replace filesystem write in `upload_profile_avatar` with S3/R2 upload and set `profile.picture` to the public object URL; keep the same validation pipeline (magic bytes, Pillow, size limits).

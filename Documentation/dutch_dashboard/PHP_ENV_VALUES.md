# PHP dashboard env values — where to get them

Values the **PHP dashboard** needs for `PYTHON_API_BASE_URL`, `DUTCH_MT_DASHBOARD_SERVICE_KEY`, and `JWT_SECRET`. The repo does not store real secrets; this doc explains where the Python (Flask) app gets them so you can use the same on the PHP side.

---

## How PHP talks to the Python Flask server (aligned contract)

1. **Outbound HTTP only**  
   PHP calls the Python API; Python does not call PHP.  
   Base URL comes from **PYTHON_API_BASE_URL** (e.g. in PHP `config.php` via `.env`).  
   All calls should go through a single client (e.g. PHP `lib/python_client.php`) using the same headers and base URL. Base URL has no trailing slash.

2. **Two kinds of calls**  
   | Type   | When                         | Auth                                      | PHP functions (example)     |
   |--------|------------------------------|-------------------------------------------|-----------------------------|
   | Service (authenticated) | Dashboard actions (create tournament, health) | `X-Service-Key: <DUTCH_MT_DASHBOARD_SERVICE_KEY>` | `python_post()`, `python_get()` |
   | Public | Optional future use (e.g. public registration to Python) | None | `python_post_public()` |

   Auth with the Flask server is done **only** via the `X-Service-Key` header for service endpoints. PHP does **not** send user JWT or any other token to Python.

3. **Service-key auth (PHP → Flask)**  
   - **Secret:** `DUTCH_MT_DASHBOARD_SERVICE_KEY` in PHP env; the **same** value must be configured on the Flask side.  
   - **Usage:** For every request to a **service** Python endpoint, PHP sends:  
     **Header:** `X-Service-Key: <DUTCH_MT_DASHBOARD_SERVICE_KEY>`  
     **Body:** JSON where applicable (e.g. create-tournament).  
   - **Contract:** Flask requires `X-Service-Key` on `/service/*` routes and validates it (e.g. compares to the same secret). This repo contains the Flask app that checks the header; the PHP app only sends it.

4. **No auth proxy to Python**  
   User auth is only in PHP: login/register and JWT creation/verification use PHP + MariaDB and `JWT_SECRET`. PHP **never** calls Python to validate user tokens.  
   **Flow for protected actions:** Frontend sends `Authorization: Bearer <JWT>` to PHP → PHP verifies the JWT locally → If valid, PHP then calls the Python **service** endpoint with **only** `X-Service-Key` (and optional JSON body). The Flask server trusts the caller because of the service key, not because it sees the user’s JWT.

5. **Concrete flows (Flask side)**  
   - **Create tournament**  
     PHP: `POST {baseUrl}/service/dutch/create-tournaments` with `Content-Type: application/json` and `X-Service-Key: <service_key>`, body = dashboard input JSON.  
     Flask: Route exists; validates `X-Service-Key` (middleware); returns JSON (e.g. `success`, `message`).  
   - **Health (Python)**  
     PHP: `GET {baseUrl}/service/health` with `X-Service-Key: <service_key>`.  
     Flask: Route exists; same health logic as `/health`; validates `X-Service-Key` (middleware).  
   - **Public endpoints**  
     Paths under `/public/` do **not** require `X-Service-Key`. Use for future calls that need no service auth.

6. **Config (PHP side)**  
   From PHP `config.php` / `.env`:  
   - **PYTHON_API_BASE_URL** — Flask base URL (no trailing slash).  
   - **DUTCH_MT_DASHBOARD_SERVICE_KEY** — Secret for `X-Service-Key` (must match Flask’s expectation).  
   If either is missing, the code that needs Python (e.g. create-tournament, health-python) should not call Flask (e.g. return 500).

---

## 1. PYTHON_API_BASE_URL

**What PHP uses it for:** Base URL of the Python API (no trailing slash). PHP calls e.g. `{PYTHON_API_BASE_URL}/service/health` and `{PYTHON_API_BASE_URL}/service/dutch/create-tournaments`.

**Actual value:** Depends on deployment. Examples from this project:

| Environment | Value |
|-------------|--------|
| Local (Flask on same machine) | `http://localhost:5001` |
| Local (Flask on LAN) | `http://192.168.178.81:5001` (from playbooks) |
| Production (from playbooks) | `https://dutch.mt` |

Use the URL where your **Python/Flask API** is actually reachable. Local defaults align on port **5001** (`app.debug.py`, `Config`, playbooks, Docker).

---

## 2. DUTCH_MT_DASHBOARD_SERVICE_KEY

**What PHP uses it for:** Same logic as Dart backend: sent as `X-Service-Key` (or `Authorization: Bearer <key>`) on **every** request to Python paths under `/service/*` (e.g. health, create-tournaments). Must match Python’s `DUTCH_MT_DASHBOARD_SERVICE_KEY` config.

**Where Python gets it** ([python_base_04/utils/config/config.py](python_base_04/utils/config/config.py)):

- **File (priority):** `dutch_mt_dashboard_service_key`  
  Looked up in: `/run/secrets/`, `/app/secrets/`, `./secrets/`
- **Env:** `DUTCH_MT_DASHBOARD_SERVICE_KEY`
- **Default in code:** `""` (empty) — **you must set it**

**Actual value:** There is no value in the repo. You must:

1. Generate a strong secret (e.g. long random string).
2. Set it **in Python**: env `DUTCH_MT_DASHBOARD_SERVICE_KEY` or a file named `dutch_mt_dashboard_service_key` in one of the paths above.
3. Set the **same** value in PHP as `DUTCH_MT_DASHBOARD_SERVICE_KEY`.

---

## 3. JWT_SECRET

**What PHP uses it for:** To verify JWTs locally (signature check). Must be the same secret the Python app uses to **sign** JWTs.

**Where Python gets it** ([python_base_04/utils/config/config.py](python_base_04/utils/config/config.py), `Config.JWT_SECRET_KEY`):

- **Vault (production):** path `flask-app/app`, key `secret_key`
- **File (priority if no Vault):** `jwt_secret_key`  
  Looked up in: `/run/secrets/`, `/app/secrets/`, `./secrets/`
- **Env:** `JWT_SECRET_KEY`
- **Default in code:** `your-super-secret-key-change-in-production`

**Actual value:**

- **If you have not set anything:** Python uses the default above. For PHP, set:
  ```bash
  JWT_SECRET=your-super-secret-key-change-in-production
  ```
  (Only for local/dev; change in production.)
- **If you have set it (file / env / Vault):** Use the **exact same** value for PHP’s `JWT_SECRET` (e.g. read from the same secret store or copy from `jwt_secret_key` / `JWT_SECRET_KEY` where Python runs).

---

## Summary

| PHP env | Where to get the actual value |
|--------|--------------------------------|
| `PYTHON_API_BASE_URL` | Your Python API base URL, e.g. `http://localhost:5001` or `https://dutch.mt`. |
| `DUTCH_MT_DASHBOARD_SERVICE_KEY` | Not in repo. Generate one; set it in Python (env or file `dutch_mt_dashboard_service_key`) and in PHP. |
| `JWT_SECRET` | Same as Python’s JWT signing secret: Python’s `JWT_SECRET_KEY` (Vault / file `jwt_secret_key` / env `JWT_SECRET_KEY`). Default in code is `your-super-secret-key-change-in-production` if nothing is set. |

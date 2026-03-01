# PHP dashboard env values — where to get them

Values the **PHP dashboard** needs for `PYTHON_API_BASE_URL`, `DUTCH_MT_DASHBOARD_SERVICE_KEY`, and `JWT_SECRET`. The repo does not store real secrets; this doc explains where the Python app gets them so you can use the same on the PHP side.

---

## 1. PYTHON_API_BASE_URL

**What PHP uses it for:** Base URL of the Python API (no trailing slash). PHP calls e.g. `{PYTHON_API_BASE_URL}/service/health` and `{PYTHON_API_BASE_URL}/service/dutch/create-tournaments`.

**Actual value:** Depends on deployment. Examples from this project:

| Environment | Value |
|-------------|--------|
| Local (Flask on same machine) | `http://localhost:5001` |
| Local (Flask on LAN) | `http://192.168.178.81:5001` (from playbooks) |
| Production (from playbooks) | `https://dutch.mt` |

Use the URL where your **Python/Flask API** is actually reachable. Flask default port in config is 5000; playbooks often use 5001.

---

## 2. DUTCH_MT_DASHBOARD_SERVICE_KEY

**What PHP uses it for:** Sent as `X-Service-Key` when calling Python `/service/*` (health, create-tournaments). Must match Python’s config.

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

# Config: Secret Files vs Hardcoded

In `config.py`, values are loaded with this priority:

- **`get_file_first_config_value(file_name, env_name, default)`** → **Secret file** (`secrets/<file_name>`) > Env > Default
- **`get_config_value(vault_path, vault_key, file_name, env_name, default)`** → **Secret file** > Vault > Env > Default
- **`get_sensitive_config_value(vault_path, vault_key, file_name, env_name, default)`** → Vault > **Secret file** > Env > Default

So if a `file_name` is given, that value **can** come from `python_base_04/secrets/<file_name>` (and is what gets copied to the VPS by the deploy playbook).

---

## From secret files (can be overridden by env or default)

These `Config` attributes read from the **secrets directory** first (or Vault for sensitive ones), then env, then default. The secret **file name** is the first argument in the table.

### App & identity
| Config | Secret file | Env | Default |
|--------|-------------|-----|---------|
| APP_ID | app_id | APP_ID | external_app_001 |
| APP_NAME | app_name | APP_NAME | External Application |
| APP_VERSION | app_version | APP_VERSION | 2.0.0 |
| APP_DOWNLOAD_BASE_URL | app_download_base_url | APP_DOWNLOAD_BASE_URL | https://dutch.mt/downloads |
| APP_URL | app_url | APP_URL | http://localhost:5000 |

### Flask & service
| Config | Secret file | Env | Default |
|--------|-------------|-----|---------|
| FLASK_SERVICE_NAME | flask_service_name | FLASK_SERVICE_NAME | flask |
| FLASK_PORT | flask_port | FLASK_PORT | 5000 |
| PYTHONPATH | pythonpath | PYTHONPATH | /app |
| FLASK_ENV | (none) | FLASK_ENV | development |

### MongoDB (sensitive: Vault > file > env > default)
| Config | Secret file | Env |
|--------|-------------|-----|
| MONGODB_SERVICE_NAME | mongodb_service_name | MONGODB_SERVICE_NAME |
| MONGODB_ROOT_USER | mongodb_root_user | MONGODB_ROOT_USER |
| MONGODB_ROOT_PASSWORD | mongodb_root_password | MONGODB_ROOT_PASSWORD |
| MONGODB_USER | mongodb_user | MONGODB_USER |
| MONGODB_PASSWORD | mongodb_user_password | MONGODB_PASSWORD |
| MONGODB_DB_NAME | mongodb_db_name | MONGODB_DB_NAME |
| MONGODB_PORT | mongodb_port | MONGODB_PORT |

### Redis (sensitive for password)
| Config | Secret file | Env |
|--------|-------------|-----|
| REDIS_SERVICE_NAME | redis_service_name | REDIS_SERVICE_NAME |
| REDIS_HOST | redis_host | REDIS_HOST |
| REDIS_PORT | redis_port | REDIS_PORT |
| REDIS_PASSWORD | redis_password | REDIS_PASSWORD |
| REDIS_DB, REDIS_USE_SSL, REDIS_*, RATE_LIMIT_STORAGE_URL | redis_* / rate_limit_storage_url | REDIS_* |

### JWT & auth
| Config | Secret file | Env |
|--------|-------------|-----|
| JWT_SECRET_KEY | jwt_secret_key | JWT_SECRET_KEY |
| JWT_ACCESS_TOKEN_EXPIRES, JWT_REFRESH_TOKEN_EXPIRES, JWT_ALGORITHM, JWT_* | jwt_* | JWT_* |

### Service keys
| Config | Secret file | Env |
|--------|-------------|-----|
| DART_BACKEND_SERVICE_KEY | dart_backend_service_key | DART_BACKEND_SERVICE_KEY |
| DUTCH_MT_DASHBOARD_SERVICE_KEY | dutch_mt_dashboard_service_key | DUTCH_MT_DASHBOARD_SERVICE_KEY |
| ENABLE_DART_SERVICE_KEY_AUTH | enable_dart_service_key_auth | ENABLE_DART_SERVICE_KEY_AUTH |

### Stripe (sensitive)
| Config | Secret file | Env |
|--------|-------------|-----|
| STRIPE_SECRET_KEY | stripe_secret_key | STRIPE_SECRET_KEY |
| STRIPE_PUBLISHABLE_KEY | stripe_publishable_key | STRIPE_PUBLISHABLE_KEY |
| STRIPE_WEBHOOK_SECRET | stripe_webhook_secret | STRIPE_WEBHOOK_SECRET |
| STRIPE_API_VERSION | stripe_api_version | STRIPE_API_VERSION |

### Google OAuth
| Config | Secret file | Env |
|--------|-------------|-----|
| GOOGLE_CLIENT_ID | google_client_id | GOOGLE_CLIENT_ID |
| GOOGLE_CLIENT_SECRET | google_client_secret | GOOGLE_CLIENT_SECRET |

### Vault, credit system, encryption
| Config | Secret file | Env |
|--------|-------------|-----|
| VAULT_*, DB_CREDS_FILE | vault_*, db_creds_file | VAULT_*, DB_CREDS_FILE |
| CREDIT_SYSTEM_URL, CREDIT_SYSTEM_API_KEY | credit_system_* | CREDIT_SYSTEM_* |
| ENCRYPTION_KEY, ENCRYPTION_SALT | encryption_key, encryption_salt | ENCRYPTION_* |

### DB pool, rate limit, auto-ban, credit/transaction validation, WebSocket, Dutch game
All of these use **secret file** (same name as config key, snake_case) > env > default, e.g.:
- db_pool_min_conn, db_connect_timeout, rate_limit_*, auto_ban_*, credit_min_amount, mongodb_uri, ws_*, dutch_player_action_timeout, etc.

---

## Hardcoded only (no secret file)

These are **not** read from secret files; they are fixed in code (or from Vault/Env only, no file).

| Config | Source |
|--------|--------|
| **DEBUG** | get_config_value with **no file_name** → Vault > Env (FLASK_DEBUG) > Default "False" |
| **RATE_LIMIT_HEADER_LIMIT** | Literal `"X-RateLimit-Limit"` |
| **RATE_LIMIT_HEADER_REMAINING** | Literal `"X-RateLimit-Remaining"` |
| **RATE_LIMIT_HEADER_RESET** | Literal `"X-RateLimit-Reset"` |
| **SENSITIVE_FIELDS** | Literal list `["user_id", "email", "phone", ...]` |
| **MONGODB_ROLES** | Literal dict `{"admin": [...], "read_write": [...], "read_only": [...]}` |

---

## Summary

- **From secret files:** Almost all runtime config (app identity, Flask, MongoDB, Redis, JWT, Stripe, Google, service keys, rate limit, WebSocket, Dutch game, etc.) **can** be supplied via files in `python_base_04/secrets/`; the deploy playbook copies that directory to the VPS so the container reads the same files.
- **Hardcoded:** Only a few symbols are code-only (DEBUG has no file, only Vault/Env; header names and SENSITIVE_FIELDS / MONGODB_ROLES are literals). Everything else is file > env > default (or Vault first for sensitive).

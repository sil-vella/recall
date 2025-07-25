import os
from tools.logger.custom_logging import custom_log

# Global VaultManager instance (initialized once)
_vault_manager = None

def get_vault_manager():
    """Get or create VaultManager instance with error handling."""
    global _vault_manager
    if _vault_manager is None:
        try:
            from core.managers.vault_manager import VaultManager
            _vault_manager = VaultManager()
            custom_log("✅ VaultManager initialized successfully for config")
        except Exception as e:
            custom_log(f"⚠️ VaultManager initialization failed: {e}", level="WARNING")
            _vault_manager = False  # Mark as failed to avoid retrying
    return _vault_manager if _vault_manager is not False else None

# Configuration Priority Architecture:
# - get_config_value(): Files > Vault > Environment > Default (for non-sensitive data with Vault integration)
# - get_sensitive_config_value(): Vault > Files > Environment > Default (for passwords, keys, secrets)
# - get_file_first_config_value(): Files > Environment > Default (for non-sensitive, no Vault)

# Helper to read secrets from files (returns None if not found)
def read_secret_file(secret_name: str) -> str:
    """Read secret from file system - checks multiple locations."""
    # Priority order for secret files:
    # 1. Kubernetes mounted secrets (/run/secrets/)
    # 2. Local development secrets (/app/secrets/)
    paths = [
        f"/run/secrets/{secret_name}",      # Kubernetes secrets
        f"/app/secrets/{secret_name}",      # Local development secrets
        f"./secrets/{secret_name}"          # Relative path fallback
    ]
    
    for path in paths:
        try:
            with open(path, 'r') as f:
                content = f.read().strip()
                if content:  # Only return non-empty content
                    custom_log(f"✅ Found secret '{secret_name}' in {path}")
                    return content
        except Exception:
            continue
    
    custom_log(f"🔍 Secret '{secret_name}' not found in any location")
    return None

def get_vault_secret(path: str, key: str) -> str:
    """Get secret from Vault with error handling."""
    try:
        vault = get_vault_manager()
        if vault:
            return vault.get_secret_value(path, key)
    except Exception as e:
        custom_log(f"Failed to get vault secret {path}/{key}: {e}")
    return None

def get_config_value(vault_path: str, vault_key: str, file_name: str = None, env_name: str = None, default_value: str = ""):
    """
    Get configuration value with priority: Files > Vault > Environment > Default
    
    Args:
        vault_path: Vault secret path (e.g., 'flask-app/mongodb')
        vault_key: Key within the vault secret (e.g., 'database_name')
        file_name: Secret file name (optional)
        env_name: Environment variable name (optional)
        default_value: Default value if all sources fail
    """
    
    # 1. Try secret files first (Kubernetes + local development)
    if file_name:
        file_value = read_secret_file(file_name)
        if file_value is not None and file_value != "vault_required":
            return file_value
        elif file_value == "vault_required":
            custom_log(f"Secret file {file_name} requires Vault - continuing to Vault")
    
    # 2. Try Vault (production secure source)
    if vault_path and vault_key:
        try:
            vault_value = get_vault_secret(vault_path, vault_key)
            if vault_value is not None:
                return vault_value
        except:
            pass  # Ignore Vault errors during initialization
    
    # 3. Try environment variable (skip if it's a security placeholder)
    if env_name:
        env_value = os.getenv(env_name)
        if env_value is not None and env_value != "vault_required":
            return env_value
        elif env_value == "vault_required":
            custom_log(f"Environment variable {env_name} requires Vault - skipping env fallback")
    
    # 4. Check if we have a security requirement
    if ((file_name and read_secret_file(file_name) == "vault_required") or 
        (env_name and os.getenv(env_name) == "vault_required")):
        custom_log(f"🚨 CRITICAL: {file_name or env_name} requires Vault but Vault is unavailable!", level="ERROR")
        # For critical security values, don't fall back to defaults
        if env_name in ["MONGODB_ROOT_PASSWORD", "JWT_SECRET_KEY", "ENCRYPTION_KEY", "REDIS_PASSWORD"]:
            return "VAULT_REQUIRED_BUT_UNAVAILABLE"
    
    # 5. Return default value
    return default_value

def get_sensitive_config_value(vault_path: str, vault_key: str, file_name: str = None, env_name: str = None, default_value: str = ""):
    """
    Get SENSITIVE configuration value with priority: Vault > Files > Environment > Default
    
    Use this for passwords, secrets, keys, and other sensitive data.
    
    Args:
        vault_path: Vault secret path (e.g., 'flask-app/mongodb')
        vault_key: Key within the vault secret (e.g., 'root_password')
        file_name: Secret file name (optional)
        env_name: Environment variable name (optional)
        default_value: Default value if all sources fail
    """
    
    # 1. Try Vault first (production secure source)
    if vault_path and vault_key:
        try:
            vault_value = get_vault_secret(vault_path, vault_key)
            if vault_value is not None:
                custom_log(f"✅ Sensitive config '{vault_key}' retrieved from Vault")
                return vault_value
        except Exception as e:
            custom_log(f"Vault lookup failed for {vault_path}/{vault_key}: {e}")
    
    # 2. Try secret files (Kubernetes + local development)
    if file_name:
        file_value = read_secret_file(file_name)
        if file_value is not None and file_value != "vault_required":
            custom_log(f"✅ Sensitive config '{file_name}' retrieved from secret file")
            return file_value
        elif file_value == "vault_required":
            custom_log(f"⚠️ Secret file {file_name} requires Vault but Vault unavailable - checking other sources", level="WARNING")
    
    # 3. Try environment variable (skip if it's a security placeholder)
    if env_name:
        env_value = os.getenv(env_name)
        if env_value is not None and env_value != "vault_required":
            custom_log(f"⚠️ Sensitive config '{env_name}' using environment variable (less secure)", level="WARNING")
            return env_value
        elif env_value == "vault_required":
            custom_log(f"Environment variable {env_name} requires Vault - skipping env fallback")
    
    # 4. Check if we have a security requirement failure
    if ((file_name and read_secret_file(file_name) == "vault_required") or 
        (env_name and os.getenv(env_name) == "vault_required")):
        custom_log(f"🚨 CRITICAL: {file_name or env_name} requires Vault but Vault is unavailable!", level="ERROR")
        return "VAULT_REQUIRED_BUT_UNAVAILABLE"
    
    # 5. Return default value (with warning for sensitive data)
    if default_value:
        custom_log(f"⚠️ Sensitive config using default value - NOT SECURE for production", level="WARNING")
    return default_value

def get_file_first_config_value(file_name: str, env_name: str, default_value: str = ""):
    """
    Get NON-SENSITIVE configuration value with priority: Files > Environment > Default
    
    Use this for regular configuration data (no Vault lookup).
    
    Args:
        file_name: Secret file name
        env_name: Environment variable name 
        default_value: Default value if all sources fail
    """
    
    # 1. Try secret files first (Kubernetes + local development)
    file_value = read_secret_file(file_name)
    if file_value is not None:
        custom_log(f"✅ Config '{file_name}' retrieved from secret file")
        return file_value
    
    # 2. Try environment variable
    env_value = os.getenv(env_name)
    if env_value is not None:
        custom_log(f"✅ Config '{env_name}' retrieved from environment")
        return env_value
    
    # 3. Return default value
    return default_value

def validate_critical_config():
    """Validate that critical configuration values are available and secure."""
    critical_failures = []
    
    # Check for Vault requirement failures in both files and environment variables
    critical_configs = [
        ("mongodb_root_password", "MONGODB_ROOT_PASSWORD", "Database authentication"),
        ("jwt_secret_key", "JWT_SECRET_KEY", "JWT token security"),
        ("encryption_key", "ENCRYPTION_KEY", "Data encryption"),
        ("redis_password", "REDIS_PASSWORD", "Redis authentication"),
        ("stripe_secret_key", "STRIPE_SECRET_KEY", "Stripe payment processing"),
        ("stripe_webhook_secret", "STRIPE_WEBHOOK_SECRET", "Stripe webhook security")
    ]
    
    for file_name, var_name, description in critical_configs:
        # Check secret file first
        file_value = read_secret_file(file_name)
        env_value = os.getenv(var_name, "")
        
        if file_value == "VAULT_REQUIRED_BUT_UNAVAILABLE" or env_value == "VAULT_REQUIRED_BUT_UNAVAILABLE":
            critical_failures.append(f"❌ {description}: Vault required but unavailable")
        elif file_value == "vault_required" or env_value == "vault_required":
            critical_failures.append(f"⚠️ {description}: Waiting for Vault initialization")
    
    if critical_failures:
        custom_log("🚨 CRITICAL CONFIGURATION ISSUES DETECTED:", level="ERROR")
        for failure in critical_failures:
            custom_log(f"   {failure}")
        
        # Check if Vault is accessible
        vault_status = False
        try:
            vault = get_vault_manager()
            vault_status = vault is not None
        except:
            pass
            
        if not vault_status:
            custom_log("🚨 VAULT IS UNAVAILABLE - APPLICATION CANNOT START SECURELY", level="ERROR")
            custom_log("🔧 RESOLUTION: Ensure Vault is accessible and AppRole credentials are valid")
            return False
    
    return True

def get_vault_status():
    """Get current Vault integration status for debugging."""
    try:
        vault = get_vault_manager()
        if vault:
            return {
                "status": "connected",
                "connection_info": vault.get_connection_info(),
                "health": vault.health_check()
            }
        else:
            return {
                "status": "unavailable",
                "reason": "VaultManager initialization failed or not configured"
            }
    except Exception as e:
        return {
            "status": "error",
            "reason": f"Error getting vault status: {e}"
        }

def get_security_status(mongodb_password=None, jwt_secret=None, redis_password=None, stripe_secret=None, stripe_webhook_secret=None):
    """Get current security configuration status."""
    vault_status = get_vault_status()
    
    security_info = {
        "vault_status": vault_status["status"],
        "vault_message": vault_status.get("reason", "Vault operational"),
        "sources": {},
        "security_level": "unknown"
    }
    
    # Use provided values or get them using sensitive config priority (Vault first)
    if mongodb_password is None:
        mongodb_password = get_sensitive_config_value("flask-app/mongodb", "root_password", "mongodb_root_password", "MONGODB_ROOT_PASSWORD", "rootpassword")
    if jwt_secret is None:
        jwt_secret = get_sensitive_config_value("flask-app/app", "secret_key", "jwt_secret_key", "JWT_SECRET_KEY", "your-super-secret-key-change-in-production")
    if redis_password is None:
        redis_password = get_sensitive_config_value("flask-app/redis", "password", "redis_password", "REDIS_PASSWORD", "")
    if stripe_secret is None:
        stripe_secret = get_sensitive_config_value("flask-app/stripe", "secret_key", "stripe_secret_key", "STRIPE_SECRET_KEY", "")
    if stripe_webhook_secret is None:
        stripe_webhook_secret = get_sensitive_config_value("flask-app/stripe", "webhook_secret", "stripe_webhook_secret", "STRIPE_WEBHOOK_SECRET", "")
    
    # Check source of critical values
    critical_configs = [
        ("mongodb_password", mongodb_password, "mongodb_root_password"),
        ("jwt_secret", jwt_secret, "jwt_secret_key"),
        ("redis_password", redis_password, "redis_password"),
        ("stripe_secret", stripe_secret, "stripe_secret_key"),
        ("stripe_webhook_secret", stripe_webhook_secret, "stripe_webhook_secret")
    ]
    
    vault_secured = 0
    file_secured = 0
    total_critical = len(critical_configs)
    
    for name, value, file_name in critical_configs:
        file_value = read_secret_file(file_name)
        
        if value == "VAULT_REQUIRED_BUT_UNAVAILABLE":
            security_info["sources"][name] = "❌ VAULT REQUIRED BUT UNAVAILABLE"
        elif value == "vault_required":
            security_info["sources"][name] = "⚠️ VAULT REQUIRED (waiting)"
        elif file_value and value == file_value:
            security_info["sources"][name] = "📁 Secret file (local)"
            file_secured += 1
        elif vault_status["status"] == "connected" and value not in ["", "your-super-secret-key-change-in-production"]:
            security_info["sources"][name] = "✅ Vault (secure)"
            vault_secured += 1
        elif value in ["", "your-super-secret-key-change-in-production"]:
            security_info["sources"][name] = "🔧 Default/Empty (development)"
        else:
            security_info["sources"][name] = "🔧 Environment fallback"
    
    # Determine security level
    total_secured = vault_secured + file_secured
    
    if vault_secured == total_critical:
        security_info["security_level"] = "high"
    elif total_secured == total_critical:
        security_info["security_level"] = "medium-high"  # All secured but via files
    elif vault_secured > 0:
        security_info["security_level"] = "medium"
    elif file_secured > 0:
        security_info["security_level"] = "medium-low"  # Some file security
    elif any("VAULT_REQUIRED_BUT_UNAVAILABLE" in str(v) for v in security_info["sources"].values()):
        security_info["security_level"] = "critical"
    else:
        security_info["security_level"] = "low"
    
    return security_info

class Config:
     # Debug mode
    DEBUG = get_config_value("flask-app/app", "debug", None, "FLASK_DEBUG", "False").lower() in ("true", "1")

    # Application Identity Configuration
    APP_ID = get_file_first_config_value("app_id", "APP_ID", "external_app_001")
    APP_NAME = get_file_first_config_value("app_name", "APP_NAME", "External Application")
    APP_VERSION = get_file_first_config_value("app_version", "APP_VERSION", "1.0.0")

    # App URL Configuration
    APP_URL = get_file_first_config_value("app_url", "APP_URL", "http://localhost:5000")
    
    # Flask Configuration
    FLASK_SERVICE_NAME = get_config_value("flask-app/app", "service_name", "flask_service_name", "FLASK_SERVICE_NAME", "flask")
    FLASK_PORT = int(get_config_value("flask-app/app", "port", "flask_port", "FLASK_PORT", "5000"))
    PYTHONPATH = get_config_value(None, None, "pythonpath", "PYTHONPATH", "/app")
    FLASK_ENV = get_config_value("flask-app/app", "environment", None, "FLASK_ENV", "development")
    
    # External Credit System Configuration
    CREDIT_SYSTEM_URL = get_file_first_config_value("credit_system_url", "CREDIT_SYSTEM_URL", "http://localhost:8000")
    CREDIT_SYSTEM_API_KEY = get_file_first_config_value("credit_system_api_key", "CREDIT_SYSTEM_API_KEY", "")

    # Vault Configuration
    VAULT_TOKEN_FILE = get_file_first_config_value("vault_token_file", "VAULT_TOKEN_FILE", "/vault/secrets/token")
    DB_CREDS_FILE = get_file_first_config_value("db_creds_file", "DB_CREDS_FILE", "/vault/secrets/flask-creds")
    VAULT_ADDR = get_file_first_config_value("vault_addr", "VAULT_ADDR", "http://vault-proxy:8200")
    VAULT_AUTH_PATH = get_file_first_config_value("vault_auth_path", "VAULT_AUTH_PATH", "auth/kubernetes")
    VAULT_ROLE = get_file_first_config_value("vault_role", "VAULT_ROLE", "flask-app")

    # MongoDB Configuration
    MONGODB_SERVICE_NAME = get_config_value("flask-app/mongodb", "service_name", "mongodb_service_name", "MONGODB_SERVICE_NAME", "mongodb")
    MONGODB_ROOT_USER = get_config_value("flask-app/mongodb", "root_user", "mongodb_root_user", "MONGODB_ROOT_USER", "root")
    MONGODB_ROOT_PASSWORD = get_sensitive_config_value("flask-app/mongodb", "root_password", "mongodb_root_password", "MONGODB_ROOT_PASSWORD", "rootpassword")
    MONGODB_USER = get_config_value("flask-app/mongodb", "user", "mongodb_user", "MONGODB_USER", "external_app_user")
    MONGODB_PASSWORD = get_sensitive_config_value("flask-app/mongodb", "user_password", "mongodb_user_password", "MONGODB_PASSWORD", "external_app_password")
    MONGODB_DB_NAME = get_config_value("flask-app/mongodb", "database_name", "mongodb_db_name", "MONGODB_DB_NAME", "external_system")
    MONGODB_PORT = int(get_config_value("flask-app/mongodb", "port", "mongodb_port", "MONGODB_PORT", "27017"))

    # Redis Configuration
    REDIS_SERVICE_NAME = get_config_value("flask-app/redis", "service_name", "redis_service_name", "REDIS_SERVICE_NAME", "redis")
    REDIS_HOST = get_config_value("flask-app/redis", "host", "redis_host", "REDIS_HOST", "redis-master-master.flask-app.svc.cluster.local")
    REDIS_PORT = int(get_config_value("flask-app/redis", "port", "redis_port", "REDIS_PORT", "6379"))
    REDIS_PASSWORD = get_sensitive_config_value("flask-app/redis", "password", "redis_password", "REDIS_PASSWORD", "")
    REDIS_DB = int(get_file_first_config_value("redis_db", "REDIS_DB", "0"))
    REDIS_USE_SSL = get_file_first_config_value("redis_use_ssl", "REDIS_USE_SSL", "false").lower() == "true"
    REDIS_SSL_VERIFY_MODE = get_file_first_config_value("redis_ssl_verify_mode", "REDIS_SSL_VERIFY_MODE", "required")
    REDIS_SOCKET_TIMEOUT = int(get_file_first_config_value("redis_socket_timeout", "REDIS_SOCKET_TIMEOUT", "5"))
    REDIS_SOCKET_CONNECT_TIMEOUT = int(get_file_first_config_value("redis_socket_connect_timeout", "REDIS_SOCKET_CONNECT_TIMEOUT", "5"))
    REDIS_RETRY_ON_TIMEOUT = get_file_first_config_value("redis_retry_on_timeout", "REDIS_RETRY_ON_TIMEOUT", "true").lower() == "true"
    REDIS_MAX_CONNECTIONS = int(get_file_first_config_value("redis_max_connections", "REDIS_MAX_CONNECTIONS", "10"))
    REDIS_MAX_RETRIES = int(get_file_first_config_value("redis_max_retries", "REDIS_MAX_RETRIES", "3"))
    RATE_LIMIT_STORAGE_URL = get_file_first_config_value("rate_limit_storage_url", "RATE_LIMIT_STORAGE_URL", f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}")
    # Stripe Configuration (Sensitive - Vault priority)
    STRIPE_SECRET_KEY = get_sensitive_config_value("flask-app/stripe", "secret_key", "stripe_secret_key", "STRIPE_SECRET_KEY", "")
    STRIPE_PUBLISHABLE_KEY = get_sensitive_config_value("flask-app/stripe", "publishable_key", "stripe_publishable_key", "STRIPE_PUBLISHABLE_KEY", "")
    STRIPE_WEBHOOK_SECRET = get_sensitive_config_value("flask-app/stripe", "webhook_secret", "stripe_webhook_secret", "STRIPE_WEBHOOK_SECRET", "")
    STRIPE_API_VERSION = get_file_first_config_value("stripe_api_version", "STRIPE_API_VERSION", "2023-10-16")

    # Google Play Developer API Configuration
    GOOGLE_PLAY_PACKAGE_NAME = get_file_first_config_value("google_play_package_name", "GOOGLE_PLAY_PACKAGE_NAME", "com.yourcompany.yourapp")
    GOOGLE_PLAY_SERVICE_ACCOUNT_FILE = get_file_first_config_value("google_play_service_account", "GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", "secrets/google_play_service_account")
    GOOGLE_PLAY_API_QUOTA_LIMIT = int(get_file_first_config_value("google_play_api_quota_limit", "GOOGLE_PLAY_API_QUOTA_LIMIT", "1000"))
    GOOGLE_PLAY_SYNC_INTERVAL_HOURS = int(get_file_first_config_value("google_play_sync_interval_hours", "GOOGLE_PLAY_SYNC_INTERVAL_HOURS", "24"))

    # JWT Configuration
    JWT_SECRET_KEY = get_sensitive_config_value("flask-app/app", "secret_key", "jwt_secret_key", "JWT_SECRET_KEY", "your-super-secret-key-change-in-production")
    JWT_ACCESS_TOKEN_EXPIRES = int(get_file_first_config_value("jwt_access_token_expires", "JWT_ACCESS_TOKEN_EXPIRES", "3600"))  # 1 hour in seconds
    JWT_REFRESH_TOKEN_EXPIRES = int(get_file_first_config_value("jwt_refresh_token_expires", "JWT_REFRESH_TOKEN_EXPIRES", "604800"))  # 7 days in seconds
    JWT_ALGORITHM = get_file_first_config_value("jwt_algorithm", "JWT_ALGORITHM", "HS256")
    JWT_TOKEN_TYPE = get_file_first_config_value("jwt_token_type", "JWT_TOKEN_TYPE", "bearer")
    JWT_HEADER_NAME = get_file_first_config_value("jwt_header_name", "JWT_HEADER_NAME", "Authorization")
    JWT_HEADER_TYPE = get_file_first_config_value("jwt_header_type", "JWT_HEADER_TYPE", "Bearer")
    JWT_QUERY_STRING_NAME = get_file_first_config_value("jwt_query_string_name", "JWT_QUERY_STRING_NAME", "token")
    JWT_QUERY_STRING_VALUE_PREFIX = get_file_first_config_value("jwt_query_string_value_prefix", "JWT_QUERY_STRING_VALUE_PREFIX", "Bearer")
    JWT_COOKIE_NAME = get_file_first_config_value("jwt_cookie_name", "JWT_COOKIE_NAME", "access_token")
    JWT_COOKIE_CSRF_PROTECT = get_file_first_config_value("jwt_cookie_csrf_protect", "JWT_COOKIE_CSRF_PROTECT", "true").lower() == "true"
    JWT_COOKIE_SECURE = get_file_first_config_value("jwt_cookie_secure", "JWT_COOKIE_SECURE", "true").lower() == "true"
    JWT_COOKIE_SAMESITE = get_file_first_config_value("jwt_cookie_samesite", "JWT_COOKIE_SAMESITE", "Lax")
    JWT_COOKIE_DOMAIN = get_file_first_config_value("jwt_cookie_domain", "JWT_COOKIE_DOMAIN", None)
    JWT_COOKIE_PATH = get_file_first_config_value("jwt_cookie_path", "JWT_COOKIE_PATH", "/")
    JWT_COOKIE_MAX_AGE = int(get_file_first_config_value("jwt_cookie_max_age", "JWT_COOKIE_MAX_AGE", "3600"))  # 1 hour in seconds

    # Toggle SSL for PostgreSQL
    USE_SSL = get_file_first_config_value("use_ssl", "USE_SSL", "False").lower() in ("true", "1")

    # Database Pool Configuration
    DB_POOL_MIN_CONN = int(get_file_first_config_value("db_pool_min_conn", "DB_POOL_MIN_CONN", "1"))
    DB_POOL_MAX_CONN = int(get_file_first_config_value("db_pool_max_conn", "DB_POOL_MAX_CONN", "10"))
    
    # Connection Pool Security Settings
    DB_CONNECT_TIMEOUT = int(get_file_first_config_value("db_connect_timeout", "DB_CONNECT_TIMEOUT", "10"))  # Connection timeout in seconds
    DB_STATEMENT_TIMEOUT = int(get_file_first_config_value("db_statement_timeout", "DB_STATEMENT_TIMEOUT", "30000"))  # Statement timeout in milliseconds
    DB_KEEPALIVES = int(get_file_first_config_value("db_keepalives", "DB_KEEPALIVES", "1"))  # Enable keepalive
    DB_KEEPALIVES_IDLE = int(get_file_first_config_value("db_keepalives_idle", "DB_KEEPALIVES_IDLE", "30"))  # Idle timeout in seconds
    DB_KEEPALIVES_INTERVAL = int(get_file_first_config_value("db_keepalives_interval", "DB_KEEPALIVES_INTERVAL", "10"))  # Keepalive interval in seconds
    DB_KEEPALIVES_COUNT = int(get_file_first_config_value("db_keepalives_count", "DB_KEEPALIVES_COUNT", "5"))
    DB_MAX_CONNECTIONS_PER_USER = int(get_file_first_config_value("db_max_connections_per_user", "DB_MAX_CONNECTIONS_PER_USER", "5"))  # Maximum connections per user
    
    # Resource Protection
    DB_MAX_QUERY_SIZE = int(get_file_first_config_value("db_max_query_size", "DB_MAX_QUERY_SIZE", "10000"))  # Maximum query size in bytes
    DB_MAX_RESULT_SIZE = int(get_file_first_config_value("db_max_result_size", "DB_MAX_RESULT_SIZE", "1048576"))  # Maximum result size in bytes (1MB)
    
    # Connection Retry Settings
    DB_RETRY_COUNT = int(get_file_first_config_value("db_retry_count", "DB_RETRY_COUNT", "3"))  # Number of connection retry attempts
    DB_RETRY_DELAY = int(get_file_first_config_value("db_retry_delay", "DB_RETRY_DELAY", "1"))  # Delay between retries in seconds
    
    # Flask-Limiter: Redis backend for rate limiting
    RATE_LIMIT_ENABLED = get_file_first_config_value("rate_limit_enabled", "RATE_LIMIT_ENABLED", "false").lower() == "true"
    RATE_LIMIT_IP_REQUESTS = int(get_file_first_config_value("rate_limit_ip_requests", "RATE_LIMIT_IP_REQUESTS", "100"))  # Requests per window
    RATE_LIMIT_IP_WINDOW = int(get_file_first_config_value("rate_limit_ip_window", "RATE_LIMIT_IP_WINDOW", "60"))  # Window in seconds
    RATE_LIMIT_IP_PREFIX = get_file_first_config_value("rate_limit_ip_prefix", "RATE_LIMIT_IP_PREFIX", "rate_limit:ip")
    RATE_LIMIT_USER_REQUESTS = int(get_file_first_config_value("rate_limit_user_requests", "RATE_LIMIT_USER_REQUESTS", "1000"))  # Requests per window
    RATE_LIMIT_USER_WINDOW = int(get_file_first_config_value("rate_limit_user_window", "RATE_LIMIT_USER_WINDOW", "3600"))  # Window in seconds
    RATE_LIMIT_USER_PREFIX = get_file_first_config_value("rate_limit_user_prefix", "RATE_LIMIT_USER_PREFIX", "rate_limit:user")
    RATE_LIMIT_API_KEY_REQUESTS = int(get_file_first_config_value("rate_limit_api_key_requests", "RATE_LIMIT_API_KEY_REQUESTS", "10000"))  # Requests per window
    RATE_LIMIT_API_KEY_WINDOW = int(get_file_first_config_value("rate_limit_api_key_window", "RATE_LIMIT_API_KEY_WINDOW", "3600"))  # Window in seconds
    RATE_LIMIT_API_KEY_PREFIX = get_file_first_config_value("rate_limit_api_key_prefix", "RATE_LIMIT_API_KEY_PREFIX", "rate_limit:api_key")
    RATE_LIMIT_HEADERS_ENABLED = get_file_first_config_value("rate_limit_headers_enabled", "RATE_LIMIT_HEADERS_ENABLED", "true").lower() == "true"
    RATE_LIMIT_HEADER_LIMIT = "X-RateLimit-Limit"
    RATE_LIMIT_HEADER_REMAINING = "X-RateLimit-Remaining"
    RATE_LIMIT_HEADER_RESET = "X-RateLimit-Reset"

    # Auto-ban Configuration
    AUTO_BAN_ENABLED = get_file_first_config_value("auto_ban_enabled", "AUTO_BAN_ENABLED", "true").lower() == "true"
    AUTO_BAN_VIOLATIONS_THRESHOLD = int(get_file_first_config_value("auto_ban_violations_threshold", "AUTO_BAN_VIOLATIONS_THRESHOLD", "5"))  # Number of violations before ban
    AUTO_BAN_DURATION = int(get_file_first_config_value("auto_ban_duration", "AUTO_BAN_DURATION", "3600"))  # Ban duration in seconds (default 1 hour)
    AUTO_BAN_WINDOW = int(get_file_first_config_value("auto_ban_window", "AUTO_BAN_WINDOW", "300"))  # Window to track violations (default 5 minutes)
    AUTO_BAN_PREFIX = get_file_first_config_value("auto_ban_prefix", "AUTO_BAN_PREFIX", "ban")
    AUTO_BAN_VIOLATIONS_PREFIX = get_file_first_config_value("auto_ban_violations_prefix", "AUTO_BAN_VIOLATIONS_PREFIX", "violations")

    # Credit Amount Validation Settings
    CREDIT_MIN_AMOUNT = float(get_file_first_config_value("credit_min_amount", "CREDIT_MIN_AMOUNT", "0.01"))  # Minimum credit amount
    CREDIT_MAX_AMOUNT = float(get_file_first_config_value("credit_max_amount", "CREDIT_MAX_AMOUNT", "1000000.0"))  # Maximum credit amount
    CREDIT_PRECISION = int(get_file_first_config_value("credit_precision", "CREDIT_PRECISION", "2"))  # Number of decimal places allowed
    CREDIT_ALLOW_NEGATIVE = get_file_first_config_value("credit_allow_negative", "CREDIT_ALLOW_NEGATIVE", "false").lower() == "true"

    # Transaction Validation Settings
    MAX_METADATA_SIZE = int(get_file_first_config_value("max_metadata_size", "MAX_METADATA_SIZE", "1024"))  # Maximum metadata size in bytes
    MAX_REFERENCE_ID_LENGTH = int(get_file_first_config_value("max_reference_id_length", "MAX_REFERENCE_ID_LENGTH", "64"))  # Maximum reference ID length
    ALLOWED_TRANSACTION_TYPES = get_file_first_config_value("allowed_transaction_types", "ALLOWED_TRANSACTION_TYPES", "purchase,reward,burn,transfer,refund").split(",")

    # Transaction Integrity Settings
    TRANSACTION_WINDOW = int(get_file_first_config_value("transaction_window", "TRANSACTION_WINDOW", "3600"))  # Time window for replay attack prevention (in seconds)
    REQUIRE_TRANSACTION_ID = get_file_first_config_value("require_transaction_id", "REQUIRE_TRANSACTION_ID", "true").lower() == "true"  # Whether transaction IDs are required
    ENFORCE_BALANCE_VALIDATION = get_file_first_config_value("enforce_balance_validation", "ENFORCE_BALANCE_VALIDATION", "true").lower() == "true"  # Whether to enforce balance validation

    # Payload Validation Settings
    MAX_PAYLOAD_SIZE = int(get_file_first_config_value("max_payload_size", "MAX_PAYLOAD_SIZE", "1048576"))  # 1MB default
    MAX_NESTING_DEPTH = int(get_file_first_config_value("max_nesting_depth", "MAX_NESTING_DEPTH", "10"))  # Maximum nesting depth
    MAX_ARRAY_SIZE = int(get_file_first_config_value("max_array_size", "MAX_ARRAY_SIZE", "1000"))  # Maximum array size
    MAX_STRING_LENGTH = int(get_file_first_config_value("max_string_length", "MAX_STRING_LENGTH", "65536"))  # Maximum string length

    # Encryption settings
    ENCRYPTION_KEY = get_sensitive_config_value("flask-app/app", "encryption_key", "encryption_key", "ENCRYPTION_KEY", "development-encryption-key-change-in-production")
    ENCRYPTION_SALT = get_sensitive_config_value("flask-app/app", "encryption_salt", "encryption_salt", "ENCRYPTION_SALT", "default_salt_123")
    SENSITIVE_FIELDS = [
        "user_id",
        "email",
        "phone",
        "address",
        "credit_balance",
        "transaction_history"
    ]

    # MongoDB Advanced Configuration
    MONGODB_URI = get_file_first_config_value("mongodb_uri", "MONGODB_URI", "mongodb://localhost:27017/")
    MONGODB_AUTH_SOURCE = get_file_first_config_value("mongodb_auth_source", "MONGODB_AUTH_SOURCE", "admin")
    
    # MongoDB Role-Based Access Control
    MONGODB_ROLES = {
        "admin": ["readWriteAnyDatabase", "dbAdminAnyDatabase", "userAdminAnyDatabase"],
        "read_write": ["readWrite"],
        "read_only": ["read"]
    }
    
    # MongoDB Replica Set Configuration
    MONGODB_REPLICA_SET = get_file_first_config_value("mongodb_replica_set", "MONGODB_REPLICA_SET", "")
    MONGODB_READ_PREFERENCE = get_file_first_config_value("mongodb_read_preference", "MONGODB_READ_PREFERENCE", "primary")
    MONGODB_READ_CONCERN = get_file_first_config_value("mongodb_read_concern", "MONGODB_READ_CONCERN", "majority")
    MONGODB_WRITE_CONCERN = get_file_first_config_value("mongodb_write_concern", "MONGODB_WRITE_CONCERN", "majority")
    
    # MongoDB Connection Settings
    MONGODB_MAX_POOL_SIZE = int(get_file_first_config_value("mongodb_max_pool_size", "MONGODB_MAX_POOL_SIZE", "100"))
    MONGODB_MIN_POOL_SIZE = int(get_file_first_config_value("mongodb_min_pool_size", "MONGODB_MIN_POOL_SIZE", "10"))
    MONGODB_MAX_IDLE_TIME_MS = int(get_file_first_config_value("mongodb_max_idle_time_ms", "MONGODB_MAX_IDLE_TIME_MS", "60000"))
    MONGODB_SOCKET_TIMEOUT_MS = int(get_file_first_config_value("mongodb_socket_timeout_ms", "MONGODB_SOCKET_TIMEOUT_MS", "5000"))
    MONGODB_CONNECT_TIMEOUT_MS = int(get_file_first_config_value("mongodb_connect_timeout_ms", "MONGODB_CONNECT_TIMEOUT_MS", "5000"))
    
    # MongoDB SSL/TLS Settings
    MONGODB_SSL = get_file_first_config_value("mongodb_ssl", "MONGODB_SSL", "false").lower() == "true"
    MONGODB_SSL_CA_FILE = get_file_first_config_value("mongodb_ssl_ca_file", "MONGODB_SSL_CA_FILE", "")
    MONGODB_SSL_CERT_FILE = get_file_first_config_value("mongodb_ssl_cert_file", "MONGODB_SSL_CERT_FILE", "")
    MONGODB_SSL_KEY_FILE = get_file_first_config_value("mongodb_ssl_key_file", "MONGODB_SSL_KEY_FILE", "")
    MONGODB_SSL_ALLOW_INVALID_CERTIFICATES = get_file_first_config_value("mongodb_ssl_allow_invalid_certificates", "MONGODB_SSL_ALLOW_INVALID_CERTIFICATES", "false").lower() == "true"

    # WebSocket Configuration
    WS_ALLOWED_ORIGINS = get_file_first_config_value("ws_allowed_origins", "WS_ALLOWED_ORIGINS", "*").split(",")
    WS_MAX_PAYLOAD_SIZE = int(get_file_first_config_value("ws_max_payload_size", "WS_MAX_PAYLOAD_SIZE", "1048576"))  # 1MB default
    WS_PING_TIMEOUT = int(get_file_first_config_value("ws_ping_timeout", "WS_PING_TIMEOUT", "60"))  # 60 seconds
    WS_PING_INTERVAL = int(get_file_first_config_value("ws_ping_interval", "WS_PING_INTERVAL", "25"))  # 25 seconds
    WS_RATE_LIMIT_CONNECTIONS = int(get_file_first_config_value("ws_rate_limit_connections", "WS_RATE_LIMIT_CONNECTIONS", "100"))  # Max connections per window
    WS_RATE_LIMIT_MESSAGES = int(get_file_first_config_value("ws_rate_limit_messages", "WS_RATE_LIMIT_MESSAGES", "1000"))  # Max messages per window
    WS_RATE_LIMIT_WINDOW = int(get_file_first_config_value("ws_rate_limit_window", "WS_RATE_LIMIT_WINDOW", "60"))  # Rate limit window in seconds
    WS_ROOM_SIZE_LIMIT = int(get_file_first_config_value("ws_room_size_limit", "WS_ROOM_SIZE_LIMIT", "100"))  # Max users per room
    WS_ROOM_SIZE_CHECK_INTERVAL = int(get_file_first_config_value("ws_room_size_check_interval", "WS_ROOM_SIZE_CHECK_INTERVAL", "30"))  # Check interval in seconds
    WS_ROOM_TTL = int(get_file_first_config_value("ws_room_ttl", "WS_ROOM_TTL", "3600"))  # Room TTL in seconds (1 hour)
    WS_PRESENCE_CHECK_INTERVAL = int(get_file_first_config_value("ws_presence_check_interval", "WS_PRESENCE_CHECK_INTERVAL", "60"))  # Presence check interval in seconds
    WS_PRESENCE_TIMEOUT = int(get_file_first_config_value("ws_presence_timeout", "WS_PRESENCE_TIMEOUT", "300"))  # Presence timeout in seconds
    WS_PRESENCE_CLEANUP_INTERVAL = int(get_file_first_config_value("ws_presence_cleanup_interval", "WS_PRESENCE_CLEANUP_INTERVAL", "300"))  # Cleanup interval in seconds
    WS_SESSION_TTL = int(get_file_first_config_value("ws_session_ttl", "WS_SESSION_TTL", "3600"))  # Session TTL in seconds

    @classmethod
    def refresh_from_vault(cls):
        """Refresh configuration values from Vault after app initialization."""
        try:
            vault = get_vault_manager()
            if not vault:
                custom_log("VaultManager not available for refresh")
                return False
            
            # Refresh MongoDB config
            mongodb_secrets = vault.get_mongodb_secrets()
            if mongodb_secrets:
                cls.MONGODB_SERVICE_NAME = mongodb_secrets.get('service_name', cls.MONGODB_SERVICE_NAME)
                cls.MONGODB_ROOT_USER = mongodb_secrets.get('root_user', cls.MONGODB_ROOT_USER)
                cls.MONGODB_ROOT_PASSWORD = mongodb_secrets.get('root_password', cls.MONGODB_ROOT_PASSWORD)
                cls.MONGODB_USER = mongodb_secrets.get('user', cls.MONGODB_USER)
                cls.MONGODB_PASSWORD = mongodb_secrets.get('user_password', cls.MONGODB_PASSWORD)
                cls.MONGODB_DB_NAME = mongodb_secrets.get('database_name', cls.MONGODB_DB_NAME)
                cls.MONGODB_PORT = int(mongodb_secrets.get('port', cls.MONGODB_PORT))
                custom_log("✅ MongoDB config refreshed from Vault")
            
            # Refresh Redis config
            redis_secrets = vault.get_redis_secrets()
            if redis_secrets:
                cls.REDIS_SERVICE_NAME = redis_secrets.get('service_name', cls.REDIS_SERVICE_NAME)
                cls.REDIS_HOST = redis_secrets.get('host', cls.REDIS_HOST)
                cls.REDIS_PORT = int(redis_secrets.get('port', cls.REDIS_PORT))
                cls.REDIS_PASSWORD = redis_secrets.get('password', cls.REDIS_PASSWORD)
                custom_log("✅ Redis config refreshed from Vault")
            
            # Refresh Flask app config
            app_secrets = vault.get_app_secrets()
            if app_secrets:
                cls.JWT_SECRET_KEY = app_secrets.get('secret_key', cls.JWT_SECRET_KEY)
                cls.FLASK_ENV = app_secrets.get('environment', cls.FLASK_ENV)
                cls.DEBUG = app_secrets.get('debug', str(cls.DEBUG)).lower() in ('true', '1')
                custom_log("✅ Flask app config refreshed from Vault")
            
            # Refresh Stripe config
            stripe_secrets = vault.get_stripe_secrets()
            if stripe_secrets:
                cls.STRIPE_SECRET_KEY = stripe_secrets.get('secret_key', cls.STRIPE_SECRET_KEY)
                cls.STRIPE_PUBLISHABLE_KEY = stripe_secrets.get('publishable_key', cls.STRIPE_PUBLISHABLE_KEY)
                cls.STRIPE_WEBHOOK_SECRET = stripe_secrets.get('webhook_secret', cls.STRIPE_WEBHOOK_SECRET)
                custom_log("✅ Stripe config refreshed from Vault")
            
            return True
            
        except Exception as e:
            custom_log(f"Failed to refresh config from Vault: {e}")
            return False

    @classmethod
    def set_credit_system_api_key(cls, api_key: str):
        """Dynamically set the credit system API key."""
        cls.CREDIT_SYSTEM_API_KEY = api_key
        custom_log(f"✅ Credit system API key set: {api_key[:16]}...")
    
    @classmethod
    def get_credit_system_api_key(cls) -> str:
        """Get the credit system API key, generate if empty."""
        if not cls.CREDIT_SYSTEM_API_KEY or cls.CREDIT_SYSTEM_API_KEY == "":
            # Try to generate API key automatically using unified APIKeyManager
            from core.managers.api_key_manager import APIKeyManager
            api_key_manager = APIKeyManager()
            api_key = api_key_manager.generate_api_key_from_credit_system()
            if api_key:
                cls.set_credit_system_api_key(api_key)
                return api_key
            else:
                custom_log("⚠️ Failed to generate API key automatically")
                return ""
        return cls.CREDIT_SYSTEM_API_KEY



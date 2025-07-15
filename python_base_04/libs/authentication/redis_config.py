from utils.config.config import Config

# Redis configuration
REDIS_URL = f"redis://{Config.REDIS_HOST}:{Config.REDIS_PORT}/{Config.REDIS_DB}"
REDIS_PASSWORD = Config.REDIS_PASSWORD
REDIS_USE_SSL = Config.REDIS_USE_SSL
REDIS_SSL_VERIFY_MODE = Config.REDIS_SSL_VERIFY_MODE

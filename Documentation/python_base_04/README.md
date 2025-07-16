# Python Base 04 - Comprehensive Documentation

## Project Overview

Python Base 04 is a sophisticated Flask-based microservices framework designed for building scalable, secure, and maintainable backend applications. The project serves as a foundation for developing enterprise-level Python applications with advanced features including state management, authentication, rate limiting, and comprehensive monitoring.

### Key Features

- **Modular Architecture**: Clean separation of concerns with module-based development
- **Advanced State Management**: Centralized state management with Redis and database persistence
- **Comprehensive Authentication**: JWT-based authentication with API key management
- **Rate Limiting**: Multi-level rate limiting (IP, user, API key)
- **Security Integration**: HashiCorp Vault integration for secure secret management
- **WebSocket Support**: Real-time communication capabilities
- **Action Discovery**: Dynamic action registration and execution
- **Monitoring & Metrics**: Prometheus integration with custom metrics
- **Database Management**: MongoDB and PostgreSQL support with connection pooling
- **Redis Integration**: Caching, session management, and pub/sub capabilities

## Project Structure

```
python_base_04/
├── app.py                          # Main Flask application entry point
├── requirements.txt                 # Python dependencies
├── Dockerfile                      # Container configuration
├── core/                           # Core application components
│   ├── managers/                   # Manager classes for different services
│   │   ├── app_manager.py         # Main application orchestrator
│   │   ├── state_manager.py       # State management system
│   │   ├── database_manager.py    # Database operations
│   │   ├── redis_manager.py       # Redis operations
│   │   ├── jwt_manager.py         # JWT authentication
│   │   ├── api_key_manager.py     # API key management
│   │   ├── vault_manager.py       # Vault integration
│   │   ├── rate_limiter_manager.py # Rate limiting
│   │   ├── action_discovery_manager.py # Action discovery
│   │   └── websockets/            # WebSocket management
│   ├── modules/                    # Feature modules
│   │   ├── base_module.py         # Base module class
│   │   ├── user_management_module/ # User management
│   │   ├── credit_system_module/  # Credit system
│   │   ├── wallet_module/         # Wallet functionality
│   │   ├── transactions_module/   # Transaction handling
│   │   ├── communications_module/ # Communication features
│   │   ├── stripe_module/         # Stripe integration
│   │   └── system_actions_module/ # System actions
│   ├── handlers/                   # Request handlers
│   ├── validators/                 # Data validation
│   ├── monitoring/                 # Monitoring and metrics
│   └── metrics.py                  # Metrics configuration
├── utils/                          # Utility functions
│   ├── config/                     # Configuration management
│   ├── validation/                 # Validation utilities
│   └── exceptions/                 # Custom exceptions
├── tools/                          # Development tools
│   ├── logger/                     # Logging system
│   ├── error_handling/             # Error handling utilities
│   └── tests/                      # Test utilities
├── secrets/                        # Secret files (development)
├── static/                         # Static files
├── grafana/                        # Grafana dashboards
├── redis_data/                     # Redis data directory
└── libs/                          # External libraries
```

## Technology Stack

### Core Dependencies

- **Flask**: ^3.1.0 - Web framework
- **Flask-SQLAlchemy**: ^2.5.1 - Database ORM
- **Flask-Limiter**: ^2.7.0 - Rate limiting
- **Flask-CORS**: ^3.0.10 - Cross-origin resource sharing
- **Flask-SocketIO**: ^5.3.6 - WebSocket support
- **PyJWT**: ^2.6.0 - JWT token handling
- **bcrypt**: ^4.3.0 - Password hashing
- **requests**: ^2.31.0 - HTTP client
- **gunicorn**: ^20.1.0 - WSGI server
- **python-dotenv**: ^1.0.0 - Environment management

### Database & Caching

- **psycopg2-binary**: ^2.9.6 - PostgreSQL adapter
- **pymongo**: ^4.6.1 - MongoDB driver
- **redis**: ^5.2.1 - Redis client

### Security & Monitoring

- **cryptography**: >=41.0.0 - Encryption utilities
- **prometheus-client**: ^0.19.0 - Metrics collection
- **prometheus-flask-exporter**: ^0.23.2 - Flask metrics
- **APScheduler**: ^3.10.4 - Task scheduling
- **PyYAML**: ^6.0.1 - YAML processing
- **stripe**: ^7.11.0 - Payment processing

## Architecture Overview

### 1. Manager Pattern
The application uses a manager-based architecture where each manager handles a specific domain:

- **AppManager**: Application lifecycle and orchestration
- **StateManager**: Centralized state management
- **DatabaseManager**: Database operations and connection pooling
- **RedisManager**: Redis operations and caching
- **JWTManager**: JWT token management
- **ApiKeyManager**: API key authentication
- **VaultManager**: Secure secret management
- **RateLimiterManager**: Multi-level rate limiting
- **ActionDiscoveryManager**: Dynamic action registration

### 2. Module System
Features are organized into modules that encapsulate related functionality:

- Each module extends `BaseModule`
- Modules can declare dependencies on other modules
- Automatic registration and initialization
- Health monitoring and status reporting

### 3. Service Layer
Core services provide essential functionality:

- **Configuration Management**: Environment-based with Vault integration
- **Logging System**: Structured logging with rotation
- **Error Handling**: Comprehensive error handling and recovery
- **Validation**: Input validation and sanitization

## Getting Started

### Prerequisites

1. Python 3.9+
2. Docker and Docker Compose
3. Redis server
4. MongoDB or PostgreSQL
5. HashiCorp Vault (optional, for production)

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. Initialize the application:
   ```bash
   python app.py
   ```

### Configuration

The application supports multiple configuration sources:

1. **Environment Variables**: Direct environment variable configuration
2. **Secret Files**: Kubernetes-style secret files
3. **HashiCorp Vault**: Secure secret management (production)
4. **Configuration Files**: YAML-based configuration

#### Configuration Priority

1. **Secret Files** (Kubernetes secrets)
2. **Vault** (production secure source)
3. **Environment Variables**
4. **Default Values**

### Running the Application

#### Development Mode
```bash
python app.py
```

#### Production Mode
```bash
gunicorn --bind 0.0.0.0:5001 --workers 4 --timeout 120 app:app
```

#### Docker Deployment
```bash
docker build -t python-base-04 .
docker run -p 5001:5001 python-base-04
```

## Development Guidelines

### Code Style

- Follow PEP 8 conventions
- Use meaningful variable and function names
- Implement comprehensive error handling
- Add documentation for public APIs

### Module Development

1. Extend `BaseModule` class
2. Implement required methods:
   - `initialize()`: Module initialization
   - `register_routes()`: Route registration
   - `configure()`: Module configuration
   - `dispose()`: Resource cleanup
3. Declare dependencies in `declare_dependencies()`
4. Implement health checks in `health_check()`

### State Management

- Use StateManager for all state operations
- Register states with proper types and transitions
- Implement state validation and callbacks
- Handle state persistence and recovery

### Authentication

- Use JWTManager for JWT token operations
- Implement API key authentication with ApiKeyManager
- Configure proper token expiration and refresh
- Implement secure password handling

### API Development

- Use ActionDiscoveryManager for dynamic action registration
- Implement proper input validation
- Add rate limiting where appropriate
- Include comprehensive error handling

## API Endpoints

### Health Check
```
GET /health
```
Comprehensive health check including database, Redis, and module status.

### Action Discovery
```
GET /actions
GET /api-auth/actions
```
List all available actions (public and authenticated).

### Action Execution
```
GET/POST /actions/<action_name>/<args>
GET/POST /api-auth/actions/<action_name>/<args>
```
Execute actions with URL arguments and request data.

### Module Status
```
GET /modules/status
GET /modules/<module_key>/health
```
Check module health and status.

## Security Features

### Authentication

- **JWT Tokens**: Secure token-based authentication
- **API Keys**: API key authentication for service-to-service communication
- **Password Hashing**: bcrypt-based password security
- **Token Refresh**: Automatic token refresh mechanism

### Rate Limiting

- **IP-based**: Rate limiting by IP address
- **User-based**: Rate limiting by authenticated user
- **API Key-based**: Rate limiting by API key
- **Auto-ban**: Automatic banning for repeated violations

### Data Protection

- **Encryption**: Field-level encryption for sensitive data
- **Vault Integration**: Secure secret management
- **Input Validation**: Comprehensive input sanitization
- **SQL Injection Protection**: Parameterized queries

## Monitoring and Observability

### Metrics

- **Prometheus Integration**: Custom metrics collection
- **Flask Metrics**: Request/response metrics
- **Database Metrics**: Connection pool and query metrics
- **Redis Metrics**: Cache hit/miss ratios

### Logging

- **Structured Logging**: JSON-formatted logs
- **Log Rotation**: Automatic log file rotation
- **Multiple Loggers**: Separate loggers for different concerns
- **Audit Logging**: Security event logging

### Health Checks

- **Application Health**: Overall application status
- **Database Health**: Database connectivity and performance
- **Redis Health**: Redis connectivity and performance
- **Module Health**: Individual module status

## Deployment

### Docker Deployment

```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 5001
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "app:app"]
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-base-04
spec:
  replicas: 3
  selector:
    matchLabels:
      app: python-base-04
  template:
    metadata:
      labels:
        app: python-base-04
    spec:
      containers:
      - name: python-base-04
        image: python-base-04:latest
        ports:
        - containerPort: 5001
        env:
        - name: FLASK_ENV
          value: "production"
```

### Environment Configuration

#### Development
```bash
FLASK_ENV=development
FLASK_DEBUG=true
MONGODB_URI=mongodb://localhost:27017/
REDIS_HOST=localhost
```

#### Production
```bash
FLASK_ENV=production
VAULT_ADDR=http://vault:8200
MONGODB_URI=mongodb://mongodb:27017/
REDIS_HOST=redis-master
```

## Testing

### Unit Tests
```bash
python -m pytest tests/unit/
```

### Integration Tests
```bash
python -m pytest tests/integration/
```

### API Tests
```bash
python -m pytest tests/api/
```

## Troubleshooting

### Common Issues

1. **Database Connection**: Check MongoDB/PostgreSQL connectivity
2. **Redis Connection**: Verify Redis server is running
3. **Vault Integration**: Ensure Vault is accessible and configured
4. **Rate Limiting**: Check Redis for rate limit data
5. **Authentication**: Verify JWT tokens and API keys

### Debug Tools

- **Health Check**: `/health` endpoint for system status
- **Module Status**: `/modules/status` for module health
- **Logs**: Check application logs for detailed information
- **Metrics**: Prometheus metrics for performance monitoring

## Contributing

1. Follow the established architecture patterns
2. Add comprehensive documentation
3. Include tests for new features
4. Update this documentation as needed
5. Follow security best practices

## License

This project is proprietary and confidential. All rights reserved.

---

For detailed documentation on specific components, see the individual documentation files in this directory. 
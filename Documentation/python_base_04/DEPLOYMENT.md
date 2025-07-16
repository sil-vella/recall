# Deployment Documentation - Python Base 04

## Overview

This document provides comprehensive deployment instructions for the Python Base 04 framework across different environments and platforms.

## Deployment Options

### 1. Local Development Deployment

#### Prerequisites

- Python 3.9+
- Redis server
- MongoDB or PostgreSQL
- Virtual environment (recommended)

#### Setup Instructions

1. **Clone and Setup**:
   ```bash
   git clone <repository-url>
   cd python_base_04
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. **Environment Configuration**:
   ```bash
   # Create environment file
   cp .env.example .env
   
   # Edit .env with your configuration
   FLASK_ENV=development
   FLASK_DEBUG=true
   MONGODB_URI=mongodb://localhost:27017/
   REDIS_HOST=localhost
   REDIS_PORT=6379
   JWT_SECRET_KEY=your-development-secret-key
   ```

3. **Database Setup**:
   ```bash
   # Start Redis
   redis-server
   
   # Start MongoDB (if using MongoDB)
   mongod --dbpath /path/to/data/db
   
   # Or start PostgreSQL (if using PostgreSQL)
   sudo -u postgres createdb python_base_04
   ```

4. **Run Application**:
   ```bash
   python app.py
   ```

#### Development Features

- **Hot Reloading**: Automatic reload on code changes
- **Debug Mode**: Detailed error messages and stack traces
- **Local Logging**: Logs written to local files
- **Development Secrets**: File-based secret management

### 2. Docker Deployment

#### Single Container Deployment

1. **Build Image**:
   ```bash
   docker build -t python-base-04 .
   ```

2. **Run Container**:
   ```bash
   docker run -d \
     --name python-base-04 \
     -p 5001:5001 \
     -e FLASK_ENV=production \
     -e MONGODB_URI=mongodb://mongodb:27017/ \
     -e REDIS_HOST=redis \
     python-base-04
   ```

#### Docker Compose Deployment

1. **Create docker-compose.yml**:
   ```yaml
   version: '3.8'
   
   services:
     app:
       build: .
       ports:
         - "5001:5001"
       environment:
         - FLASK_ENV=production
         - MONGODB_URI=mongodb://mongodb:27017/
         - REDIS_HOST=redis
       depends_on:
         - mongodb
         - redis
       volumes:
         - ./logs:/app/logs
         - ./secrets:/app/secrets
       restart: unless-stopped
       healthcheck:
         test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
         interval: 30s
         timeout: 10s
         retries: 3
         start_period: 60s
   
     mongodb:
       image: mongo:6.0
       ports:
         - "27017:27017"
       environment:
         - MONGO_INITDB_ROOT_USERNAME=root
         - MONGO_INITDB_ROOT_PASSWORD=rootpassword
       volumes:
         - mongodb_data:/data/db
       restart: unless-stopped
   
     redis:
       image: redis:7-alpine
       ports:
         - "6379:6379"
       volumes:
         - redis_data:/data
       restart: unless-stopped
   
     vault:
       image: vault:1.15
       ports:
         - "8200:8200"
       environment:
         - VAULT_DEV_ROOT_TOKEN_ID=dev-token
         - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
       cap_add:
         - IPC_LOCK
       restart: unless-stopped
   
   volumes:
     mongodb_data:
     redis_data:
   ```

2. **Deploy with Docker Compose**:
   ```bash
   docker-compose up -d
   ```

3. **Check Status**:
   ```bash
   docker-compose ps
   docker-compose logs app
   ```

### 3. Kubernetes Deployment

#### Prerequisites

- Kubernetes cluster (1.20+)
- kubectl configured
- Helm (optional)

#### Basic Kubernetes Deployment

1. **Create Namespace**:
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: python-base-04
   ```

2. **Create ConfigMap**:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: python-base-04-config
     namespace: python-base-04
   data:
     FLASK_ENV: "production"
     MONGODB_URI: "mongodb://mongodb:27017/"
     REDIS_HOST: "redis"
     REDIS_PORT: "6379"
     APP_NAME: "Python Base 04"
     APP_VERSION: "1.0.0"
   ```

3. **Create Secret**:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: python-base-04-secrets
     namespace: python-base-04
   type: Opaque
   data:
     JWT_SECRET_KEY: <base64-encoded-secret>
     MONGODB_ROOT_PASSWORD: <base64-encoded-password>
     REDIS_PASSWORD: <base64-encoded-password>
   ```

4. **Create Deployment**:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: python-base-04
     namespace: python-base-04
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
           envFrom:
           - configMapRef:
               name: python-base-04-config
           - secretRef:
               name: python-base-04-secrets
           resources:
             requests:
               memory: "256Mi"
               cpu: "250m"
             limits:
               memory: "512Mi"
               cpu: "500m"
           livenessProbe:
             httpGet:
               path: /health
               port: 5001
             initialDelaySeconds: 60
             periodSeconds: 30
             timeoutSeconds: 10
             failureThreshold: 3
           readinessProbe:
             httpGet:
               path: /health
               port: 5001
             initialDelaySeconds: 30
             periodSeconds: 10
             timeoutSeconds: 5
             failureThreshold: 3
           volumeMounts:
           - name: logs
             mountPath: /app/logs
           - name: secrets
             mountPath: /app/secrets
         volumes:
         - name: logs
           emptyDir: {}
         - name: secrets
           secret:
             secretName: python-base-04-secrets
   ```

5. **Create Service**:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: python-base-04-service
     namespace: python-base-04
   spec:
     selector:
       app: python-base-04
     ports:
     - protocol: TCP
       port: 80
       targetPort: 5001
     type: ClusterIP
   ```

6. **Create Ingress**:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: python-base-04-ingress
     namespace: python-base-04
     annotations:
       nginx.ingress.kubernetes.io/rewrite-target: /
   spec:
     rules:
     - host: python-base-04.example.com
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: python-base-04-service
               port:
                 number: 80
   ```

#### Deploy to Kubernetes

```bash
# Apply all resources
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml

# Check deployment status
kubectl get pods -n python-base-04
kubectl get services -n python-base-04
kubectl get ingress -n python-base-04
```

### 4. Production Deployment

#### Environment Configuration

1. **Production Environment Variables**:
   ```bash
   # Application
   FLASK_ENV=production
   FLASK_DEBUG=false
   APP_NAME=Python Base 04 Production
   APP_VERSION=1.0.0
   
   # Database
   MONGODB_URI=mongodb://mongodb:27017/
   MONGODB_ROOT_USER=root
   MONGODB_ROOT_PASSWORD=<secure-password>
   MONGODB_DB_NAME=production_db
   
   # Redis
   REDIS_HOST=redis
   REDIS_PORT=6379
   REDIS_PASSWORD=<secure-password>
   
   # JWT
   JWT_SECRET_KEY=<secure-jwt-secret>
   JWT_ACCESS_TOKEN_EXPIRES=3600
   JWT_REFRESH_TOKEN_EXPIRES=604800
   
   # Rate Limiting
   RATE_LIMIT_ENABLED=true
   RATE_LIMIT_IP_REQUESTS=100
   RATE_LIMIT_IP_WINDOW=60
   
   # Vault (if using)
   VAULT_ADDR=http://vault:8200
   VAULT_TOKEN=<vault-token>
   ```

2. **Security Configuration**:
   ```bash
   # SSL/TLS
   USE_SSL=true
   SSL_CERT_FILE=/path/to/cert.pem
   SSL_KEY_FILE=/path/to/key.pem
   
   # CORS
   CORS_ORIGINS=https://yourdomain.com
   
   # Security Headers
   SECURITY_HEADERS_ENABLED=true
   ```

#### Production Dockerfile

```dockerfile
FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements file first (for better caching)
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app.py .
COPY __init__.py .
COPY core/ ./core/
COPY utils/ ./utils/
COPY tools/ ./tools/

# Create necessary directories
RUN mkdir -p /app/logs /app/secrets /app/static

# Set environment variables
ENV PYTHONPATH="/app:$PYTHONPATH"
ENV FLASK_HOST="0.0.0.0"
ENV FLASK_PORT="5001"

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 5001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:5001/health || exit 1

# Start Flask application with Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "4", "--timeout", "120", "--keep-alive", "5", "--max-requests", "1000", "--max-requests-jitter", "100", "app:app"]
```

#### Production Deployment Script

```bash
#!/bin/bash

# Production deployment script
set -e

echo "Starting production deployment..."

# Build production image
docker build -t python-base-04:production .

# Tag for registry
docker tag python-base-04:production registry.example.com/python-base-04:latest

# Push to registry
docker push registry.example.com/python-base-04:latest

# Update Kubernetes deployment
kubectl set image deployment/python-base-04 python-base-04=registry.example.com/python-base-04:latest -n python-base-04

# Wait for rollout
kubectl rollout status deployment/python-base-04 -n python-base-04

echo "Production deployment completed successfully!"
```

### 5. CI/CD Pipeline

#### GitHub Actions Workflow

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      mongodb:
        image: mongo:6.0
        ports:
          - 27017:27017
        options: >-
          --health-cmd "mongosh --eval 'db.runCommand(\"ping\")'"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'
    
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt
        pip install pytest pytest-cov
    
    - name: Run tests
      run: |
        pytest tests/ --cov=core --cov-report=xml
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.xml

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2
    
    - name: Login to Docker Hub
      uses: docker/login-action@v2
      with:
        username: ${{ secrets.DOCKER_USERNAME }}
        password: ${{ secrets.DOCKER_PASSWORD }}
    
    - name: Build and push
      uses: docker/build-push-action@v4
      with:
        context: .
        push: true
        tags: |
          your-username/python-base-04:latest
          your-username/python-base-04:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up kubectl
      uses: azure/setup-kubectl@v3
      with:
        version: 'latest'
    
    - name: Configure kubectl
      run: |
        echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > kubeconfig
        export KUBECONFIG=kubeconfig
    
    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/python-base-04 python-base-04=your-username/python-base-04:${{ github.sha }} -n python-base-04
        kubectl rollout status deployment/python-base-04 -n python-base-04
```

#### GitLab CI/CD Pipeline

```yaml
stages:
  - test
  - build
  - deploy

variables:
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: "/certs"

test:
  stage: test
  image: python:3.9
  services:
    - mongo:6.0
    - redis:7-alpine
  before_script:
    - pip install -r requirements.txt
    - pip install pytest pytest-cov
  script:
    - pytest tests/ --cov=core --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

build:
  stage: build
  image: docker:20.10.16
  services:
    - docker:20.10.16-dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - |
      if [ "$CI_COMMIT_BRANCH" = "$CI_DEFAULT_BRANCH" ]; then
        docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA $CI_REGISTRY_IMAGE:latest
        docker push $CI_REGISTRY_IMAGE:latest
      fi
  only:
    - main

deploy:
  stage: deploy
  image: alpine:latest
  before_script:
    - apk add --no-cache curl
    - curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    - chmod +x kubectl
    - mv kubectl /usr/local/bin/
  script:
    - echo "$KUBE_CONFIG" | base64 -d > kubeconfig
    - export KUBECONFIG=kubeconfig
    - kubectl set image deployment/python-base-04 python-base-04=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA -n python-base-04
    - kubectl rollout status deployment/python-base-04 -n python-base-04
  only:
    - main
```

### 6. Monitoring and Observability

#### Prometheus Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    
    scrape_configs:
      - job_name: 'python-base-04'
        static_configs:
          - targets: ['python-base-04-service:5001']
        metrics_path: /metrics
        scrape_interval: 5s
```

#### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Python Base 04 Metrics",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{endpoint}}"
          }
        ]
      },
      {
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      },
      {
        "title": "Error Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m])",
            "legendFormat": "5xx errors"
          }
        ]
      }
    ]
  }
}
```

#### Health Check Endpoints

- `/health`: Overall application health
- `/metrics`: Prometheus metrics
- `/modules/status`: Module health status
- `/modules/<module>/health`: Specific module health

### 7. Security Considerations

#### SSL/TLS Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    location / {
        proxy_pass http://python-base-04-service:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Security Headers

```python
# In app.py
from flask_talisman import Talisman

# Configure security headers
Talisman(app, 
    content_security_policy={
        'default-src': "'self'",
        'script-src': "'self' 'unsafe-inline'",
        'style-src': "'self' 'unsafe-inline'",
    },
    force_https=True
)
```

### 8. Performance Optimization

#### Gunicorn Configuration

```python
# gunicorn.conf.py
bind = "0.0.0.0:5001"
workers = 4
worker_class = "sync"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 100
timeout = 120
keepalive = 5
preload_app = True
```

#### Redis Optimization

```python
# Redis connection pooling
REDIS_MAX_CONNECTIONS = 10
REDIS_RETRY_ON_TIMEOUT = True
REDIS_SOCKET_TIMEOUT = 5
REDIS_SOCKET_CONNECT_TIMEOUT = 5
```

#### Database Optimization

```python
# Database connection pooling
DB_POOL_MIN_CONN = 1
DB_POOL_MAX_CONN = 10
DB_CONNECT_TIMEOUT = 10
DB_STATEMENT_TIMEOUT = 30000
```

### 9. Troubleshooting

#### Common Issues

1. **Database Connection Issues**:
   ```bash
   # Check database connectivity
   kubectl exec -it <pod-name> -- python -c "
   from core.managers.database_manager import DatabaseManager
   db = DatabaseManager()
   print(db.check_connection())
   "
   ```

2. **Redis Connection Issues**:
   ```bash
   # Check Redis connectivity
   kubectl exec -it <pod-name> -- python -c "
   from core.managers.redis_manager import RedisManager
   redis = RedisManager()
   print(redis.ping())
   "
   ```

3. **Memory Issues**:
   ```bash
   # Check memory usage
   kubectl top pods -n python-base-04
   ```

4. **Log Analysis**:
   ```bash
   # View application logs
   kubectl logs -f deployment/python-base-04 -n python-base-04
   
   # View specific pod logs
   kubectl logs -f <pod-name> -n python-base-04
   ```

#### Debug Commands

```bash
# Check pod status
kubectl get pods -n python-base-04

# Check service endpoints
kubectl get endpoints -n python-base-04

# Check ingress
kubectl get ingress -n python-base-04

# Check events
kubectl get events -n python-base-04 --sort-by='.lastTimestamp'

# Port forward for debugging
kubectl port-forward deployment/python-base-04 5001:5001 -n python-base-04
```

This comprehensive deployment documentation provides all the necessary information to deploy the Python Base 04 framework across different environments and platforms. 
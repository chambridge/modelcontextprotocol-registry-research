# Security and Access Control Architecture for MCP Registry

## Overview

This document outlines comprehensive security models and access control mechanisms for MCP Registry deployments. The security architecture implements defense-in-depth principles with multiple layers of protection suitable for both development and production environments.

## Security Architecture Layers

```
┌─────────────────────────────────────────────────┐
│                 Network Layer                   │
│           (Kind Cluster + K8s)                  │
│  ┌─────────────────────────────────────────┐   │
│  │       Ingress & Load Balancing          │   │
│  │     (nginx proxy, rate limiting)        │   │
│  └─────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              Namespace Level                    │
│         (mcp-registry namespace)                │
│  ┌─────────────────────────────────────────┐   │
│  │     RBAC & Access Control              │   │
│  │   (who can access what resources?)      │   │
│  └─────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────┐   │
│  │      Network Policies                   │   │
│  │   (service-to-service isolation)        │   │
│  └─────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              Application Level                  │
│           (MCP Registry Service)                │
│  ┌─────────────────────────────────────────┐   │
│  │     Authentication & Authorization      │   │
│  │   (JWT tokens, anonymous auth)          │   │
│  └─────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────┐   │
│  │       API Method Filtering              │   │
│  │   (nginx sidecar read-only proxy)       │   │
│  └─────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              Runtime Level                      │
│           (Container Security)                  │
│  ┌─────────────────────────────────────────┐   │
│  │     Pod Security Standards              │   │
│  │   (non-root, read-only filesystem)      │   │
│  └─────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────┐   │
│  │       Resource Constraints              │   │
│  │   (CPU/memory limits, capabilities)     │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## Access Control Models

### Role-Based Registry Access

**Use Case:** Fine-grained control based on user roles and responsibilities

#### Registry Reader Role
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: mcp-registry
  name: mcp-registry-reader
rules:
# Service access for API consumption
- apiGroups: [""]
  resources: ["services"]
  resourceNames: ["mcp-registry-readonly"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: mcp-registry-reader-binding
  namespace: mcp-registry
subjects:
- kind: User
  name: mcp-developer
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: mcp-users
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: mcp-registry-reader
  apiGroup: rbac.authorization.k8s.io
```

## Network Security

### Network Policies for Service Isolation

```yaml
# Default deny all ingress traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: mcp-registry
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Allow PostgreSQL access only from registry pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-access-policy
  namespace: mcp-registry
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: mcp-registry
    ports:
    - protocol: TCP
      port: 5432
---
# Allow registry API access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: registry-api-access-policy
  namespace: mcp-registry
spec:
  podSelector:
    matchLabels:
      app: mcp-registry
  policyTypes:
  - Ingress
  ingress:
  # Allow read-only access through nginx proxy
  - from: []
    ports:
    - protocol: TCP
      port: 80
  # Allow full API access from same namespace only
  - from:
    - namespaceSelector:
        matchLabels:
          name: mcp-registry
    ports:
    - protocol: TCP
      port: 8080
  # Allow health checks from system components
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 8080
    - protocol: TCP
      port: 80
```

### Egress Control for Registry Components

```yaml
# Control outbound traffic from registry pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: registry-egress-policy
  namespace: mcp-registry
spec:
  podSelector:
    matchLabels:
      app: mcp-registry
  policyTypes:
  - Egress
  egress:
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow PostgreSQL access
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  # Allow HTTPS for seed data fetching (if needed)
  - to: []
    ports:
    - protocol: TCP
      port: 443
```

## Application-Level Security

### Enhanced Authentication Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mcp-registry-security-config
  namespace: mcp-registry
data:
  # Authentication settings
  MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH: "true"
  MCP_REGISTRY_ANONYMOUS_NAMESPACE: "io.modelcontextprotocol.anonymous"
  MCP_REGISTRY_JWT_EXPIRY_MINUTES: "5"
  MCP_REGISTRY_ENABLE_REGISTRY_VALIDATION: "false"
  
  # Security settings
  MCP_REGISTRY_ENABLE_RATE_LIMITING: "true"
  MCP_REGISTRY_RATE_LIMIT_REQUESTS_PER_MINUTE: "100"
  MCP_REGISTRY_LOG_LEVEL: "INFO"
```

### Enhanced Nginx Security Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-security-config
  namespace: mcp-registry
data:
  nginx.conf: |
    events {
        worker_connections 1024;
    }
    
    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;
        
        # Security headers
        add_header X-Content-Type-Options nosniff always;
        add_header X-Frame-Options DENY always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'" always;
        
        # Rate limiting
        limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
        limit_req_zone $binary_remote_addr zone=health:10m rate=60r/m;
        
        # Logging
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log warn;
        
        upstream registry {
            server 127.0.0.1:8080;
            keepalive 32;
        }
        
        server {
            listen 80;
            server_name _;
            
            # Hide nginx version
            server_tokens off;
            
            # Health check endpoint with separate rate limit
            location /v0/health {
                limit_req zone=health burst=5 nodelay;
                
                if ($request_method !~ ^(GET|HEAD|OPTIONS)$ ) {
                    return 405 '{"error": "Method not allowed", "allowed": ["GET", "HEAD", "OPTIONS"]}';
                }
                
                proxy_pass http://registry;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }
            
            # Read-only server endpoints
            location ~ ^/v0/servers(/.*)?$ {
                limit_req zone=api burst=10 nodelay;
                
                if ($request_method !~ ^(GET|HEAD|OPTIONS)$ ) {
                    return 405 '{"error": "Method not allowed in read-only mode", "allowed": ["GET", "HEAD", "OPTIONS"], "contact": "platform-team@company.com"}';
                }
                
                proxy_pass http://registry;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                
                # Cache headers for better performance
                expires 5m;
                add_header Cache-Control "public, max-age=300";
            }
            
            # Block all write operations with informative error
            location ~ ^/v0/(publish|auth) {
                return 403 '{"error": "Write operations disabled in read-only mode", "message": "Use direct API access on port 8080 for publishing", "contact": "platform-team@company.com"}';
            }
            
            # Block unauthorized access to other endpoints
            location / {
                return 404 '{"error": "Endpoint not available in read-only mode", "available_endpoints": ["/v0/health", "/v0/servers"]}';
            }
        }
    }
```

## Container Security

### Pod Security Standards

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pod-security-config
  namespace: mcp-registry
data:
  security-context.yaml: |
    # Applied to all containers in mcp-registry deployment
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 2000
      capabilities:
        drop:
        - ALL
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      seccompProfile:
        type: RuntimeDefault
```

### Enhanced Registry Deployment with Security

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-registry-secure
  namespace: mcp-registry
  labels:
    app: mcp-registry
    security-profile: "enhanced"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-registry
  template:
    metadata:
      labels:
        app: mcp-registry
        security-profile: "enhanced"
      annotations:
        # Security annotations
        seccomp.security.alpha.kubernetes.io/pod: runtime/default
    spec:
      serviceAccountName: mcp-registry-service-account
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault
      
      # Init container with security constraints
      initContainers:
      - name: wait-for-postgres
        image: quay.io/enterprisedb/postgresql:16
        imagePullPolicy: IfNotPresent
        command: ['sh', '-c']
        args:
        - |
          echo "Waiting for PostgreSQL to be ready..."
          until pg_isready -h postgres -p 5432 -U postgres; do
            echo "PostgreSQL is not ready yet. Waiting..."
            sleep 2
          done
          echo "PostgreSQL is ready!"
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-password
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          capabilities:
            drop:
            - ALL
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        resources:
          requests:
            memory: "32Mi"
            cpu: "10m"
          limits:
            memory: "64Mi"
            cpu: "50m"
      
      containers:
      # Registry container with enhanced security
      - name: registry
        image: ghcr.io/modelcontextprotocol/registry:latest
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: MCP_REGISTRY_SERVER_ADDRESS
          value: ":8080"
        - name: MCP_REGISTRY_DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: database-url
        envFrom:
        - configMapRef:
            name: mcp-registry-security-config
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          capabilities:
            drop:
            - ALL
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /v0/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /v0/health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: temp-storage
          mountPath: /tmp
      
      # Nginx sidecar with enhanced security
      - name: nginx-readonly
        image: nginx:alpine
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: readonly-http
          protocol: TCP
        securityContext:
          runAsNonRoot: true
          runAsUser: 101  # nginx user
          runAsGroup: 101
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE  # Required for binding to port 80
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
          readOnly: true
        - name: nginx-temp
          mountPath: /var/cache/nginx
        - name: nginx-temp
          mountPath: /var/run
        livenessProbe:
          httpGet:
            path: /v0/health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /v0/health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-security-config
      - name: temp-storage
        emptyDir: {}
      - name: nginx-temp
        emptyDir: {}
```


This comprehensive security architecture provides multiple layers of protection while maintaining operational flexibility for MCP Registry deployments in both development and production environments.
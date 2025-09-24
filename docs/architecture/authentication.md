# Authentication and Deployment Patterns

This document provides comprehensive guidance for authentication configuration and deployment patterns for the MCP Registry, including options for disabling authentication in internal environments and implementing read-only access patterns.

## Authentication Architecture Overview

### Current Implementation

The MCP Registry uses **endpoint-specific authentication** rather than global middleware. Authentication is implemented at the individual endpoint level with the following characteristics:

- **JWT-based tokens** with Ed25519 signing
- **5-minute token expiration** for security
- **Namespace-based permissions** (e.g., `io.github.username/*`, `company.com/*`)
- **Multiple authentication methods** (GitHub OAuth, OIDC, DNS verification, etc.)

### Protected vs Unprotected Endpoints

**Public Endpoints (No Authentication Required)**:
```
GET  /v0/servers                    # List MCP servers
GET  /v0/servers/{server_id}        # Get server details
GET  /v0/servers/{server_id}/versions # Get server versions
GET  /v0/health                     # Health check
GET  /v0/ping                       # Ping endpoint
GET  /metrics                       # Prometheus metrics
```

**Protected Endpoints (Authentication Required)**:
```
POST /v0/publish                    # Publish MCP server
PUT  /v0/servers/{server_id}        # Edit server (admin only)
POST /v0/auth/*                     # Authentication endpoints
```

## Authentication Configuration Options

### 1. Anonymous Authentication Mode ✅ (Recommended for Internal Use)

Enable anonymous authentication to allow publishing without external OAuth providers.

#### Configuration
```bash
# Environment Variables
MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH=true
MCP_REGISTRY_ENABLE_REGISTRY_VALIDATION=false  # Optional: skip package validation
```

#### Usage Workflow
```bash
# 1. Get anonymous token
curl -X POST http://localhost:8080/v0/auth/none
# Returns: {"registry_token": "jwt_token", "expires_at": timestamp}

# 2. Publish servers to anonymous namespace
curl -X POST http://localhost:8080/v0/publish \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "io.modelcontextprotocol.anonymous/my-server",
    "description": "My internal server",
    "version": "1.0.0",
    "packages": [...]
  }'
```

**Limitations**:
- Restricted to `io.modelcontextprotocol.anonymous/*` namespace
- Tokens expire every 5 minutes (requires refresh)

### 2. Full Authentication Bypass (Code Modification Required)

For complete authentication removal, add a configuration flag:

```go
// internal/config/config.go
type Config struct {
    // ... existing fields
    DisableAuthentication bool `env:"DISABLE_AUTHENTICATION" envDefault:"false"`
}

// internal/api/handlers/v0/publish.go
func RegisterPublishEndpoint(api huma.API, registry service.RegistryService, cfg *config.Config) {
    huma.Register(api, huma.Operation{
        // ... operation config
    }, func(ctx context.Context, input *PublishServerInput) (*Response[apiv0.ServerJSON], error) {
        
        // Skip authentication if disabled
        if cfg.DisableAuthentication {
            // Allow any publication without namespace restrictions
            return publishWithoutAuth(ctx, input, registry, cfg)
        }
        
        // Existing authentication flow...
    })
}
```

## Deployment Patterns

### Pattern 1: Init Container with Pre-loaded Servers

Use an init container to pre-populate the registry with predefined MCP servers before the main application starts.

#### Kubernetes Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-registry
spec:
  template:
    spec:
      # Init container to pre-load MCP servers using direct API calls
      initContainers:
      - name: mcp-loader
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          # Wait for main registry to be ready
          until curl -f http://mcp-registry:8080/v0/health; do
            echo "Waiting for registry..."
            sleep 2
          done
          
          # Get anonymous JWT token
          echo "Getting anonymous authentication token..."
          TOKEN_RESPONSE=$(curl -s -X POST http://mcp-registry:8080/v0/auth/none)
          JWT_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"registry_token":"[^"]*"' | cut -d'"' -f4)
          
          if [ -z "$JWT_TOKEN" ]; then
            echo "Failed to get authentication token"
            exit 1
          fi
          
          # Publish each predefined server using direct API calls
          for server_file in /mcp-servers/*.json; do
            if [ -f "$server_file" ]; then
              echo "Publishing $(basename $server_file)..."
              curl -X POST http://mcp-registry:8080/v0/publish \
                -H "Authorization: Bearer $JWT_TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$server_file"
              
              if [ $? -eq 0 ]; then
                echo "Successfully published $(basename $server_file)"
              else
                echo "Failed to publish $(basename $server_file)"
              fi
            fi
          done
          
          echo "Server loading completed"
        env:
        - name: MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH
          value: "true"
        volumeMounts:
        - name: server-definitions
          mountPath: /mcp-servers
          readOnly: true
        - name: shared-data
          mountPath: /shared
      
      # Main registry container
      containers:
      - name: registry
        image: ghcr.io/modelcontextprotocol/registry:latest
        ports:
        - containerPort: 8080
        env:
        - name: MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH
          value: "true"
        - name: MCP_REGISTRY_DATABASE_URL
          value: "postgres://user:pass@postgres:5432/mcp-registry"
        volumeMounts:
        - name: shared-data
          mountPath: /shared
      
      # Read-only nginx proxy sidecar
      - name: nginx-proxy
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
          readOnly: true
      
      volumes:
      - name: server-definitions
        configMap:
          name: mcp-server-definitions
      - name: shared-data
        emptyDir: {}
      - name: nginx-config
        configMap:
          name: nginx-readonly-config
```

#### ConfigMap for Server Definitions

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mcp-server-definitions
data:
  postgres-server.json: |
    {
      "name": "io.modelcontextprotocol.anonymous/postgres",
      "description": "PostgreSQL MCP server for internal databases",
      "version": "1.0.0",
      "packages": [
        {
          "registryType": "npm",
          "identifier": "@modelcontextprotocol/server-postgres",
          "version": "1.0.0"
        }
      ],
      "environmentVariables": ["POSTGRES_CONNECTION_STRING"],
      "transport": "stdio"
    }
  
  filesystem-server.json: |
    {
      "name": "io.modelcontextprotocol.anonymous/filesystem",
      "description": "Filesystem MCP server for file operations",
      "version": "1.0.0",
      "packages": [
        {
          "registryType": "npm", 
          "identifier": "@modelcontextprotocol/server-filesystem",
          "version": "1.0.0"
        }
      ],
      "packageArguments": ["--readonly"],
      "transport": "stdio"
    }
```

### Pattern 2: Read-Only Nginx Sidecar Proxy

Since the registry doesn't have a built-in read-only mode, implement an nginx sidecar to filter HTTP methods and expose only read operations.

#### Nginx Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-readonly-config
data:
  nginx.conf: |
    events {
        worker_connections 1024;
    }
    
    http {
        upstream registry {
            server 127.0.0.1:8080;
        }
        
        # Rate limiting
        limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
        
        server {
            listen 80;
            server_name _;
            
            # Security headers
            add_header X-Content-Type-Options nosniff;
            add_header X-Frame-Options DENY;
            add_header X-XSS-Protection "1; mode=block";
            
            # Health check endpoint
            location /v0/health {
                limit_req zone=api burst=20 nodelay;
                proxy_pass http://registry;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
            }
            
            # Read-only API endpoints
            location ~ ^/v0/servers(/.*)?$ {
                limit_req zone=api burst=50 nodelay;
                
                # Only allow GET requests
                if ($request_method !~ ^(GET|HEAD|OPTIONS)$ ) {
                    return 405 '{"error": "Method not allowed in read-only mode", "allowed_methods": ["GET", "HEAD", "OPTIONS"]}';
                }
                
                proxy_pass http://registry;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            }
            
            # Metrics endpoint
            location /metrics {
                limit_req zone=api burst=10 nodelay;
                proxy_pass http://registry;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
            }
            
            # Block all write operations
            location ~ ^/v0/(publish|auth) {
                return 403 '{"error": "Write operations disabled in read-only mode", "contact": "admin@company.com"}';
            }
            
            # Block edit operations
            location ~ ^/v0/servers/.*/edit {
                return 403 '{"error": "Edit operations disabled in read-only mode", "contact": "admin@company.com"}';
            }
            
            # Default deny for unmatched paths
            location / {
                return 404 '{"error": "Endpoint not found in read-only mode"}';
            }
        }
    }
```

#### Service Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mcp-registry-readonly
spec:
  selector:
    app: mcp-registry
  ports:
  - name: readonly-api
    port: 80
    targetPort: 80
    protocol: TCP
  - name: full-api
    port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
```

### Pattern 3: Complete Deployment Example

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: mcp-registry
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-registry
  namespace: mcp-registry
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mcp-registry
  template:
    metadata:
      labels:
        app: mcp-registry
    spec:
      # Init container for server pre-loading
      initContainers:
      - name: wait-for-db
        image: postgres:16-alpine
        command: ['sh', '-c', 'until pg_isready -h postgres -p 5432; do sleep 1; done']
      
      - name: mcp-loader
        image: curlimages/curl:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          # Wait for registry service
          until curl -f http://localhost:8080/v0/health; do
            echo "Waiting for registry service..."
            sleep 2
          done
          
          # Get anonymous JWT token via direct API call
          echo "Getting anonymous authentication token..."
          TOKEN_RESPONSE=$(curl -s -X POST http://localhost:8080/v0/auth/none)
          JWT_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"registry_token":"[^"]*"' | cut -d'"' -f4)
          
          if [ -z "$JWT_TOKEN" ]; then
            echo "Failed to get authentication token"
            exit 1
          fi
          
          # Publish servers using direct API calls
          for server_file in /mcp-servers/*.json; do
            if [ -f "$server_file" ]; then
              echo "Publishing $(basename $server_file)..."
              RESPONSE=$(curl -s -w "%{http_code}" -X POST http://localhost:8080/v0/publish \
                -H "Authorization: Bearer $JWT_TOKEN" \
                -H "Content-Type: application/json" \
                -d @"$server_file")
              
              HTTP_CODE=$(echo "$RESPONSE" | tail -c 4)
              if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
                echo "Successfully published $(basename $server_file)"
              else
                echo "Failed to publish $(basename $server_file) - HTTP $HTTP_CODE"
                echo "$RESPONSE"
              fi
            fi
          done
          
          echo "Server loading completed"
        env:
        - name: MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH
          value: "true"
        volumeMounts:
        - name: server-definitions
          mountPath: /mcp-servers
          readOnly: true
      
      containers:
      # Main registry application
      - name: registry
        image: ghcr.io/modelcontextprotocol/registry:latest
        ports:
        - containerPort: 8080
        env:
        - name: MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH
          value: "true"
        - name: MCP_REGISTRY_ENABLE_REGISTRY_VALIDATION
          value: "false"
        - name: MCP_REGISTRY_DATABASE_URL
          value: "postgres://mcpregistry:password@postgres:5432/mcp-registry"
        livenessProbe:
          httpGet:
            path: /v0/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /v0/health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      
      # Read-only nginx proxy sidecar
      - name: nginx-readonly
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      
      volumes:
      - name: server-definitions
        configMap:
          name: mcp-server-definitions
      - name: nginx-config
        configMap:
          name: nginx-readonly-config
```

## Security Considerations

### Authentication Security
- **Token Expiration**: Anonymous tokens expire in 5 minutes
- **Namespace Isolation**: Anonymous mode restricts to specific namespaces
- **No Credential Exposure**: No need to manage GitHub OAuth credentials

### Read-Only Security
- **Method Filtering**: Nginx blocks non-GET requests
- **Rate Limiting**: Prevents API abuse
- **Error Information**: Limited error details to prevent enumeration
- **Security Headers**: Standard security headers applied

### Network Security
- **Internal Communication**: Registry-to-database traffic stays internal
- **Service Mesh**: Compatible with Istio/Linkerd for additional security
- **Network Policies**: Kubernetes network policies for traffic isolation

## Operational Considerations

### Monitoring and Observability
```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mcp-registry
spec:
  selector:
    matchLabels:
      app: mcp-registry
  endpoints:
  - port: full-api
    path: /metrics
    interval: 30s
```

### Backup and Recovery
- **Database Backups**: Use PostgreSQL backup strategies
- **Server Definitions**: Store as GitOps configuration
- **Configuration**: Backup ConfigMaps and environment variables

### Scaling Considerations
- **Horizontal Scaling**: Multiple registry replicas supported
- **Database**: PostgreSQL clustering for high availability
- **Load Balancing**: Use Kubernetes services with multiple endpoints

## Troubleshooting

### Common Issues

**Init Container Fails to Load Servers**:
```bash
# Check init container logs
kubectl logs -n mcp-registry deployment/mcp-registry -c mcp-loader

# Verify anonymous auth is enabled
kubectl exec -n mcp-registry deployment/mcp-registry -c registry -- \
  curl -X POST http://localhost:8080/v0/auth/none
```

**Nginx Proxy Blocks Valid Requests**:
```bash
# Check nginx access logs
kubectl logs -n mcp-registry deployment/mcp-registry -c nginx-readonly

# Test endpoints directly
kubectl port-forward -n mcp-registry deployment/mcp-registry 8080:8080
curl http://localhost:8080/v0/servers
```

**Database Connection Issues**:
```bash
# Check database connectivity
kubectl exec -n mcp-registry deployment/mcp-registry -c registry -- \
  pg_isready -h postgres -p 5432

# Verify environment variables
kubectl exec -n mcp-registry deployment/mcp-registry -c registry -- env | grep MCP_REGISTRY
```

## Recommendations

### For Internal Enterprise Deployment

1. **Use Anonymous Authentication** for simplified server publishing
2. **Implement Nginx Sidecar** for read-only public access
3. **Pre-load Servers** via init containers with predefined configurations
4. **Monitor Resources** and set appropriate resource limits
5. **Backup Configurations** in version control (GitOps)

### For High-Security Environments

1. **Network Policies** to restrict traffic flow
2. **Service Mesh** for encryption and observability  
3. **Resource Quotas** to prevent resource exhaustion
4. **Pod Security Standards** for container security
5. **Regular Security Scans** of container images

This approach provides a production-ready deployment pattern that balances security, functionality, and operational simplicity for internal MCP registry deployments.
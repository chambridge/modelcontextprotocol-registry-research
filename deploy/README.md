# MCP Registry Kubernetes Deployment

This directory contains Kubernetes deployment manifests and scripts for running the Model Context Protocol (MCP) Registry on a Kind cluster with PostgreSQL backend and read-only nginx proxy.

## Architecture Overview

The deployment consists of the following components:

```
┌─────────────────────────────────────────────┐
│              Kind Cluster                   │
│                                             │
│  ┌─────────────────────────────────────────┐│
│  │           mcp-registry namespace        ││
│  │                                         ││
│  │  ┌─────────────┐  ┌─────────────────────┤│
│  │  │ PostgreSQL  │  │   MCP Registry Pod   ││
│  │  │ Database    │  │                      ││
│  │  │             │  │  ┌─────────────────┐ ││
│  │  │ - PVC       │  │  │ Registry App    │ ││
│  │  │ - Secret    │  │  │ (Port 8080)     │ ││
│  │  │             │  │  └─────────────────┘ ││
│  │  └─────────────┘  │                      ││
│  │                   │  ┌─────────────────┐ ││
│  │  ┌─────────────┐  │  │ Nginx Sidecar   │ ││
│  │  │ Seed Job    │  │  │ (Port 80)       │ ││
│  │  │ (Post-      │  │  │ Read-Only Proxy │ ││
│  │  │ Deploy)     │  │  └─────────────────┘ ││
│  │  └─────────────┘  └─────────────────────┤│
│  │                                         ││
│  │  Direct connection: Job -> Registry:8080││
│  │  (Bypasses nginx proxy for POST access)││
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

## Components

### 1. PostgreSQL Database
- **Persistent storage** with 10Gi PVC
- **Credentials** stored in Kubernetes secrets
- **Health checks** for startup verification
- **Resource limits** for stable operation

### 2. MCP Registry Application
- **Anonymous authentication** enabled for internal server publishing
- **Environment configuration** via ConfigMaps
- **Health probes** for reliability
- **Init container** only waits for PostgreSQL readiness

### 3. Nginx Read-Only Sidecar
- **HTTP method filtering** (only GET, HEAD, OPTIONS allowed)
- **Write endpoint blocking** (POST /v0/publish, etc.)
- **Rate limiting** and security headers
- **CORS support** for web applications

### 4. Seed Data Loading Job
- **Sample MCP servers** from the official GitHub repository
- **Post-deployment job** that runs after registry is ready
- **Direct service access** (bypasses nginx proxy restrictions)
- **API-based publishing** using anonymous authentication
- **Error handling** and progress reporting

## Files

### Kubernetes Manifests (`k8s/`)
- `namespace.yaml` - Creates the mcp-registry namespace
- `postgres.yaml` - PostgreSQL deployment with persistent storage
- `nginx-config.yaml` - Nginx configuration for read-only proxy (simplified)
- `registry.yaml` - MCP Registry deployment with nginx sidecar
- `seed-job.yaml` - Post-deployment job for loading sample data

### Scripts
- `setup.sh` - Complete deployment automation script
- `cleanup.sh` - Cleanup script for removing deployment
- `../scripts/fetch-seed-data.py` - Python script to fetch sample data from GitHub

### Configuration
- `kind-config.yaml` - Kind cluster configuration with port mappings

## Prerequisites

Before deploying, ensure you have the following installed:

- **Docker** (for Kind cluster)
- **Kind** (Kubernetes in Docker)
  ```bash
  go install sigs.k8s.io/kind@latest
  ```
- **kubectl** (Kubernetes CLI)
- **Python 3** (for JSON validation)

## Quick Start

### 1. Clone and Setup
```bash
# Ensure you're in the project root directory
pwd  # Should be .../modelcontextprotocol-registry-research

# Make scripts executable (if not already)
chmod +x deploy/setup.sh deploy/cleanup.sh
```

### 2. Deploy Everything
```bash
# Run the automated setup script
./deploy/setup.sh
```

The setup script will:
1. **Create Kind cluster** with proper configuration
2. **Deploy PostgreSQL** with persistent storage  
3. **Fetch sample seed data** from GitHub repository
4. **Deploy MCP Registry** with anonymous auth enabled
5. **Configure nginx sidecar** for read-only access
6. **Run seed loading job** to populate data
7. **Verify deployment** and show access information

### 3. Access the Registry

After deployment, you can access the registry:

```bash
# Access read-only endpoints (recommended for users)
kubectl port-forward -n mcp-registry service/mcp-registry-readonly 8080:80

# Access full API (for administration)
kubectl port-forward -n mcp-registry service/mcp-registry 8081:8080
```

### 4. Test the Deployment

```bash
# Test health endpoint
curl http://localhost:8080/v0/health
# Expected: {"status":"ok"}

# Test read-only access - should show loaded servers
curl http://localhost:8080/v0/servers
# Expected: {"servers":[...],"metadata":{"count":1}}

# Verify write operations are blocked
curl -X POST http://localhost:8080/v0/publish
# Expected: 403 Forbidden HTML response

# Verify auth endpoint is blocked
curl -X POST http://localhost:8080/v0/auth/none
# Expected: 403 Forbidden HTML response

# Test full API access (different port)
kubectl port-forward -n mcp-registry service/mcp-registry 8081:8080 &
curl -X POST http://localhost:8081/v0/auth/none
# Expected: {"registry_token":"eyJ...","expires_at":...}
```

## Manual Deployment Steps

If you prefer to deploy manually or understand the process step-by-step:

### 1. Create Kind Cluster

```bash
# Create cluster with custom configuration
kind create cluster --name mcp-registry --config deploy/kind-config.yaml

# Verify cluster is ready
kubectl get nodes
```

### 2. Deploy Database

```bash
# Create namespace
kubectl apply -f deploy/k8s/namespace.yaml

# Deploy PostgreSQL
kubectl apply -f deploy/k8s/postgres.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=available deployment/postgres -n mcp-registry --timeout=300s
```

### 3. Prepare Seed Data

```bash
# Fetch sample seed data from GitHub
python3 scripts/fetch-seed-data.py deploy/sample-seed.json 10

# Create ConfigMap with sample seed data
kubectl create configmap mcp-seed-data \
  --from-file=seed.json=deploy/sample-seed.json \
  --namespace=mcp-registry

# Verify the data was loaded correctly
kubectl get configmap mcp-seed-data -n mcp-registry -o yaml | head -20
```

**Note:** The setup.sh script automatically handles this step and fetches sample data from the official GitHub repository.

### 4. Deploy Registry Application

```bash
# Deploy nginx configuration
kubectl apply -f deploy/k8s/nginx-config.yaml

# Deploy MCP Registry
kubectl apply -f deploy/k8s/registry.yaml

# Wait for deployment
kubectl wait --for=condition=available deployment/mcp-registry -n mcp-registry --timeout=300s

# Deploy seed loading job
kubectl apply -f deploy/k8s/seed-job.yaml

# Wait for seed job to complete
kubectl wait --for=condition=complete job/mcp-seed-loader -n mcp-registry --timeout=300s
```

### 5. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n mcp-registry

# Check logs
kubectl logs -n mcp-registry deployment/mcp-registry -c registry
kubectl logs -n mcp-registry job/mcp-seed-loader
kubectl logs -n mcp-registry deployment/mcp-registry -c nginx-readonly
```

## Configuration

### Environment Variables

The registry is configured with the following settings:

```yaml
MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH: "true"      # Enable anonymous publishing
MCP_REGISTRY_ENABLE_REGISTRY_VALIDATION: "false" # Skip external validation
MCP_REGISTRY_DATABASE_URL: "postgres://postgres:password@postgres:5432/mcp-registry?sslmode=disable"
MCP_REGISTRY_JWT_PRIVATE_KEY: "bb2c6b424005acd5df47a9e2c87f446def86dd740c888ea3efb825b23f7ef47c"
```

**Important Notes:**
- **JWT Private Key is still required** even in anonymous mode because `/v0/auth/none` still generates JWT tokens
- **Anonymous mode** bypasses external OAuth but still uses JWT tokens for API security
- **The private key** signs tokens for the `io.modelcontextprotocol.anonymous/*` namespace

### Resource Limits

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| PostgreSQL | 100m | 256Mi | 500m | 512Mi |
| Registry | 100m | 256Mi | 500m | 512Mi |
| Nginx | 50m | 64Mi | 100m | 128Mi |

### Nginx Read-Only Configuration

The nginx sidecar is configured to:
- **Allow**: `GET`, `HEAD`, `OPTIONS` methods only
- **Block**: `POST`, `PUT`, `DELETE`, `PATCH` methods
- **Rate limit**: 10 requests/second per IP
- **Security headers**: X-Frame-Options, X-XSS-Protection, etc.
- **CORS support**: For cross-origin web applications

## API Endpoints

### Read-Only Endpoints (via nginx on port 80)

```bash
GET  /v0/servers                     # List all MCP servers
GET  /v0/servers/{id}               # Get specific server details  
GET  /v0/servers/{id}/versions      # Get all versions of a server
GET  /v0/health                     # Health check
GET  /v0/ping                       # Ping endpoint
```

### Full API Endpoints (via registry on port 8080)

All read-only endpoints plus:
```bash
POST /v0/publish                    # Publish new server (requires auth)
PUT  /v0/servers/{id}              # Edit server (admin only)
POST /v0/auth/none                 # Get anonymous auth token
```

## Seed Data Loading

The post-deployment job loads sample MCP servers from the official GitHub repository:

### Loading Process
1. **Wait** for registry service to be healthy (connects to mcp-registry:8080)
2. **Obtain** anonymous JWT token via `/v0/auth/none`
3. **Parse** sample seed.json containing server definitions
4. **Publish** each server via `/v0/publish` API (bypasses nginx proxy)
5. **Report** success/failure statistics
6. **Complete** as successful Kubernetes Job

### Sample Server Format
```json
{
  "name": "io.github.example/my-server",
  "description": "Example MCP server",
  "status": "active",
  "version": "1.0.0",
  "packages": [
    {
      "registryType": "npm",
      "identifier": "@example/mcp-server",
      "version": "1.0.0",
      "transport": {
        "type": "stdio"
      }
    }
  ]
}
```

## Troubleshooting

### Common Issues

#### 1. Seed Job Fails to Load Data
```bash
# Check seed job logs
kubectl logs -n mcp-registry job/mcp-seed-loader

# Check job status
kubectl get job mcp-seed-loader -n mcp-registry

# Re-run seed job if needed
kubectl delete job mcp-seed-loader -n mcp-registry
kubectl apply -f deploy/k8s/seed-job.yaml

# Common causes:
# - Registry service not ready
# - Authentication token failure
# - ConfigMap with seed data missing
# - Network connectivity issues
# - YAML syntax errors in job definition (avoid heredoc in YAML)
```

#### 2. PostgreSQL Connection Issues
```bash
# Check PostgreSQL status
kubectl get pods -n mcp-registry -l app=postgres

# Check PostgreSQL logs
kubectl logs -n mcp-registry deployment/postgres

# Test connection manually
kubectl exec -n mcp-registry deployment/postgres -- \
  pg_isready -U postgres -d mcp-registry
```

#### 3. Nginx Proxy Issues
```bash
# Check nginx configuration
kubectl describe configmap nginx-readonly-config -n mcp-registry

# Check nginx logs for configuration errors
kubectl logs -n mcp-registry deployment/mcp-registry -c nginx-readonly

# Common nginx issues:
# - "add_header directive is not allowed here" error
#   Solution: Move add_header directives to location blocks, not server block
# - CrashLoopBackOff for nginx container
#   Solution: Simplify nginx config, remove 'always' keyword from add_header

# Test nginx directly
kubectl port-forward -n mcp-registry deployment/mcp-registry 8080:80
curl http://localhost:8080/v0/health
```

#### 4. Registry Health Check Failures
```bash
# Check registry logs
kubectl logs -n mcp-registry deployment/mcp-registry -c registry

# Check environment variables
kubectl exec -n mcp-registry deployment/mcp-registry -c registry -- env | grep MCP_REGISTRY

# Test registry directly
kubectl port-forward -n mcp-registry deployment/mcp-registry 8081:8080
curl http://localhost:8081/v0/health
```

### Debugging Commands

```bash
# Get all resources in namespace
kubectl get all -n mcp-registry

# Describe problematic pods
kubectl describe pod -n mcp-registry <pod-name>

# Get events
kubectl get events -n mcp-registry --sort-by='.lastTimestamp'

# Shell into registry container
kubectl exec -it -n mcp-registry deployment/mcp-registry -c registry -- /bin/sh

# Shell into postgres container  
kubectl exec -it -n mcp-registry deployment/postgres -- psql -U postgres -d mcp-registry
```

### Performance Tuning

#### For Large Seed Data Sets
If loading many servers, consider:

1. **Increase timeouts**:
   ```yaml
   initialDelaySeconds: 60  # Instead of 30
   timeoutSeconds: 10       # Instead of 5
   ```

2. **Increase resource limits**:
   ```yaml
   resources:
     limits:
       memory: "1Gi"        # Instead of 512Mi
       cpu: "1000m"         # Instead of 500m
   ```

3. **Batch processing** in post-deployment job:
   - Process servers in batches of 10-50
   - Add delays between batches
   - Implement retry logic for failures

## Known Issues and Solutions

### Issue: Init Container Chicken-and-Egg Problem
**Problem**: Originally used init container for seed loading, which created a deadlock - init container waited for main container, but main container couldn't start until init completed.

**Solution**: Moved to post-deployment Kubernetes Job that runs after the registry is fully ready.

### Issue: Nginx Configuration Compatibility
**Problem**: nginx:alpine version doesn't support `add_header` with `always` keyword in server context.

**Solution**: Simplified nginx configuration and moved headers to location blocks.

### Issue: YAML Heredoc Syntax
**Problem**: Using heredoc (`<< EOF`) inside YAML causes parsing errors.

**Solution**: Use echo statements instead of heredoc for generating JSON in shell scripts.

### Issue: Seed Data JSON Parsing
**Problem**: Simple grep for server names picks up environment variables and arguments.

**Solution**: Improved JSON parsing or use proper JSON tools like jq (requires adding to container image).

## Security Considerations

### Anonymous Authentication
- **Limited to anonymous namespace**: `io.modelcontextprotocol.anonymous/*`
- **5-minute token expiration**: Prevents long-term token abuse
- **No external dependencies**: No GitHub OAuth required

### Network Security
- **Internal communication only**: All services use ClusterIP
- **Method filtering**: Only safe HTTP methods allowed via nginx
- **Rate limiting**: Prevents API abuse
- **Security headers**: Standard web security headers applied

### Data Security
- **Secrets for database**: PostgreSQL credentials in Kubernetes secrets
- **No persistent credentials**: Anonymous tokens expire automatically
- **Read-only default**: Public access limited to read operations

## Cleanup

### Quick Cleanup
```bash
# Delete everything
./deploy/cleanup.sh
```

### Manual Cleanup
```bash
# Delete namespace (removes all resources)
kubectl delete namespace mcp-registry

# Delete Kind cluster
kind delete cluster --name mcp-registry
```

## Customization

### Adding Custom Servers

To add your own servers to the seed data:

1. **Create custom seed file**:
   ```json
   [
     {
       "name": "io.modelcontextprotocol.anonymous/my-custom-server",
       "description": "My custom MCP server",
       "version": "1.0.0",
       "packages": [...]
     }
   ]
   ```

2. **Update ConfigMap**:
   ```bash
   kubectl create configmap mcp-seed-data \
     --from-file=seed.json=my-custom-seed.json \
     --namespace=mcp-registry \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. **Restart deployment**:
   ```bash
   kubectl rollout restart deployment/mcp-registry -n mcp-registry
   ```

### Modifying nginx Configuration

1. **Edit nginx config**:
   ```bash
   kubectl edit configmap nginx-readonly-config -n mcp-registry
   ```

2. **Restart nginx sidecar**:
   ```bash
   kubectl rollout restart deployment/mcp-registry -n mcp-registry
   ```

### Enabling Full Authentication

To use GitHub OAuth instead of anonymous auth:

1. **Update registry config**:
   ```yaml
   MCP_REGISTRY_ENABLE_ANONYMOUS_AUTH: "false"
   MCP_REGISTRY_GITHUB_CLIENT_ID: "your-client-id"
   MCP_REGISTRY_GITHUB_CLIENT_SECRET: "your-client-secret"
   ```

2. **Restart deployment**:
   ```bash
   kubectl rollout restart deployment/mcp-registry -n mcp-registry
   ```

## Production Considerations

This deployment is designed for development and testing. For production use, consider:

### High Availability
- **Multiple registry replicas**: Scale deployment to 2-3 replicas
- **PostgreSQL clustering**: Use PostgreSQL operators for HA
- **Load balancing**: Use ingress controllers with load balancing

### Persistent Storage
- **Storage class**: Use appropriate storage class for your environment
- **Backup strategy**: Implement regular PostgreSQL backups
- **Volume snapshots**: Use volume snapshot capabilities

### Security Hardening
- **Network policies**: Restrict network traffic between pods
- **Pod security standards**: Implement pod security policies
- **RBAC**: Use proper service accounts and RBAC
- **Image scanning**: Scan container images for vulnerabilities

### Monitoring
- **Prometheus integration**: Enable metrics collection
- **Grafana dashboards**: Create monitoring dashboards
- **Alerting**: Set up alerts for critical issues
- **Log aggregation**: Use centralized logging solutions

This deployment provides a solid foundation for running the MCP Registry in a Kubernetes environment with proper security, initialization, and operational considerations.
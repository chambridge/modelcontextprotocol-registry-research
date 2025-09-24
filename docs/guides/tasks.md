# MCP Registry Kubernetes Deployment Tasks

## Phase 1: Environment Setup

### Task 1: Prerequisites Verification
- [ ] Verify container runtime: check for Docker or Podman
- [ ] Verify kubectl is installed and configured
- [ ] Verify Kind is installed (latest version)
- [ ] Confirm Python 3 is available for seed data fetching
- [ ] Verify system has sufficient resources for Kind cluster

**Copy-paste commands:**
```bash
# Check prerequisites
docker --version && echo "✅ Docker found" || echo "❌ Docker not found"
podman --version && echo "✅ Podman found" || echo "❌ Podman not found"
kubectl version --client
kind version
python3 --version

# Check system resources
free -h  # Check memory
df -h /  # Check disk space
```

### Task 2: Repository Setup
- [ ] Clone the MCP registry research repository
- [ ] Verify project structure and required files
- [ ] Make deployment scripts executable
- [ ] Review deployment architecture documentation

**Copy-paste commands:**
```bash
# Clone and setup repository
git clone <repository-url>
cd modelcontextprotocol-registry-research

# Verify structure
ls -la deploy/
ls -la docs/architecture/
ls -la scripts/

# Make scripts executable
chmod +x deploy/setup.sh deploy/cleanup.sh
```

### Task 3: Kind Cluster Setup
- [ ] Create Kind cluster with custom configuration
- [ ] Verify cluster is running and accessible via kubectl
- [ ] Test basic cluster functionality

**Copy-paste commands:**
```bash
# Automated cluster setup (recommended)
./deploy/setup.sh

# OR manual cluster setup
kind create cluster --name mcp-registry --config deploy/kind-config.yaml

# Verify cluster
kubectl cluster-info --context kind-mcp-registry
kubectl get nodes
kubectl get pods -A
```

## Phase 2: MCP Registry Deployment

### Task 4: Database Deployment
- [ ] Deploy PostgreSQL with persistent storage
- [ ] Verify PostgreSQL is ready and accepting connections
- [ ] Confirm database initialization completed

**Copy-paste commands:**
```bash
# Check PostgreSQL deployment status
kubectl get pods -n mcp-registry -l app=postgres
kubectl logs -n mcp-registry deployment/postgres

# Test database connectivity
kubectl exec -n mcp-registry deployment/postgres -- pg_isready -U postgres
```

### Task 5: Registry Application Deployment
- [ ] Deploy MCP Registry with nginx sidecar
- [ ] Verify all containers are running
- [ ] Check application health endpoints

**Copy-paste commands:**
```bash
# Check registry deployment status
kubectl get pods -n mcp-registry -l app=mcp-registry
kubectl logs -n mcp-registry deployment/mcp-registry -c registry
kubectl logs -n mcp-registry deployment/mcp-registry -c nginx-readonly

# Test health endpoints
kubectl port-forward -n mcp-registry service/mcp-registry-readonly 8080:80 &
curl http://localhost:8080/v0/health
```

### Task 6: Seed Data Loading
- [ ] Verify seed data ConfigMap was created
- [ ] Deploy and monitor seed loading job
- [ ] Confirm servers were loaded into registry

**Copy-paste commands:**
```bash
# Check seed data ConfigMap
kubectl get configmap mcp-seed-data -n mcp-registry
kubectl describe configmap mcp-seed-data -n mcp-registry

# Check seed loading job
kubectl get job mcp-seed-loader -n mcp-registry
kubectl logs job/mcp-seed-loader -n mcp-registry

# Verify data was loaded
curl http://localhost:8080/v0/servers | jq '.metadata.count'
```

## Phase 3: Verification and Testing

### Task 7: Read-Only Access Verification
- [ ] Test read-only endpoints through nginx proxy
- [ ] Verify write operations are blocked
- [ ] Confirm security headers are present

**Copy-paste commands:**
```bash
# Test read-only access (port 8080 → nginx proxy)
kubectl port-forward -n mcp-registry service/mcp-registry-readonly 8080:80 &

# Test successful read operations
curl -v http://localhost:8080/v0/health
curl -v http://localhost:8080/v0/servers

# Test blocked write operations (should return 403)
curl -v -X POST http://localhost:8080/v0/publish
curl -v -X POST http://localhost:8080/v0/auth/none
```

### Task 8: Full API Access Verification
- [ ] Test full API access with direct registry connection
- [ ] Verify anonymous authentication works
- [ ] Confirm administrative endpoints are accessible

**Copy-paste commands:**
```bash
# Test full API access (port 8081 → direct registry)
kubectl port-forward -n mcp-registry service/mcp-registry 8081:8080 &

# Test administrative endpoints
curl -v http://localhost:8081/v0/health
curl -v -X POST http://localhost:8081/v0/auth/none

# Test with authentication token
TOKEN=$(curl -s -X POST http://localhost:8081/v0/auth/none | jq -r '.registry_token')
curl -v -X POST http://localhost:8081/v0/publish \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"test-server","description":"Test server"}'
```

### Task 9: System Monitoring
- [ ] Monitor resource usage and performance
- [ ] Check logs for errors or warnings
- [ ] Verify persistent storage is working

**Copy-paste commands:**
```bash
# Check resource usage
kubectl top pods -n mcp-registry
kubectl top nodes

# Check for issues
kubectl get events -n mcp-registry --sort-by='.lastTimestamp'
kubectl describe deployment mcp-registry -n mcp-registry

# Verify persistent storage
kubectl get pvc -n mcp-registry
kubectl describe pvc postgres-pvc -n mcp-registry
```

## Phase 4: Cleanup (Optional)

### Task 10: Environment Cleanup
- [ ] Stop port forwarding processes
- [ ] Delete MCP Registry deployment
- [ ] Remove Kind cluster
- [ ] Clean up temporary files

**Copy-paste commands:**
```bash
# Stop port forwarding (if running)
pkill -f "kubectl port-forward"

# Automated cleanup
./deploy/cleanup.sh

# Manual cleanup (if needed)
kubectl delete namespace mcp-registry
kind delete cluster --name mcp-registry
```

## Troubleshooting Quick Reference

### Common Issues
- **Pods stuck in Init state**: Check PostgreSQL readiness
- **Nginx container crashes**: Review nginx configuration syntax
- **Seed job fails**: Verify registry health and ConfigMap data
- **Port conflicts**: Change Kind port mappings in kind-config.yaml

### Diagnostic Commands
```bash
# Get all resources
kubectl get all -n mcp-registry

# Check specific pod issues
kubectl describe pod <pod-name> -n mcp-registry
kubectl logs <pod-name> -c <container-name> -n mcp-registry

# Test internal connectivity
kubectl exec -it deployment/mcp-registry -c registry -n mcp-registry -- curl localhost:8080/v0/health
```

## Next Steps

After successful deployment:
1. Review [Architecture Documentation](../architecture/) for system understanding
2. Explore [Authentication Configuration](../architecture/authentication.md) for security customization
3. Read [Design Decisions](../architecture/design-decisions.md) for implementation insights
4. Consider production deployment patterns in [Deployment Architecture](../architecture/deployment-architecture.md)

## Success Criteria

✅ **Deployment Complete When:**
- All pods in `mcp-registry` namespace are `Running`
- Health endpoints return `{"status":"ok"}`
- Read-only API blocks write operations (403 Forbidden)
- Full API allows administrative operations with authentication
- At least one MCP server is loaded in the registry
- No errors in application logs
# MCP Registry Kubernetes Deployment Research

## Executive Summary

The Model Context Protocol (MCP) Registry is a Go-based metadata repository service that provides a standardized REST API for discovering MCP servers. This research analyzes the deployment capabilities, containerization options, dependencies, and integration patterns for deploying the registry in a Kubernetes environment.

## Repository Analysis

### Project Structure and Architecture
- **Repository**: https://github.com/modelcontextprotocol/registry
- **Technology Stack**: Go 1.25, PostgreSQL, Docker, Pulumi
- **Architecture**: Microservice with REST API, multi-stage Docker builds
- **Status**: Preview release (as of 2025-09-08), potential breaking changes expected

### Key Components
```
cmd/               - Application entry points
internal/          - Private application code (API, auth, config, database)
pkg/               - Public packages (API types, models)
deploy/            - Pulumi-based infrastructure as code
data/              - Seed data (seed.json with MCP server definitions)
```

## Containerization Analysis

### Current Docker Configuration
- **Base Images**: 
  - Builder: `golang:1.25-alpine`
  - Runtime: `alpine:latest`
- **Security**: Non-privileged user (UID 10001), runs on port 8080
- **Multi-architecture**: Supports amd64 and arm64

### UBI 9 Compatibility Assessment
**Status**: ❌ **Requires Modification**

**Current Dockerfile Analysis**:
```dockerfile
# Current (Alpine-based)
FROM golang:1.25-alpine AS builder
FROM alpine:latest
```

**UBI 9 Migration Requirements**:
1. **Base Image Changes**:
   ```dockerfile
   # Proposed UBI 9 version
   FROM registry.access.redhat.com/ubi9/go-toolset:1.25 AS builder
   FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
   ```

2. **User Management Adaptations**:
   - UBI uses different user creation mechanisms
   - Current: `adduser -D -s /bin/sh -u 10001 appuser`
   - UBI equivalent: `useradd -r -u 10001 -s /bin/sh appuser`

3. **Package Management**:
   - Replace `apk` commands with `microdnf` for UBI minimal
   - Verify Go toolchain compatibility

**Recommendation**: Moderate effort required (~2-4 hours) to adapt Dockerfile for UBI 9 compliance.

## Dependencies Analysis

### Core Dependencies (from go.mod)
- **Go Version**: 1.25 (latest requirement)
- **Database**: PostgreSQL (via `github.com/jackc/pgx/v5`)
- **Web Framework**: `github.com/danielgtaylor/huma/v2`
- **Authentication**: 
  - `github.com/coreos/go-oidc/v3` (OIDC)
  - `github.com/golang-jwt/jwt/v5` (JWT)
- **Observability**: 
  - `github.com/prometheus/client_golang`
  - `go.opentelemetry.io/otel`

### Database Requirements
- **PostgreSQL Version**: 16 (from docker-compose.yml)
- **Database**: `mcp-registry`
- **User**: `mcpregistry`
- **Storage**: Persistent volume required for production
- **Backup**: K8up (Kubernetes backup operator) with Restic

### Environment Variables (Critical Configuration)
```bash
# Database
DATABASE_URL=postgres://username:password@host:5432/mcp-registry

# Authentication
GITHUB_CLIENT_ID=<oauth-app-id>
GITHUB_CLIENT_SECRET=<oauth-secret>
JWT_PRIVATE_KEY=<32-byte-ed25519-seed>

# Optional OIDC
GOOGLE_OIDC_CLIENT_SECRET=<google-oauth-secret>

# Server Configuration
PORT=8080
ENVIRONMENT=production
```

## Kubernetes Deployment Analysis

### Current Deployment Infrastructure
**Technology**: Pulumi with Go
**Supported Environments**:
- **Local**: Minikube-based development
- **Staging**: GCP with Google Kubernetes Engine (GKE)
- **Production**: GCP with GKE

### Kubernetes Components Deployed
1. **Application Pod**: Registry service container
2. **Database**: PostgreSQL with persistent storage
3. **Ingress**: NGINX ingress controller with cert-manager
4. **Backup**: K8up operator for automated backups
5. **Monitoring**: Prometheus integration
6. **Storage**: 
   - Local: MinIO for development
   - Cloud: Google Cloud Storage for staging/production

### RBAC Integration Assessment
**Status**: ✅ **Kubernetes-Native RBAC Supported**

**Current Implementation**:
- Service account-based authentication for GCP deployment
- GitHub Actions integration with workload identity
- OAuth2/OIDC integration for user authentication

**RBAC Capabilities**:
1. **Namespace-based Access Control**:
   - `io.github.*` namespaces require GitHub authentication
   - `com.company.*` namespaces require domain verification
   - Custom domain namespaces via DNS/HTTP validation

2. **Authentication Methods**:
   - GitHub OAuth
   - GitHub OIDC (for CI/CD)
   - DNS verification
   - HTTP domain verification
   - Anonymous access (configurable)

3. **Kubernetes RBAC Integration**:
   - Service accounts for pod authentication
   - Workload identity for GCP integration
   - Secrets management for OAuth credentials

**Recommendation**: ✅ Well-suited for enterprise Kubernetes RBAC patterns.

## GitHub Integration Dependencies

### Level of GitHub Integration
**Status**: 🔶 **Moderate GitHub Dependency**

**Required GitHub Integrations**:
1. **OAuth Application**: Required for `io.github.*` namespace authentication
2. **Container Registry**: Uses GitHub Container Registry (ghcr.io)
3. **CI/CD**: GitHub Actions for automated deployment
4. **Source Management**: Repository hosting and version control

**Optional GitHub Features**:
- GitHub Discussions for community engagement
- GitHub Issues for project management
- Dependabot for dependency updates

**De-coupling Potential**:
- ✅ OAuth can be replaced with alternative OIDC providers
- ✅ Container registry can use alternative registries (Docker Hub, Harbor, etc.)
- ✅ CI/CD can use alternative pipelines (GitLab CI, Jenkins, etc.)
- ❌ `io.github.*` namespace validation deeply integrated with GitHub API

**Recommendation**: Moderate GitHub coupling primarily for namespace validation. Core functionality can operate independently.

## API and Interfaces Documentation

### REST API Endpoints
**Base URL**: `https://registry.modelcontextprotocol.io/api/v0`

**Key Operations**:
```bash
# Server Discovery
GET /servers                    # List all servers with pagination
GET /servers/{name}            # Get specific server details
GET /servers/{name}/versions   # Get version history

# Server Registration (Authenticated)
POST /servers                  # Register new server
PUT /servers/{name}           # Update existing server
DELETE /servers/{name}        # Remove server (admin only)

# Search and Discovery
GET /servers?search={query}    # Search servers by name/description
GET /servers?category={cat}    # Filter by category
GET /servers?tag={tag}        # Filter by tags
```

### Authentication API
```bash
# OAuth Flow
GET /auth/github/login        # Initiate GitHub OAuth
GET /auth/github/callback     # OAuth callback handler

# Token Management
POST /auth/refresh            # Refresh JWT token
GET /auth/me                  # Get current user info
```

### Response Format
```json
{
  "servers": [
    {
      "name": "io.github.company/server-name",
      "description": "Server description",
      "version": "1.0.0",
      "status": "active",
      "repository": "https://github.com/company/repo",
      "package": {
        "registryType": "npm",
        "identifier": "package-name",
        "version": "1.0.0"
      },
      "transport": "stdio",
      "environmentVariables": ["API_KEY"],
      "packageArguments": ["--option", "value"]
    }
  ],
  "total": 150,
  "page": 1,
  "pageSize": 20
}
```

## MCP Server Registration Mechanisms

### Registration Methods Analysis
**Status**: 📝 **API-Only Registration** (No CRDs or File-based)

**Current Mechanism**: REST API + Authentication
1. **API Registration**:
   ```bash
   POST /api/v0/servers
   Content-Type: application/json
   Authorization: Bearer <jwt-token>
   
   {
     "name": "io.github.myorg/my-server",
     "description": "My MCP server",
     "version": "1.0.0",
     "repository": "https://github.com/myorg/my-server",
     "package": {
       "registryType": "npm",
       "identifier": "my-mcp-server"
     }
   }
   ```

2. **Authentication Required**:
   - GitHub OAuth for `io.github.*` namespaces
   - Domain verification for custom domains
   - JWT tokens for API access

**Missing Mechanisms**:
- ❌ **File-based Registration**: No support for bulk imports via files
- ❌ **Kubernetes CRDs**: No custom resource definitions for K8s-native registration
- ❌ **GitOps Integration**: No automated registration from Git repositories

**Potential Extensions**:
```yaml
# Proposed CRD for Kubernetes integration
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: mcpservers.registry.modelcontextprotocol.io
spec:
  group: registry.modelcontextprotocol.io
  versions:
  - name: v1
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name:
                type: string
              description:
                type: string
              package:
                type: object
                properties:
                  registryType:
                    type: string
                    enum: ["npm", "pypi", "oci"]
```

## Feature Capabilities Analysis

### Categorization and Tagging
**Status**: ❌ **Limited Categorization Support**

**Current Implementation**:
- No explicit category fields in schema
- No formal tagging system
- Classification based on package type only (`npm`, `pypi`, `oci`)

**Available Metadata**:
- `name`: Hierarchical namespace
- `description`: Free-text description
- `repository`: Source code location
- `registryType`: Distribution platform
- `environmentVariables`: Configuration requirements

**Missing Features**:
- Formal category taxonomy
- Multi-level tagging system
- Domain-specific classifications (database, API, development tools)

### Search Capabilities
**Status**: ✅ **Basic Search Implemented**

**Current Search Features**:
```bash
# Text search across name and description
GET /api/v0/servers?search=database

# Filter by registry type
GET /api/v0/servers?registryType=npm

# Pagination support
GET /api/v0/servers?page=2&pageSize=50
```

**Advanced Search Needs**:
- Fuzzy matching
- Category-based filtering
- Tag-based filtering
- Multi-criteria search
- Faceted search results

### Resource Documentation
**Status**: ✅ **Comprehensive Resource Metadata**

**Resource Types Captured**:
1. **Tools**: Implicitly documented through MCP server capabilities
2. **Environment Variables**: 
   ```json
   "environmentVariables": ["API_KEY", "DATABASE_URL", "DEBUG_MODE"]
   ```
3. **Package Arguments**:
   ```json
   "packageArguments": ["--config", "/path/to/config", "--verbose"]
   ```
4. **Permissions**: Documented in server descriptions and documentation
5. **Transport Method**: 
   ```json
   "transport": "stdio"  // or "sse", "websocket"
   ```

**Resource Metadata Examples** (from seed.json):
```json
{
  "name": "io.github.modelcontextprotocol/servers-postgres",
  "description": "PostgreSQL MCP server for database operations",
  "environmentVariables": [
    "POSTGRES_CONNECTION_STRING"
  ],
  "packageArguments": [
    "--schema", "public",
    "--readonly"
  ]
}
```

## Deployment Recommendations

### Kubernetes Deployment Strategy
**Recommended Approach**: 🎯 **Helm Chart + GitOps**

1. **Create Helm Chart**:
   ```yaml
   # values.yaml
   image:
     repository: ghcr.io/modelcontextprotocol/registry
     tag: "latest"
     pullPolicy: IfNotPresent
   
   database:
     host: postgres-service
     name: mcp-registry
     user: mcpregistry
   
   auth:
     github:
       clientId: "{{ .Values.auth.github.clientId }}"
       clientSecret: "{{ .Values.auth.github.clientSecret }}"
   
   ingress:
     enabled: true
     className: nginx
     host: registry.company.com
   ```

2. **Security Hardening**:
   ```yaml
   securityContext:
     runAsNonRoot: true
     runAsUser: 10001
     readOnlyRootFilesystem: true
     allowPrivilegeEscalation: false
   
   podSecurityPolicy:
     enabled: true
     
   networkPolicy:
     enabled: true
     ingress:
       - from:
         - namespaceSelector:
             matchLabels:
               name: ingress-nginx
   ```

3. **Resource Requirements**:
   ```yaml
   resources:
     requests:
       memory: "256Mi"
       cpu: "100m"
     limits:
       memory: "512Mi"
       cpu: "500m"
   ```

### Database Deployment
**Recommendation**: 🎯 **PostgreSQL Operator + Persistent Storage**

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: mcp-registry-postgres
spec:
  instances: 3
  primaryUpdateStrategy: unsupervised
  
  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "256MB"
      effective_cache_size: "1GB"
  
  bootstrap:
    initdb:
      database: mcp-registry
      owner: mcpregistry
      secret:
        name: postgres-credentials
  
  storage:
    size: 10Gi
    storageClass: fast-ssd
```

### Production Considerations

**High Availability**:
- Multi-replica deployment with anti-affinity rules
- Database clustering with automatic failover
- Load balancer with health checks
- Backup strategy with point-in-time recovery

**Monitoring and Observability**:
- Prometheus metrics collection
- OpenTelemetry tracing
- Log aggregation with structured logging
- Health check endpoints

**Security**:
- TLS encryption for all communications
- Secret management with sealed-secrets or external-secrets
- RBAC policies for service accounts
- Network policies for traffic isolation

## Risks and Mitigation Strategies

### Technical Risks
1. **GitHub Dependency**: 
   - **Risk**: Service disruption if GitHub is unavailable
   - **Mitigation**: Implement alternative OIDC providers, cache authentication data

2. **Database Single Point of Failure**:
   - **Risk**: Data loss or service unavailability
   - **Mitigation**: PostgreSQL clustering, automated backups, read replicas

3. **Container Registry Dependency**:
   - **Risk**: Image pull failures
   - **Mitigation**: Mirror images to private registry, implement image caching

### Operational Risks
1. **Preview Status**:
   - **Risk**: Breaking changes in future releases
   - **Mitigation**: Pin specific versions, test upgrades in staging, maintain rollback capability

2. **Limited Search Capabilities**:
   - **Risk**: Poor user experience as registry grows
   - **Mitigation**: Implement enhanced search features, consider external search engine integration

3. **Manual Registration Process**:
   - **Risk**: Scaling bottleneck for large organizations
   - **Mitigation**: Develop bulk import tools, implement CRD support, create GitOps workflows

## Implementation Timeline

### Phase 1 (2-3 weeks): Basic Deployment
- [ ] Create Helm chart for registry deployment
- [ ] Set up PostgreSQL with persistence
- [ ] Configure ingress and TLS termination
- [ ] Implement basic monitoring and alerting

### Phase 2 (3-4 weeks): UBI Integration and Hardening
- [ ] Adapt Dockerfile for UBI 9 compatibility
- [ ] Implement security hardening (PSP, network policies)
- [ ] Set up backup and disaster recovery
- [ ] Performance testing and optimization

### Phase 3 (4-6 weeks): Enterprise Features
- [ ] Develop CRD support for Kubernetes-native registration
- [ ] Implement enhanced search and categorization
- [ ] Create bulk import tools and GitOps integration
- [ ] Set up multi-environment deployment pipeline

## Conclusion

The MCP Registry is well-architected for Kubernetes deployment with modern containerization practices, comprehensive observability, and flexible authentication mechanisms. While it requires moderate effort to adapt for UBI 9 compatibility and has some GitHub dependencies for namespace validation, the overall design is enterprise-ready with appropriate security and scalability considerations.

**Key Strengths**:
- ✅ Modern Go-based architecture with good separation of concerns
- ✅ Comprehensive authentication and authorization mechanisms
- ✅ Production-ready deployment infrastructure with Pulumi
- ✅ Strong observability and monitoring capabilities
- ✅ Multi-architecture container support

**Areas for Enhancement**:
- 🔶 Enhanced search and categorization features
- 🔶 Kubernetes CRD support for native registration
- 🔶 Bulk import and GitOps integration capabilities
- 🔶 Alternative authentication providers to reduce GitHub dependency

The registry represents a solid foundation for enterprise MCP server discovery and management in Kubernetes environments.
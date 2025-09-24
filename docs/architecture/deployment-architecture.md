# MCP Registry Deployment Architecture

## Overview

This document outlines the core deployment architecture for the MCP Registry on Kubernetes, focusing on component relationships, data flows, and design patterns.

## Architecture Components

### Core Infrastructure
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

### Component Details

#### 1. PostgreSQL Database
- **Persistent storage** with 10Gi PVC for registry data
- **Kubernetes secrets** for credential management
- **Health checks** ensure startup verification
- **Resource limits** for stable operation (256Mi-512Mi memory, 100m-500m CPU)

#### 2. MCP Registry Application
- **Anonymous authentication** enabled for internal server publishing
- **Environment configuration** via ConfigMaps for deployment flexibility
- **Health probes** (liveness and readiness) for reliability
- **Init container** handles PostgreSQL readiness verification only

#### 3. Nginx Read-Only Sidecar
- **HTTP method filtering** - only GET, HEAD, OPTIONS allowed
- **Write endpoint blocking** - POST /v0/publish returns 403 Forbidden
- **Simplified configuration** for nginx:alpine compatibility
- **Security headers** for basic web security

#### 4. Seed Data Loading Job
- **Post-deployment execution** - runs after registry is fully operational
- **Direct service access** - connects to mcp-registry:8080 bypassing nginx proxy
- **GitHub data integration** - fetches sample data from official repository
- **Error handling** and progress reporting for operational visibility

## Data Flow Architecture

### Seed Data Loading Flow
```
GitHub Repository 
    ↓ (Python script fetch)
Sample Data File
    ↓ (ConfigMap creation)
Kubernetes ConfigMap
    ↓ (Job execution)
Post-Deploy Job
    ↓ (Direct registry API)
Registry Database
```

### Runtime Data Access Flow
```
Read-Only Users → Nginx Proxy (Port 80) → Registry App → PostgreSQL
                     ↓ (Method filtering)
               GET/HEAD/OPTIONS only

Admin Users → Registry Service (Port 8080) → Registry App → PostgreSQL
                     ↓ (Full API access)
           POST/PUT/DELETE allowed with auth
```

## Network Architecture

### Service Mapping
- **mcp-registry-readonly**: ClusterIP service exposing nginx proxy (port 80)
- **mcp-registry**: ClusterIP service exposing full registry API (port 8080)
- **postgres**: ClusterIP service for database access (port 5432)

### Port Configuration
- **Kind cluster**: Maps 9080:80 and 9443:443 to avoid localhost conflicts
- **Registry pod**: Exposes 8080 (full API) and 80 (read-only proxy)
- **PostgreSQL**: Standard 5432 for database connections

## Resource Management

### Resource Allocation
| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| PostgreSQL | 100m | 256Mi | 500m | 512Mi |
| Registry | 100m | 256Mi | 500m | 512Mi |
| Nginx | 50m | 64Mi | 100m | 128Mi |
| Seed Job | 50m | 64Mi | 100m | 128Mi |

### Storage Requirements
- **PostgreSQL PVC**: 10Gi persistent storage for registry data
- **ConfigMaps**: < 1MB for nginx config and seed data samples
- **Secrets**: Minimal storage for PostgreSQL credentials

## Operational Patterns

### Deployment Sequence
1. **Namespace creation** and basic infrastructure setup
2. **PostgreSQL deployment** with persistent storage initialization
3. **Configuration deployment** (nginx config, registry config, seed data)
4. **Registry deployment** with init container waiting for PostgreSQL
5. **Seed job execution** after registry reaches ready state
6. **Verification** of all components and data loading

### Health Check Strategy
- **PostgreSQL**: `pg_isready` checks for database availability
- **Registry**: HTTP GET `/v0/health` for application readiness
- **Nginx**: HTTP GET `/v0/health` proxied through nginx for proxy health
- **Overall system**: Combination of all component health states

### Scaling Considerations
- **Current design**: Single-replica for development and testing
- **Production scaling**: Multiple registry replicas with shared PostgreSQL
- **Database scaling**: PostgreSQL clustering for high availability
- **Storage scaling**: Dynamic PVC expansion for growing registry data

This architecture provides a robust foundation for MCP Registry deployment while maintaining clear separation of concerns, security boundaries, and operational visibility.
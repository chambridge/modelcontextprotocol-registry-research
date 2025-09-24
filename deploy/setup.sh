#!/bin/bash

# MCP Registry Kind Deployment Setup Script
# This script sets up a complete MCP Registry deployment on Kind with PostgreSQL and nginx sidecar

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="mcp-registry"
NAMESPACE="mcp-registry"
TIMEOUT=300  # 5 minutes timeout for deployments

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v kind &> /dev/null; then
        error "kind is not installed. Please install kind first."
        error "Install with: go install sigs.k8s.io/kind@latest"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        error "docker is not installed. Please install Docker first."
        exit 1
    fi
    
    log "All prerequisites are installed"
}

# Create Kind cluster
create_cluster() {
    log "Creating Kind cluster: $CLUSTER_NAME"
    
    if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        warn "Cluster $CLUSTER_NAME already exists. Deleting and recreating..."
        kind delete cluster --name $CLUSTER_NAME
    fi
    
    kind create cluster --name $CLUSTER_NAME --config deploy/kind-config.yaml
    
    # Wait for cluster to be ready
    log "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    
    log "Kind cluster created successfully"
}

# Fetch and prepare seed data
prepare_seed_data() {
    log "Preparing seed data..."
    
    # Use the fetch-seed-data.py script to get data from GitHub
    log "Fetching seed data from GitHub repository..."
    
    if ! command -v python3 &> /dev/null; then
        error "python3 is required but not installed"
        exit 1
    fi
    
    # Run the seed data fetcher script
    SAMPLE_SEED_FILE="deploy/sample-seed.json"
    if ! python3 scripts/fetch-seed-data.py "$SAMPLE_SEED_FILE" 10; then
        error "Failed to fetch and prepare seed data"
        exit 1
    fi
    
    # Verify the sample file was created
    if [ ! -f "$SAMPLE_SEED_FILE" ]; then
        error "Sample seed data file was not created: $SAMPLE_SEED_FILE"
        exit 1
    fi
    
    # Create the ConfigMap with the sample seed data
    TOTAL_SERVERS=$(grep -c '"name":' "$SAMPLE_SEED_FILE")
    log "Creating ConfigMap with sample seed data ($TOTAL_SERVERS servers)..."
    
    kubectl create configmap mcp-seed-data \
        --from-file=seed.json="$SAMPLE_SEED_FILE" \
        --namespace=$NAMESPACE \
        --dry-run=client -o yaml > /tmp/seed-configmap.yaml
    
    # Show some details about the ConfigMap size
    CONFIGMAP_SIZE=$(wc -c < /tmp/seed-configmap.yaml)
    log "ConfigMap created: ${CONFIGMAP_SIZE} bytes with sample MCP server data"
    log "Seed data prepared successfully"
}

# Deploy all components
deploy_components() {
    log "Deploying MCP Registry components..."
    
    # Create namespace
    log "Creating namespace: $NAMESPACE"
    kubectl apply -f deploy/k8s/namespace.yaml
    
    # Deploy PostgreSQL
    log "Deploying PostgreSQL..."
    kubectl apply -f deploy/k8s/postgres.yaml
    
    # Wait for PostgreSQL to be ready
    log "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=available deployment/postgres \
        --namespace=$NAMESPACE --timeout=${TIMEOUT}s
    
    # Deploy nginx configuration
    log "Deploying nginx configuration..."
    kubectl apply -f deploy/k8s/nginx-config.yaml
    
    # Apply the seed data ConfigMap
    log "Applying seed data ConfigMap..."
    kubectl apply -f /tmp/seed-configmap.yaml
    
    # Deploy MCP Registry
    log "Deploying MCP Registry..."
    kubectl apply -f deploy/k8s/registry.yaml
    
    # Wait for registry to be ready
    log "Waiting for MCP Registry to be ready..."
    kubectl wait --for=condition=available deployment/mcp-registry \
        --namespace=$NAMESPACE --timeout=${TIMEOUT}s
    
    # Deploy seed loading job
    log "Deploying seed loading job..."
    kubectl apply -f deploy/k8s/seed-job.yaml
    
    # Wait for seed job to complete
    log "Waiting for seed loading job to complete..."
    kubectl wait --for=condition=complete job/mcp-seed-loader \
        --namespace=$NAMESPACE --timeout=300s
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check pod status
    log "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    
    # Check if all pods are running
    if ! kubectl get pods -n $NAMESPACE --no-headers | grep -v Running | grep -v Completed; then
        log "All pods are running successfully"
    else
        warn "Some pods are not in Running state"
    fi
    
    # Check seed job status
    log "Checking seed loading job status..."
    kubectl get job mcp-seed-loader -n $NAMESPACE
    kubectl logs job/mcp-seed-loader -n $NAMESPACE --tail=20
    
    # Test registry health
    log "Testing registry health..."
    kubectl port-forward -n $NAMESPACE service/mcp-registry-readonly 8080:80 &
    PORT_FORWARD_PID=$!
    
    sleep 5
    
    if curl -f http://localhost:8080/v0/health 2>/dev/null; then
        log "Registry health check passed"
    else
        warn "Registry health check failed"
    fi
    
    # Test read-only endpoint
    log "Testing read-only server listing..."
    if curl -f http://localhost:8080/v0/servers 2>/dev/null | grep -q "servers"; then
        log "Server listing endpoint working"
    else
        warn "Server listing endpoint may not be working properly"
    fi
    
    # Test that write operations are blocked
    log "Testing write operation blocking..."
    if curl -f -X POST http://localhost:8080/v0/publish 2>/dev/null; then
        warn "Write operations are NOT blocked (this should not happen)"
    else
        log "Write operations are properly blocked"
    fi
    
    kill $PORT_FORWARD_PID 2>/dev/null || true
}

# Show access information
show_access_info() {
    log "Deployment completed successfully!"
    echo ""
    echo -e "${BLUE}=== Access Information ===${NC}"
    echo ""
    echo "Namespace: $NAMESPACE"
    echo ""
    echo "To access the read-only MCP Registry:"
    echo "  kubectl port-forward -n $NAMESPACE service/mcp-registry-readonly 8080:80"
    echo "  Then visit: http://localhost:8080/v0/servers"
    echo ""
    echo "To access the full MCP Registry (for administration):"
    echo "  kubectl port-forward -n $NAMESPACE service/mcp-registry 8080:8080"
    echo "  Then visit: http://localhost:8080/v0/servers"
    echo ""
    echo "Available read-only endpoints:"
    echo "  GET  /v0/servers              - List all MCP servers"
    echo "  GET  /v0/servers/{id}         - Get specific server details"
    echo "  GET  /v0/servers/{id}/versions - Get server versions"
    echo "  GET  /v0/health               - Health check"
    echo "  GET  /v0/ping                 - Ping endpoint"
    echo ""
    echo "Cluster information:"
    echo "  Cluster name: $CLUSTER_NAME"
    echo "  kubectl config current-context: kind-$CLUSTER_NAME"
    echo ""
    echo "To view logs:"
    echo "  kubectl logs -n $NAMESPACE deployment/mcp-registry -c registry"
    echo "  kubectl logs -n $NAMESPACE deployment/mcp-registry -c nginx-readonly"
    echo ""
    echo "To cleanup:"
    echo "  kind delete cluster --name $CLUSTER_NAME"
}

# Cleanup function
cleanup() {
    if [ ! -z "$PORT_FORWARD_PID" ]; then
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
    rm -f /tmp/seed-configmap.yaml
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Main execution
main() {
    log "Starting MCP Registry deployment on Kind..."
    
    check_prerequisites
    create_cluster
    prepare_seed_data
    deploy_components
    verify_deployment
    show_access_info
    
    log "Setup completed successfully!"
}

# Run main function
main "$@"
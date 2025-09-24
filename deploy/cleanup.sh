#!/bin/bash

# MCP Registry Cleanup Script
# This script cleans up the MCP Registry deployment and Kind cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CLUSTER_NAME="mcp-registry"
NAMESPACE="mcp-registry"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    log "Starting cleanup of MCP Registry deployment..."
    
    # Check if cluster exists
    if ! kind get clusters | grep -q "^$CLUSTER_NAME$"; then
        warn "Cluster $CLUSTER_NAME does not exist"
        return 0
    fi
    
    # Set kubectl context
    kubectl config use-context kind-$CLUSTER_NAME
    
    # Show current resources before cleanup
    log "Current resources in namespace $NAMESPACE:"
    kubectl get all -n $NAMESPACE 2>/dev/null || warn "Namespace $NAMESPACE does not exist"
    
    # Delete namespace (this will delete all resources in it)
    if kubectl get namespace $NAMESPACE 2>/dev/null; then
        log "Deleting namespace $NAMESPACE and all resources..."
        kubectl delete namespace $NAMESPACE --timeout=60s
    else
        warn "Namespace $NAMESPACE does not exist"
    fi
    
    # Delete the Kind cluster
    log "Deleting Kind cluster: $CLUSTER_NAME"
    kind delete cluster --name $CLUSTER_NAME
    
    # Clean up temporary files
    log "Cleaning up temporary files..."
    rm -f /tmp/seed-configmap.yaml
    rm -f deploy/sample-seed.json
    
    log "Cleanup completed successfully!"
}

# Show help
show_help() {
    echo "MCP Registry Cleanup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -f, --force   Force cleanup without confirmation"
    echo ""
    echo "This script will:"
    echo "  1. Delete the namespace '$NAMESPACE' and all resources"
    echo "  2. Delete the Kind cluster '$CLUSTER_NAME'"
    echo "  3. Clean up temporary files"
}

# Confirm cleanup
confirm_cleanup() {
    echo -e "${YELLOW}WARNING: This will completely remove the MCP Registry deployment and Kind cluster.${NC}"
    echo ""
    echo "This action will delete:"
    echo "  - Kind cluster: $CLUSTER_NAME"
    echo "  - Namespace: $NAMESPACE"
    echo "  - All PostgreSQL data"
    echo "  - All MCP Registry data"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
}

# Parse command line arguments
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    if [ "$FORCE" = false ]; then
        confirm_cleanup
    fi
    
    cleanup
}

# Run main function
main "$@"
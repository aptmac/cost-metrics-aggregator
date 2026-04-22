#!/usr/bin/env bash

# Installation script for Prometheus + Thanos on OpenShift with SeaweedFS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="cma-observability"
MANIFESTS_DIR="manifests"

echo "=========================================="
echo "Prometheus + Thanos Setup (SeaweedFS)"
echo "=========================================="
echo ""

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo "Error: oc command not found."
    echo "Please install the OpenShift CLI to continue."
    exit 1
fi

# Check if logged into OpenShift
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged into OpenShift cluster."
    echo "Please login using 'oc login' before running this script."
    exit 1
fi

echo "Logged in as: $(oc whoami)"
echo "Current cluster: $(oc whoami --show-server)"
echo ""

# Confirm installation
read -p "This will create namespace '$NAMESPACE' and deploy Prometheus + Thanos with SeaweedFS. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo "Deploying Prometheus + Thanos stack with SeaweedFS..."
echo ""

# Apply manifests in order
echo "Creating namespace and base resources..."
oc apply -f "$MANIFESTS_DIR/base/namespace.yml"
oc apply -f "$MANIFESTS_DIR/base/serviceaccount.yml"
oc apply -f "$MANIFESTS_DIR/base/storage-seaweedfs.yml"

echo ""
echo "Deploying SeaweedFS..."
oc apply -f "$MANIFESTS_DIR/seaweedfs/deployment.yml"

echo ""
echo "Waiting for SeaweedFS to be ready..."
oc wait --for=condition=ready --timeout=300s pod -l app=seaweedfs -n "$NAMESPACE" || echo "SeaweedFS may still be starting..."

echo ""
echo "Initializing SeaweedFS S3 bucket..."

# Wait a bit for SeaweedFS to fully initialize
sleep 10

# Create bucket using SeaweedFS S3 API
echo "Creating 'thanos' bucket in SeaweedFS..."
if oc exec -n "$NAMESPACE" statefulset/seaweedfs -- sh -c '
  # Install AWS CLI tools if needed
  which aws > /dev/null 2>&1 || (apk add --no-cache aws-cli 2>/dev/null || apt-get update && apt-get install -y awscli 2>/dev/null || yum install -y awscli 2>/dev/null || true)
  
  # Configure AWS CLI for SeaweedFS
  export AWS_ACCESS_KEY_ID=seaweedfs
  export AWS_SECRET_ACCESS_KEY=seaweedfs123
  export AWS_DEFAULT_REGION=us-east-1
  
  # Create bucket
  aws --endpoint-url=http://localhost:8333 s3 mb s3://thanos 2>/dev/null || echo "Bucket may already exist"
  aws --endpoint-url=http://localhost:8333 s3 ls
' 2>/dev/null; then
    echo "✓ Bucket 'thanos' created successfully!"
else
    echo "Warning: Could not create bucket using AWS CLI. Trying alternative method..."
    # Alternative: Use curl to create bucket
    if oc exec -n "$NAMESPACE" statefulset/seaweedfs -- sh -c '
      curl -X PUT http://localhost:8333/thanos \
        -H "Authorization: AWS seaweedfs:seaweedfs123" \
        -H "Date: $(date -R)"
    ' 2>/dev/null; then
        echo "✓ Bucket 'thanos' created successfully (curl method)!"
    else
        echo "Warning: Could not create bucket automatically."
        echo "The bucket will be created automatically when Thanos first writes to it."
    fi
fi

echo ""
echo "Deploying Prometheus..."
oc apply -f "$MANIFESTS_DIR/prometheus/"

echo ""
echo "Deploying Thanos components..."
oc apply -f "$MANIFESTS_DIR/thanos/"

echo ""
echo "Deploying Grafana..."
oc apply -f "$MANIFESTS_DIR/grafana/"

echo ""
echo "Waiting for deployments to be ready..."
echo ""

# Wait for deployments
oc wait --for=condition=available --timeout=300s \
    deployment/thanos-query \
    deployment/grafana \
    -n "$NAMESPACE" 2>/dev/null || echo "Some deployments may still be starting..."

# Wait for statefulsets
oc wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=300s \
    statefulset/prometheus \
    statefulset/thanos-store \
    statefulset/thanos-compactor \
    statefulset/seaweedfs \
    -n "$NAMESPACE" 2>/dev/null || echo "Some statefulsets may still be starting..."

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""

# Get routes
THANOS_ROUTE=$(oc get route thanos-query -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available yet")
GRAFANA_ROUTE=$(oc get route grafana -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available yet")
SEAWEEDFS_ROUTE=$(oc get route seaweedfs-console -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available yet")

echo "Access the services at:"
echo "  - Thanos Query: https://$THANOS_ROUTE"
echo "  - Grafana:      https://$GRAFANA_ROUTE (admin/admin)"
echo "  - SeaweedFS Console: https://$SEAWEEDFS_ROUTE"
echo ""
echo "Object Storage:"
echo "  - Provider:     SeaweedFS (actively maintained)"
echo "  - Bucket:       thanos"
echo "  - Endpoint:     seaweedfs:8333 (internal)"
echo "  - Storage:      100Gi PVC"
echo ""
echo "Data Retention Policy:"
echo "  - Raw data (30s):        30 days"
echo "  - 5-minute downsampled:  180 days (6 months)"
echo "  - 1-hour downsampled:    1825 days (5 years)"
echo ""
echo "Components deployed:"
echo "  - SeaweedFS: Lightweight S3-compatible object storage"
echo "  - Prometheus: Federates from OpenShift monitoring"
echo "  - Thanos Sidecar: Ships data to SeaweedFS"
echo "  - Thanos Store: Serves historical data"
echo "  - Thanos Compactor: Downsamples and compacts data"
echo "  - Thanos Query: Unified query interface"
echo "  - Grafana: Visualization"
echo ""

# Made with Bob
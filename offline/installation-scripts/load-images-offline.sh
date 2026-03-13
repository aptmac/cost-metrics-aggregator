#!/usr/bin/env bash

set -e

# AI-ASSISTED: Bob 1.0.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for required environment variables
if [ -z "${INTERNAL_REGISTRY}" ]; then
    echo -e "${RED}Error: INTERNAL_REGISTRY environment variable is not set${NC}"
    echo "Example: export INTERNAL_REGISTRY=your-registry.example.com"
    exit 1
fi

INTERNAL_REGISTRY_NAMESPACE="${INTERNAL_REGISTRY_NAMESPACE:-cost-metrics}"

echo -e "${GREEN}Loading images to internal registry: ${INTERNAL_REGISTRY}${NC}"
echo -e "${YELLOW}Note: Using --tls-verify=false for CRC self-signed certificates${NC}"
echo ""

# Create namespace in OpenShift if it doesn't exist
echo -e "${YELLOW}Creating namespace ${INTERNAL_REGISTRY_NAMESPACE} if it doesn't exist...${NC}"
oc create namespace ${INTERNAL_REGISTRY_NAMESPACE} 2>/dev/null || echo "Namespace already exists"
echo ""

# Set environment variable to skip TLS verification globally for this script
export REGISTRY_AUTH_FILE=${XDG_RUNTIME_DIR}/containers/auth.json

# Image mappings
declare -A IMAGE_MAP=(
    ["cost-metrics-aggregator.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cost-metrics-aggregator:latest"
    ["postgresql-15.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/postgresql-15:latest"
    ["ubi9-go-toolset.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/ubi9-go-toolset:1.21"
    ["ubi9-minimal.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/ubi9-minimal:latest"
    ["grafana.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/grafana:11.4.0"
    ["koku-metrics-operator.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/koku-metrics-operator:latest"
)

IMAGES_DIR="../images"

for tar_file in "${!IMAGE_MAP[@]}"; do
    target_image="${IMAGE_MAP[$tar_file]}"
    tar_path="${IMAGES_DIR}/${tar_file}"
    
    if [ ! -f "${tar_path}" ]; then
        echo -e "${YELLOW}Warning: ${tar_path} not found, skipping...${NC}"
        continue
    fi
    
    echo -e "${YELLOW}Processing ${tar_file}...${NC}"
    
    # Load image from tar
    echo "  Loading image from tar..."
    podman load -i "${tar_path}"
    
    # Get the loaded image name
    loaded_image=$(podman load -i "${tar_path}" 2>&1 | grep "Loaded image" | awk '{print $NF}' || podman images --format "{{.Repository}}:{{.Tag}}" | head -1)
    
    # Tag for internal registry
    echo "  Tagging as ${target_image}..."
    podman tag "${loaded_image}" "${target_image}"
    
    # Push to internal registry
    echo "  Pushing to internal registry..."
    # Use --tls-verify=false for CRC's self-signed certificates
    # Also retry once if it fails
    if podman push "${target_image}" --tls-verify=false 2>&1; then
        echo -e "${GREEN}  ✓ Successfully pushed ${tar_file}${NC}"
    else
        echo -e "${YELLOW}  Retrying push...${NC}"
        sleep 2
        if podman push "${target_image}" --tls-verify=false 2>&1; then
            echo -e "${GREEN}  ✓ Successfully pushed ${tar_file} (retry)${NC}"
        else
            echo -e "${RED}  ✗ Failed to push ${tar_file}${NC}"
            echo -e "${YELLOW}  Try running: podman push ${target_image} --tls-verify=false${NC}"
        fi
    fi
    echo ""
done

echo -e "${GREEN}Image loading complete!${NC}"

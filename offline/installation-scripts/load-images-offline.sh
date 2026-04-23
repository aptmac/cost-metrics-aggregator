#!/usr/bin/env bash

# AI-ASSISTED: Bob 1.0.1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for required environment variables
if [ -z "${INTERNAL_REGISTRY}" ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Error: Required environment variables not set${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "Before running this script, you must set:"
    echo ""
    echo -e "${YELLOW}Required:${NC}"
    echo -e "  ${BLUE}export INTERNAL_REGISTRY=<your-registry-url>${NC}"
    echo -e "  Example: export INTERNAL_REGISTRY=default-route-openshift-image-registry.apps-crc.testing"
    echo ""
    echo -e "${YELLOW}Optional:${NC}"
    echo -e "  ${BLUE}export INTERNAL_REGISTRY_NAMESPACE=<namespace>${NC}"
    echo -e "  Default: cost-metrics"
    echo ""
    echo -e "${YELLOW}For OpenShift/CRC:${NC}"
    echo -e "  1. Get the registry route:"
    echo -e "     ${BLUE}oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}'${NC}"
    echo -e "  2. Login to the registry:"
    echo -e "     ${BLUE}podman login \$INTERNAL_REGISTRY --tls-verify=false${NC}"
    echo -e "  3. Set the environment variable:"
    echo -e "     ${BLUE}export INTERNAL_REGISTRY=<route-from-step-1>${NC}"
    echo ""
    exit 1
fi

INTERNAL_REGISTRY_NAMESPACE="${INTERNAL_REGISTRY_NAMESPACE:-cost-metrics}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Loading Images to Internal Registry${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Registry: ${BLUE}${INTERNAL_REGISTRY}${NC}"
echo -e "Namespace: ${BLUE}${INTERNAL_REGISTRY_NAMESPACE}${NC}"
echo -e "${YELLOW}Note: Using --tls-verify=false for self-signed certificates${NC}"
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
    ["postgresql-16.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/postgresql-16:latest"
    ["grafana.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/grafana:11.4.0"
    ["koku-metrics-operator.tar"]="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/koku-metrics-operator:latest"
)

IMAGES_DIR="../images"

# Track success/failure
LOADED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for tar_file in "${!IMAGE_MAP[@]}"; do
    target_image="${IMAGE_MAP[$tar_file]}"
    tar_path="${IMAGES_DIR}/${tar_file}"
    
    if [ ! -f "${tar_path}" ]; then
        echo -e "${YELLOW}Warning: ${tar_path} not found, skipping...${NC}"
        ((SKIPPED_COUNT++))
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
        ((LOADED_COUNT++))
    else
        echo -e "${YELLOW}  Retrying push...${NC}"
        sleep 2
        if podman push "${target_image}" --tls-verify=false 2>&1; then
            echo -e "${GREEN}  ✓ Successfully pushed ${tar_file} (retry)${NC}"
            ((LOADED_COUNT++))
        else
            echo -e "${RED}  ✗ Failed to push ${tar_file}${NC}"
            echo -e "${YELLOW}  Try running: podman push ${target_image} --tls-verify=false${NC}"
            ((FAILED_COUNT++))
        fi
    fi
    echo ""
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Image Loading Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Successfully loaded: ${GREEN}${LOADED_COUNT}${NC}"
echo -e "Failed: ${RED}${FAILED_COUNT}${NC}"
echo -e "Skipped: ${YELLOW}${SKIPPED_COUNT}${NC}"
echo ""

if [ ${LOADED_COUNT} -eq 0 ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}No images were loaded!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo ""
    echo -e "1. Verify you're logged into the registry:"
    echo -e "   ${BLUE}podman login \${INTERNAL_REGISTRY} --tls-verify=false${NC}"
    echo ""
    echo -e "2. Check if the registry route is accessible:"
    echo -e "   ${BLUE}curl -k https://\${INTERNAL_REGISTRY}/v2/${NC}"
    echo ""
    echo -e "3. Verify the images directory exists:"
    echo -e "   ${BLUE}ls -la ${IMAGES_DIR}/${NC}"
    echo ""
    echo -e "4. Ensure environment variables are set:"
    echo -e "   ${BLUE}echo \$INTERNAL_REGISTRY${NC}"
    echo -e "   ${BLUE}echo \$INTERNAL_REGISTRY_NAMESPACE${NC}"
    echo ""
    exit 1
elif [ ${FAILED_COUNT} -gt 0 ]; then
    echo -e "${YELLOW}Some images failed to load. Check the errors above.${NC}"
    exit 1
else
    echo -e "${GREEN}All images loaded successfully!${NC}"
fi

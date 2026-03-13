#!/usr/bin/env bash

set -e

# AI-ASSISTED: Bob 1.0.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUNDLE_DIR="demo-apps-bundle"
IMAGES_DIR="${BUNDLE_DIR}/images"
HELM_DIR="${BUNDLE_DIR}/helm-charts"
SCRIPTS_DIR="${BUNDLE_DIR}/scripts"
CONFIG_DIR="${BUNDLE_DIR}/configuration"

# Demo application container images
declare -A IMAGES=(
    ["cryostat"]="quay.io/cryostat/cryostat:4.1.1"
    ["cryostat-grafana"]="quay.io/cryostat/cryostat-grafana-dashboard:4.1.1"
    ["cryostat-reports"]="quay.io/cryostat/cryostat-reports:4.1.1"
    ["cryostat-db"]="quay.io/cryostat/cryostat-db:4.1.1"
    ["cryostat-storage"]="quay.io/cryostat/cryostat-storage:4.1.1"
    ["jfr-datasource"]="quay.io/cryostat/jfr-datasource:4.1.1"
    ["oauth2-proxy"]="quay.io/oauth2-proxy/oauth2-proxy:v7.14.3"
    ["eap74-openjdk11"]="registry.redhat.io/jboss-eap-7/eap74-openjdk11-openshift-rhel8:latest"
)

# Helm charts for demo applications
declare -A HELM_CHARTS=(
    ["cryostat"]="cryostat-charts/cryostat"
    ["eap74"]="openshift-helm-charts/redhat-eap74"
)

# Helm repositories
declare -A HELM_REPOS=(
    ["cryostat-charts"]="https://cryostat.io/helm-charts"
    ["openshift-helm-charts"]="https://charts.openshift.io"
)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Demo Applications${NC}"
echo -e "${GREEN}Offline Bundle Preparation Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}This bundle includes:${NC}"
echo "  - Cryostat (JVM monitoring)"
echo "  - EAP 7.4 (sample application)"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

command -v podman >/dev/null 2>&1 || { echo -e "${RED}Error: podman is required but not installed.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is required but not installed.${NC}" >&2; exit 1; }

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Important note about Red Hat Registry authentication
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}NOTE: Red Hat Registry Authentication${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "This script pulls from ${YELLOW}registry.redhat.io${NC}"
echo -e ""
echo -e "If you haven't logged in yet, run:"
echo -e "  ${YELLOW}podman login registry.redhat.io${NC}"
echo -e ""
echo -e "Use your Red Hat Customer Portal credentials."
echo -e "${BLUE}========================================${NC}"
echo ""
sleep 2

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p "${IMAGES_DIR}" "${HELM_DIR}" "${SCRIPTS_DIR}" "${CONFIG_DIR}"
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Pull and save container images
echo -e "${YELLOW}Pulling and saving container images...${NC}"
for name in "${!IMAGES[@]}"; do
    image="${IMAGES[$name]}"
    echo -e "  Pulling ${image}..."
    
    if podman pull "${image}"; then
        echo -e "  Saving ${name} to tar archive..."
        podman save -o "${IMAGES_DIR}/${name}.tar" "${image}"
        echo -e "${GREEN}  ✓ ${name} saved${NC}"
    else
        echo -e "${RED}  ✗ Failed to pull ${image}${NC}"
        echo -e "${YELLOW}  Continuing with other images...${NC}"
    fi
    echo ""
done

# Download Helm charts
echo -e "${YELLOW}Downloading Helm charts...${NC}"

# Add Helm repositories
for repo_name in "${!HELM_REPOS[@]}"; do
    repo_url="${HELM_REPOS[$repo_name]}"
    echo -e "  Adding Helm repo: ${repo_name}"
    helm repo add "${repo_name}" "${repo_url}" 2>/dev/null || true
done

echo -e "  Updating Helm repositories..."
helm repo update

# Download charts
for chart_name in "${!HELM_CHARTS[@]}"; do
    chart="${HELM_CHARTS[$chart_name]}"
    echo -e "  Downloading ${chart}..."
    
    if helm pull "${chart}" -d "${HELM_DIR}"; then
        echo -e "${GREEN}  ✓ ${chart_name} downloaded${NC}"
    else
        echo -e "${RED}  ✗ Failed to download ${chart}${NC}"
    fi
done
echo ""

# Copy installation scripts
echo -e "${YELLOW}Copying installation scripts...${NC}"
cp installation-scripts/*.sh "${SCRIPTS_DIR}/"
chmod +x "${SCRIPTS_DIR}"/*.sh
echo -e "${GREEN}✓ Installation scripts copied${NC}"
echo ""

# Copy configuration files
echo -e "${YELLOW}Copying configuration files...${NC}"
cp configuration/*.yaml "${CONFIG_DIR}/"
echo -e "${GREEN}✓ Configuration files copied${NC}"
echo ""

# Create a summary file
cat > "${BUNDLE_DIR}/bundle-info.txt" << EOF
Demo Applications Offline Bundle
=================================
Created: $(date)
Bundle Directory: ${BUNDLE_DIR}

Container Images:
EOF

for name in "${!IMAGES[@]}"; do
    image="${IMAGES[$name]}"
    if [ -f "${IMAGES_DIR}/${name}.tar" ]; then
        size=$(du -h "${IMAGES_DIR}/${name}.tar" | cut -f1)
        echo "  ✓ ${name}: ${image} (${size})" >> "${BUNDLE_DIR}/bundle-info.txt"
    else
        echo "  ✗ ${name}: ${image} (FAILED)" >> "${BUNDLE_DIR}/bundle-info.txt"
    fi
done

echo "" >> "${BUNDLE_DIR}/bundle-info.txt"
echo "Helm Charts:" >> "${BUNDLE_DIR}/bundle-info.txt"

for chart_name in "${!HELM_CHARTS[@]}"; do
    chart_file=$(ls "${HELM_DIR}/${chart_name}"*.tgz 2>/dev/null | head -1)
    if [ -n "${chart_file}" ]; then
        size=$(du -h "${chart_file}" | cut -f1)
        echo "  ✓ ${chart_name}: $(basename ${chart_file}) (${size})" >> "${BUNDLE_DIR}/bundle-info.txt"
    else
        echo "  ✗ ${chart_name}: (FAILED)" >> "${BUNDLE_DIR}/bundle-info.txt"
    fi
done

echo "" >> "${BUNDLE_DIR}/bundle-info.txt"
echo "Total Bundle Size: $(du -sh ${BUNDLE_DIR} | cut -f1)" >> "${BUNDLE_DIR}/bundle-info.txt"

# Display summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Demo Bundle Preparation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
cat "${BUNDLE_DIR}/bundle-info.txt"
echo ""
echo -e "${GREEN}Bundle location: $(pwd)/${BUNDLE_DIR}${NC}"
echo ""

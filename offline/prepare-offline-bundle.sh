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
BUNDLE_DIR="offline-bundle"
IMAGES_DIR="${BUNDLE_DIR}/images"
HELM_DIR="${BUNDLE_DIR}/helm-charts"
GO_DIR="${BUNDLE_DIR}/go-dependencies"
SCRIPTS_DIR="${BUNDLE_DIR}/scripts"
MANIFESTS_DIR="${BUNDLE_DIR}/manifests"

# Container images to mirror (core components only)
declare -A IMAGES=(
    ["cost-metrics-aggregator"]="quay.io/almacdon/cost-metrics-aggregator:latest"
    ["postgresql-16"]="registry.redhat.io/rhel9/postgresql-16:latest"
    ["ubi9-go-toolset"]="registry.access.redhat.com/ubi9/go-toolset:1.21"
    ["ubi9-minimal"]="registry.access.redhat.com/ubi9/ubi-minimal:latest"
    ["grafana"]="docker.io/grafana/grafana:11.4.0"
    ["koku-metrics-operator"]="quay.io/project-koku/koku-metrics-operator:latest"
)

# Helm charts to download (core components only)
declare -A HELM_CHARTS=(
    ["grafana"]="grafana/grafana"
)

# Helm repositories
declare -A HELM_REPOS=(
    ["grafana"]="https://grafana.github.io/helm-charts"
)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cost Metrics Aggregator${NC}"
echo -e "${GREEN}Offline Bundle Preparation Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

command -v podman >/dev/null 2>&1 || { echo -e "${RED}Error: podman is required but not installed.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is required but not installed.${NC}" >&2; exit 1; }
command -v go >/dev/null 2>&1 || { echo -e "${RED}Warning: go is not installed. Skipping Go dependency vendoring.${NC}" >&2; }

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
mkdir -p "${IMAGES_DIR}" "${HELM_DIR}" "${GO_DIR}" "${SCRIPTS_DIR}" "${MANIFESTS_DIR}"
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

# Package Go dependencies
echo -e "${YELLOW}Packaging Go dependencies...${NC}"
if command -v go >/dev/null 2>&1; then
    # Save current directory
    CURRENT_DIR=$(pwd)
    
    # Copy go.mod and go.sum
    if [ -f "../go.mod" ]; then
        cp ../go.mod "${GO_DIR}/"
        echo -e "  ✓ Copied go.mod"
    fi
    
    if [ -f "../go.sum" ]; then
        cp ../go.sum "${GO_DIR}/"
        echo -e "  ✓ Copied go.sum"
    fi
    
    # Vendor dependencies
    echo -e "  Vendoring Go dependencies..."
    cd ..
    if go mod vendor; then
        # Use absolute path for GO_DIR
        cp -r vendor "${CURRENT_DIR}/${GO_DIR}/"
        echo -e "${GREEN}  ✓ Go dependencies vendored${NC}"
        
        # Clean up vendor directory from source
        echo -e "  Cleaning up vendor directory..."
        rm -rf vendor
        echo -e "${GREEN}  ✓ Vendor directory removed${NC}"
    else
        echo -e "${YELLOW}  Warning: Failed to vendor dependencies${NC}"
    fi
    cd "${CURRENT_DIR}"
else
    echo -e "${YELLOW}  Skipping Go dependency vendoring (go not installed)${NC}"
fi
echo ""

# Copy deployment manifests
echo -e "${YELLOW}Copying deployment manifests...${NC}"
cp -r ../deploy/* "${MANIFESTS_DIR}/"
cp configuration/CostManagementMetricsConfig.yml "${MANIFESTS_DIR}/"
cp configuration/cost-metrics-db-secret.yml "${MANIFESTS_DIR}/"
echo -e "${GREEN}✓ Manifests copied (including secret)${NC}"
echo ""

# Copy SSL certificate generation script
echo -e "${YELLOW}Copying SSL certificate generation script...${NC}"
if [ -f "../scripts/generate-ssl-certs.sh" ]; then
    cp ../scripts/generate-ssl-certs.sh "${SCRIPTS_DIR}/"
    chmod +x "${SCRIPTS_DIR}/generate-ssl-certs.sh"
    echo -e "${GREEN}✓ SSL certificate script copied${NC}"
else
    echo -e "${YELLOW}Warning: SSL certificate script not found${NC}"
fi
echo ""

# Copy offline installation scripts
echo -e "${YELLOW}Copying offline installation scripts...${NC}"
cp installation-scripts/*.sh "${SCRIPTS_DIR}/"
chmod +x "${SCRIPTS_DIR}"/*.sh
echo -e "${GREEN}✓ Installation scripts copied${NC}"
echo ""

# Copy configuration files (core only, no demo apps)
echo -e "${YELLOW}Copying configuration files...${NC}"
mkdir -p "${BUNDLE_DIR}/configuration"
cp configuration/grafana-openshift-values.yaml "${BUNDLE_DIR}/configuration/" 2>/dev/null || true
echo -e "${GREEN}✓ Configuration files copied${NC}"
echo ""

# Copy Grafana dashboard
echo -e "${YELLOW}Copying Grafana dashboard...${NC}"
mkdir -p "${BUNDLE_DIR}/grafana"
if [ -f "../grafana/dashboard.json" ]; then
    cp ../grafana/dashboard.json "${BUNDLE_DIR}/grafana/"
    echo -e "${GREEN}✓ Grafana dashboard copied${NC}"
else
    echo -e "${YELLOW}Warning: Grafana dashboard not found at ../grafana/dashboard.json${NC}"
fi
echo ""

# Create a summary file
cat > "${BUNDLE_DIR}/bundle-info.txt" << EOF
Offline Bundle Creation Summary
================================
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
echo -e "${GREEN}Bundle Preparation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
cat "${BUNDLE_DIR}/bundle-info.txt"
echo ""
echo -e "${GREEN}Bundle location: $(pwd)/${BUNDLE_DIR}${NC}"

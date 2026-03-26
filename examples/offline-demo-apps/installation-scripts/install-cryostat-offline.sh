#!/usr/bin/env bash

set -e

# AI-ASSISTED: Bob 1.0.0

NAMESPACE="cryostat"
HELM_DIR="../helm-charts"

echo "Installing Cryostat (Offline Mode)"
echo ""

oc new-project ${NAMESPACE} 2>/dev/null || oc project ${NAMESPACE}

# Create image pull secret for internal registry
if [ -n "${INTERNAL_REGISTRY}" ]; then
    echo "Creating image pull secret for Cryostat..."
    oc create secret docker-registry cryostat-registry-pull-secret \
      --docker-server=${INTERNAL_REGISTRY} \
      --docker-username=kubeadmin \
      --docker-password=$(oc whoami -t) \
      -n ${NAMESPACE} 2>/dev/null || echo "Secret already exists"
    
    oc secrets link default cryostat-registry-pull-secret --for=pull -n ${NAMESPACE} 2>/dev/null || true
fi

# Find the Cryostat chart
CRYOSTAT_CHART=$(ls ${HELM_DIR}/cryostat-*.tgz | head -1)

if [ -z "${CRYOSTAT_CHART}" ]; then
    echo "Error: Cryostat chart not found in ${HELM_DIR}"
    exit 1
fi

# Check for environment variables for internal registry
if [ -z "${INTERNAL_REGISTRY}" ] || [ -z "${INTERNAL_REGISTRY_NAMESPACE}" ]; then
    echo "Warning: INTERNAL_REGISTRY or INTERNAL_REGISTRY_NAMESPACE not set"
    echo "Cryostat will try to pull from quay.io (requires internet)"
    CRYOSTAT_CORE_IMAGE="quay.io/cryostat/cryostat"
    CRYOSTAT_GRAFANA_IMAGE="quay.io/cryostat/cryostat-grafana-dashboard"
    CRYOSTAT_REPORTS_IMAGE="quay.io/cryostat/cryostat-reports"
    CRYOSTAT_DB_IMAGE="quay.io/cryostat/cryostat-db"
    CRYOSTAT_STORAGE_IMAGE="quay.io/cryostat/cryostat-storage"
    JFR_DATASOURCE_IMAGE="quay.io/cryostat/jfr-datasource"
    OAUTH2_PROXY_IMAGE="quay.io/oauth2-proxy/oauth2-proxy"
else
    CRYOSTAT_CORE_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cryostat"
    CRYOSTAT_GRAFANA_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cryostat-grafana-dashboard"
    CRYOSTAT_REPORTS_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cryostat-reports"
    CRYOSTAT_DB_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cryostat-db"
    CRYOSTAT_STORAGE_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cryostat-storage"
    JFR_DATASOURCE_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/jfr-datasource"
    OAUTH2_PROXY_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/oauth2-proxy"
    echo "Using internal registry images"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configuration"

# Use the external values file
VALUES_FILE="${CONFIG_DIR}/cryostat-offline-values.yaml"

# Create a temporary values file with the correct images
TEMP_VALUES=$(mktemp)
trap "rm -f ${TEMP_VALUES}" EXIT

# Replace the placeholders in the values file
sed -e "s|{{CRYOSTAT_CORE_IMAGE}}|${CRYOSTAT_CORE_IMAGE}|g" \
    -e "s|{{CRYOSTAT_GRAFANA_IMAGE}}|${CRYOSTAT_GRAFANA_IMAGE}|g" \
    -e "s|{{CRYOSTAT_REPORTS_IMAGE}}|${CRYOSTAT_REPORTS_IMAGE}|g" \
    -e "s|{{CRYOSTAT_DB_IMAGE}}|${CRYOSTAT_DB_IMAGE}|g" \
    -e "s|{{CRYOSTAT_STORAGE_IMAGE}}|${CRYOSTAT_STORAGE_IMAGE}|g" \
    -e "s|{{JFR_DATASOURCE_IMAGE}}|${JFR_DATASOURCE_IMAGE}|g" \
    -e "s|{{OAUTH2_PROXY_IMAGE}}|${OAUTH2_PROXY_IMAGE}|g" \
    "${VALUES_FILE}" > "${TEMP_VALUES}"

echo "Installing from: ${CRYOSTAT_CHART}"
helm install cryostat "${CRYOSTAT_CHART}" -n ${NAMESPACE} -f "${TEMP_VALUES}"

# Add rht.comp label
echo "Adding rht.comp label..."
oc patch deployment cryostat-v4 -n ${NAMESPACE} --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"rht.comp":"Cryostat"}}}}}'

echo ""
echo "Cryostat installation complete!"

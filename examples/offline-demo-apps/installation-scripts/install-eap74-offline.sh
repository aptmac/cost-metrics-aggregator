#!/usr/bin/env bash

set -e

# AI-ASSISTED: Bob 1.0.0

NAMESPACE="eap74"
HELM_DIR="../helm-charts"

echo "Installing EAP 7.4 Helloworld (Offline Mode)"
echo ""

oc new-project ${NAMESPACE} 2>/dev/null || oc project ${NAMESPACE}

# Create image pull secret for internal registry
if [ -n "${INTERNAL_REGISTRY}" ]; then
    echo "Creating image pull secret for EAP 7.4..."
    oc create secret docker-registry eap74-registry-pull-secret \
      --docker-server=${INTERNAL_REGISTRY} \
      --docker-username=kubeadmin \
      --docker-password=$(oc whoami -t) \
      -n ${NAMESPACE} 2>/dev/null || echo "Secret already exists"
    
    oc secrets link default eap74-registry-pull-secret --for=pull -n ${NAMESPACE} 2>/dev/null || true
fi

# Find the EAP 7.4 chart
EAP74_CHART=$(ls ${HELM_DIR}/eap74-*.tgz | head -1)

if [ -z "${EAP74_CHART}" ]; then
    echo "Error: EAP 7.4 chart not found in ${HELM_DIR}"
    exit 1
fi

# Check for environment variables for internal registry
if [ -z "${INTERNAL_REGISTRY}" ] || [ -z "${INTERNAL_REGISTRY_NAMESPACE}" ]; then
    echo "Warning: INTERNAL_REGISTRY or INTERNAL_REGISTRY_NAMESPACE not set"
    echo "EAP 7.4 will try to pull from registry.redhat.io (requires internet)"
    EAP_IMAGE="registry.redhat.io/jboss-eap-7/eap74-openjdk11-openshift-rhel8"
else
    EAP_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/eap74-openjdk11-openshift-rhel8"
    echo "Using internal registry image: ${EAP_IMAGE}"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configuration"

# Use the external values file
VALUES_FILE="${CONFIG_DIR}/eap74-offline-values.yaml"

# Create a temporary values file with the correct image
TEMP_VALUES=$(mktemp)
trap "rm -f ${TEMP_VALUES}" EXIT

# Replace the placeholder in the values file
sed "s|{{EAP_IMAGE}}|${EAP_IMAGE}|g" "${VALUES_FILE}" > "${TEMP_VALUES}"

echo "Installing from: ${EAP74_CHART}"
helm install eap74-helloworld "${EAP74_CHART}" -n ${NAMESPACE} -f "${TEMP_VALUES}"

# Wait for deployment to be created
echo ""
echo "Waiting for EAP deployment..."
sleep 5

# Add rht.comp label to the deployment
echo "Adding rht.comp=EAP label..."
oc patch deployment eap74-helloworld -n ${NAMESPACE} --type='json' \
  -p='[{"op": "add", "path": "/spec/template/metadata/labels/rht.comp", "value": "EAP"}]' 2>/dev/null || \
  echo "Note: Deployment name might be different, check with: oc get deployments -n ${NAMESPACE}"

echo ""
echo "EAP 7.4 Helloworld installation complete!"
echo ""
echo "To access the application:"
echo "  oc get route -n ${NAMESPACE}"

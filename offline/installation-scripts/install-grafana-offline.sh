#!/usr/bin/env bash

set -e

# AI-ASSISTED: Bob 1.0.0

NAMESPACE="grafana"
HELM_DIR="../helm-charts"

echo "Installing Grafana (Offline Mode)"
echo ""

oc new-project ${NAMESPACE} 2>/dev/null || oc project ${NAMESPACE}

# Find the Grafana chart
GRAFANA_CHART=$(ls ${HELM_DIR}/grafana-*.tgz | head -1)

if [ -z "${GRAFANA_CHART}" ]; then
    echo "Error: Grafana chart not found in ${HELM_DIR}"
    exit 1
fi

# Set up permissions
echo "Setting up permissions for Grafana..."
oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z grafana -n ${NAMESPACE}

# Check for environment variables for internal registry
if [ -z "${INTERNAL_REGISTRY}" ] || [ -z "${INTERNAL_REGISTRY_NAMESPACE}" ]; then
    echo "Warning: INTERNAL_REGISTRY or INTERNAL_REGISTRY_NAMESPACE not set"
    echo "Grafana will try to pull from docker.io (requires internet)"
    GRAFANA_REGISTRY=""
    GRAFANA_REPOSITORY="grafana/grafana"
    GRAFANA_TAG="11.4.0"
else
    # For internal registry, we need to set registry and repository separately
    # to prevent Helm from prepending docker.io
    GRAFANA_REGISTRY="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}"
    GRAFANA_REPOSITORY="grafana"
    GRAFANA_TAG="11.4.0"
    echo "Using internal registry: ${GRAFANA_REGISTRY}/${GRAFANA_REPOSITORY}:${GRAFANA_TAG}"
fi

# Create image pull secret for internal registry
if [ -n "${INTERNAL_REGISTRY}" ]; then
    echo "Creating image pull secret for Grafana..."
    oc create secret docker-registry grafana-registry-pull-secret \
      --docker-server=${INTERNAL_REGISTRY} \
      --docker-username=kubeadmin \
      --docker-password=$(oc whoami -t) \
      -n ${NAMESPACE} 2>/dev/null || echo "Secret already exists"
    
    oc secrets link default grafana-registry-pull-secret --for=pull -n ${NAMESPACE} 2>/dev/null || true
    oc secrets link grafana grafana-registry-pull-secret --for=pull -n ${NAMESPACE} 2>/dev/null || true
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find the grafana values file
# When running from bundle, it's in ../manifests
# When running from repo, it's in ../../deploy/offline
if [ -f "${SCRIPT_DIR}/../manifests/grafana-openshift-values.yaml" ]; then
    VALUES_FILE="${SCRIPT_DIR}/../manifests/grafana-openshift-values.yaml"
elif [ -f "${SCRIPT_DIR}/../../deploy/offline/grafana-openshift-values.yaml" ]; then
    VALUES_FILE="${SCRIPT_DIR}/../../deploy/offline/grafana-openshift-values.yaml"
else
    echo "Error: grafana-openshift-values.yaml not found"
    exit 1
fi

# Create a temporary values file with the correct image
TEMP_VALUES=$(mktemp)
trap "rm -f ${TEMP_VALUES}" EXIT

# Replace the placeholders in the values file
sed -e "s|{{GRAFANA_REGISTRY}}|${GRAFANA_REGISTRY}|g" \
    -e "s|{{GRAFANA_REPOSITORY}}|${GRAFANA_REPOSITORY}|g" \
    -e "s|{{GRAFANA_TAG}}|${GRAFANA_TAG}|g" \
    "${VALUES_FILE}" > "${TEMP_VALUES}"

# Check if custom grafana-values.yml exists and merge
if [ -f "../../grafana/grafana-values.yml" ]; then
    echo "Installing from: ${GRAFANA_CHART} with custom and OpenShift values"
    helm install grafana "${GRAFANA_CHART}" -n ${NAMESPACE} \
      -f "${TEMP_VALUES}" \
      -f ../../grafana/grafana-values.yml
else
    echo "Installing from: ${GRAFANA_CHART} with OpenShift-compatible values"
    helm install grafana "${GRAFANA_CHART}" -n ${NAMESPACE} \
      -f "${TEMP_VALUES}"
fi

# Wait for Grafana ServiceAccount to be created by Helm
echo "Waiting for Grafana ServiceAccount to be created..."
sleep 5

# Ensure secret is linked to the grafana ServiceAccount (Helm creates this)
if oc get sa grafana -n ${NAMESPACE} 2>/dev/null; then
    echo "Linking secret to grafana ServiceAccount..."
    oc secrets link grafana grafana-registry-pull-secret --for=pull -n ${NAMESPACE} 2>/dev/null || true
fi

# Patch the deployment to ensure imagePullSecrets is set
echo "Patching deployment to ensure imagePullSecrets..."
oc patch deployment grafana -n ${NAMESPACE} --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "grafana-registry-pull-secret"}]}]' 2>/dev/null || true

# Restart the deployment to pick up changes
echo "Restarting Grafana deployment..."
oc rollout restart deployment/grafana -n ${NAMESPACE}

# Create service account token
TOKEN=$(oc create token grafana -n $NAMESPACE --duration=8760h)

# Create datasource ConfigMap
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-prometheus
  namespace: ${NAMESPACE}
  labels:
    grafana_datasource: "1"
data:
  prometheus-datasource.yaml: |
    apiVersion: 1
    datasources:
    - name: OpenShift Prometheus
      type: prometheus
      access: proxy
      url: https://thanos-querier.openshift-monitoring.svc:9091
      isDefault: true
      jsonData:
        httpMethod: GET
        tlsSkipVerify: true
        httpHeaderName1: 'Authorization'
      secureJsonData:
        httpHeaderValue1: 'Bearer ${TOKEN}'
      editable: false
EOF

# Mount datasource
oc set volume deployment/grafana -n ${NAMESPACE} \
  --add \
  --name=datasource-prometheus \
  --type=configmap \
  --configmap-name=grafana-datasource-prometheus \
  --mount-path=/etc/grafana/provisioning/datasources/prometheus-datasource.yaml \
  --sub-path=prometheus-datasource.yaml

echo ""
echo "Grafana installation complete!"
echo "Access Grafana by getting the route:"
echo "  oc get route -n ${NAMESPACE}"

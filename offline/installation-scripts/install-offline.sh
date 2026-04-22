#!/usr/bin/env bash

set -e

# AI-ASSISTED: Bob 1.0.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Complete Offline Installation${NC}"
echo -e "${GREEN}Cost Metrics Aggregator + Operator${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Configuration
OPERATOR_NAMESPACE="koku-metrics-operator"
AGGREGATOR_NAMESPACE="cost-metrics"

INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-default-route-openshift-image-registry.apps-crc.testing}"
INTERNAL_REGISTRY_NAMESPACE="${INTERNAL_REGISTRY_NAMESPACE:-cost-metrics}"

echo -e "${BLUE}Configuration:${NC}"
echo "  Operator Namespace: ${OPERATOR_NAMESPACE}"
echo "  Aggregator Namespace: ${AGGREGATOR_NAMESPACE}"
echo "  Internal Registry: ${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}"
echo ""

# ============================================
# STEP 1: Install Cost Metrics Aggregator
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STEP 1: Installing Cost Metrics Aggregator${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Creating namespace...${NC}"
oc create namespace ${AGGREGATOR_NAMESPACE} 2>/dev/null || echo "Namespace already exists"

echo -e "${YELLOW}Creating database secret...${NC}"
# Try bundle location first, then repo location
if [ -f "../manifests/cost-metrics-db-secret.yml" ]; then
    oc apply -f ../manifests/cost-metrics-db-secret.yml -n ${AGGREGATOR_NAMESPACE}
    echo -e "${GREEN}✓ Database secret created${NC}"
elif [ -f "../../deploy/postgres/cost-metrics-db-secret.yml" ]; then
    oc apply -f ../../deploy/postgres/cost-metrics-db-secret.yml -n ${AGGREGATOR_NAMESPACE}
    echo -e "${GREEN}✓ Database secret created${NC}"
elif [ -f "cost-metrics-db-secret.yml" ]; then
    oc apply -f cost-metrics-db-secret.yml -n ${AGGREGATOR_NAMESPACE}
    echo -e "${GREEN}✓ Database secret created${NC}"
else
    echo -e "${YELLOW}Creating default database secret...${NC}"
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cost-metrics-db
  namespace: ${AGGREGATOR_NAMESPACE}
type: Opaque
stringData:
  database-url: postgresql://costmetrics:costmetrics123@postgres:5432/costmetrics?sslmode=require
  postgres-password: costmetrics123
  POSTGRES_USER: costmetrics
  POSTGRES_PASSWORD: costmetrics123
  POSTGRES_DB: costmetrics
EOF
    echo -e "${GREEN}✓ Default database secret created${NC}"
fi

echo -e "${YELLOW}Applying manifests...${NC}"

# Determine the correct path to manifests
# When running from bundle, manifests are in ../manifests
# When running from repo, they're in ../../deploy/offline
if [ -d "../manifests" ]; then
    MANIFESTS_DIR="../manifests"
elif [ -d "../../deploy/offline" ]; then
    MANIFESTS_DIR="../../deploy/offline"
else
    echo -e "${RED}Error: Cannot find manifests directory${NC}"
    exit 1
fi

# Generate SSL certificates
echo -e "${YELLOW}Generating SSL certificates for PostgreSQL...${NC}"
CERT_SCRIPT="../../scripts/generate-ssl-certs.sh"
if [ -f "${CERT_SCRIPT}" ]; then
    bash "${CERT_SCRIPT}" ${AGGREGATOR_NAMESPACE}
    echo -e "${GREEN}✓ SSL certificates generated${NC}"
else
    echo -e "${YELLOW}Warning: SSL certificate script not found at ${CERT_SCRIPT}${NC}"
    echo -e "${YELLOW}Checking in bundle scripts directory...${NC}"
    if [ -f "generate-ssl-certs.sh" ]; then
        bash generate-ssl-certs.sh ${AGGREGATOR_NAMESPACE}
        echo -e "${GREEN}✓ SSL certificates generated${NC}"
    else
        echo -e "${YELLOW}SSL certificate script not found. SSL will not be enabled.${NC}"
        echo -e "${YELLOW}Run scripts/generate-ssl-certs.sh manually if needed.${NC}"
    fi
fi

# Apply SSL config if it exists
echo -e "${YELLOW}Applying SSL configuration...${NC}"
if [ -f "${MANIFESTS_DIR}/postgres-ssl-config.yml" ]; then
    oc apply -f "${MANIFESTS_DIR}/postgres-ssl-config.yml" -n ${AGGREGATOR_NAMESPACE}
    echo -e "${GREEN}✓ SSL configuration applied${NC}"
else
    echo -e "${YELLOW}Warning: postgres-ssl-config.yml not found in ${MANIFESTS_DIR}${NC}"
fi

# Update image references to use internal registry and apply
for file in postgres-deployment.yml deployment.yml; do
    if [ -f "${MANIFESTS_DIR}/$file" ]; then
        # Create temp file with substituted values
        sed "s|{{INTERNAL_REGISTRY}}|${INTERNAL_REGISTRY}|g; s|{{INTERNAL_REGISTRY_NAMESPACE}}|${INTERNAL_REGISTRY_NAMESPACE}|g" "${MANIFESTS_DIR}/$file" | \
        oc apply -f - -n ${AGGREGATOR_NAMESPACE}
    fi
done

# Apply other manifests
for file in service.yml route.yml; do
    if [ -f "${MANIFESTS_DIR}/$file" ]; then
        oc apply -f "${MANIFESTS_DIR}/$file" -n ${AGGREGATOR_NAMESPACE}
    elif [ -f "../../deploy/$file" ]; then
        oc apply -f "../../deploy/$file" -n ${AGGREGATOR_NAMESPACE}
    fi
done

echo -e "${GREEN}✓ Aggregator installed${NC}"
echo ""

echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
oc wait --for=condition=ready pod -l app=postgres -n ${AGGREGATOR_NAMESPACE} --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}Warning: PostgreSQL readiness check timed out or failed${NC}"
    echo -e "${YELLOW}Waiting 30 seconds for PostgreSQL to stabilize...${NC}"
    sleep 30
}
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

echo -e "${YELLOW}Waiting for Cost Metrics Aggregator to be ready...${NC}"
oc wait --for=condition=ready pod -l app=cost-metrics-aggregator -n ${AGGREGATOR_NAMESPACE} --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}Warning: Aggregator readiness check timed out or failed${NC}"
    echo -e "${YELLOW}Waiting 30 seconds for Aggregator to stabilize...${NC}"
    sleep 30
}
echo -e "${GREEN}✓ Cost Metrics Aggregator is ready${NC}"
echo ""

# ============================================
# STEP 2: Install Koku Metrics Operator
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STEP 2: Installing Koku Metrics Operator${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Creating namespace...${NC}"
oc create namespace ${OPERATOR_NAMESPACE} 2>/dev/null || echo "Namespace already exists"

echo -e "${YELLOW}Applying operator manifests...${NC}"
# Try bundle location first, then repo location
if [ -f "../manifests/operator-serviceaccount.yml" ]; then
    oc apply -f ../manifests/operator-serviceaccount.yml
    oc apply -f ../manifests/operator-clusterrole.yml
    oc apply -f ../manifests/operator-clusterrolebinding.yml
    oc apply -f ../manifests/operator-prometheus-rolebinding.yml
    oc apply -f ../manifests/operator-crd.yml
elif [ -f "../../deploy/operator/operator-serviceaccount.yml" ]; then
    oc apply -f ../../deploy/operator/operator-serviceaccount.yml
    oc apply -f ../../deploy/operator/operator-clusterrole.yml
    oc apply -f ../../deploy/operator/operator-clusterrolebinding.yml
    oc apply -f ../../deploy/operator/operator-prometheus-rolebinding.yml
    oc apply -f ../../deploy/operator/operator-crd.yml
fi

echo -e "${YELLOW}Creating image pull secret...${NC}"
oc create secret docker-registry koku-registry-pull-secret \
  --docker-server=${INTERNAL_REGISTRY} \
  --docker-username=kubeadmin \
  --docker-password=$(oc whoami -t) \
  -n ${OPERATOR_NAMESPACE} 2>/dev/null || echo "Secret already exists"

oc secrets link koku-metrics-operator koku-registry-pull-secret --for=pull -n ${OPERATOR_NAMESPACE} 2>/dev/null || true

echo -e "${YELLOW}Deploying Operator with internal registry...${NC}"
# Apply operator deployment with substituted registry values
if [ -f "${MANIFESTS_DIR}/operator-deployment.yml" ]; then
    sed "s|{{INTERNAL_REGISTRY}}|${INTERNAL_REGISTRY}|g; s|{{INTERNAL_REGISTRY_NAMESPACE}}|${INTERNAL_REGISTRY_NAMESPACE}|g" "${MANIFESTS_DIR}/operator-deployment.yml" | \
    oc apply -f - -n ${OPERATOR_NAMESPACE}
elif [ -f "../../deploy/offline/operator-deployment.yml" ]; then
    sed "s|{{INTERNAL_REGISTRY}}|${INTERNAL_REGISTRY}|g; s|{{INTERNAL_REGISTRY_NAMESPACE}}|${INTERNAL_REGISTRY_NAMESPACE}|g" "../../deploy/offline/operator-deployment.yml" | \
    oc apply -f - -n ${OPERATOR_NAMESPACE}
fi

echo -e "${GREEN}✓ Operator installed${NC}"
echo ""

echo -e "${YELLOW}Waiting for Koku Metrics Operator to be ready...${NC}"
oc wait --for=condition=ready pod -l name=koku-metrics-operator -n ${OPERATOR_NAMESPACE} --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}Warning: Operator readiness check timed out or failed${NC}"
    echo -e "${YELLOW}Waiting 30 seconds for Operator to stabilize...${NC}"
    sleep 30
}
echo -e "${GREEN}✓ Koku Metrics Operator is ready${NC}"
echo ""

# ============================================
# STEP 3: Apply Configuration
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STEP 3: Applying Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Applying CostManagementMetricsConfig...${NC}"

# Determine the correct path to the config file
if [ -f "../manifests/CostManagementMetricsConfig.yml" ]; then
    CONFIG_FILE="../manifests/CostManagementMetricsConfig.yml"
elif [ -f "../../deploy/operator/CostManagementMetricsConfig.yml" ]; then
    CONFIG_FILE="../../deploy/operator/CostManagementMetricsConfig.yml"
elif [ -f "CostManagementMetricsConfig.yml" ]; then
    CONFIG_FILE="CostManagementMetricsConfig.yml"
else
    echo -e "${YELLOW}Warning: CostManagementMetricsConfig.yml not found${NC}"
    echo "You'll need to create and apply your configuration manually"
    CONFIG_FILE=""
fi

if [ -n "${CONFIG_FILE}" ]; then
    oc apply -f "${CONFIG_FILE}" -n ${OPERATOR_NAMESPACE}
    echo -e "${GREEN}✓ Configuration applied${NC}"
fi

echo ""

# ============================================
# STEP 4: Verification
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STEP 4: Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}Checking aggregator status...${NC}"
oc get pods -n ${AGGREGATOR_NAMESPACE}
echo ""

echo -e "${YELLOW}Checking operator status...${NC}"
oc get pods -n ${OPERATOR_NAMESPACE}
echo ""

echo -e "${YELLOW}Checking CRDs...${NC}"
oc get crd | grep -E "(koku|cost)" || echo "No CRDs found"
echo ""

# ============================================
# Summary
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}All components installed successfully!${NC}"

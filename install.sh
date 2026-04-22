#!/usr/bin/env bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cost Metrics Aggregator Installation${NC}"
echo -e "${GREEN}Online Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Configuration
OPERATOR_NAMESPACE="koku-metrics-operator"
AGGREGATOR_NAMESPACE="cost-metrics"

echo -e "${BLUE}Configuration:${NC}"
echo "  Operator Namespace: ${OPERATOR_NAMESPACE}"
echo "  Aggregator Namespace: ${AGGREGATOR_NAMESPACE}"
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
oc apply -f deploy/cost-metrics-db-secret.yml -n ${AGGREGATOR_NAMESPACE}
echo -e "${GREEN}✓ Database secret created${NC}"

echo -e "${YELLOW}Generating SSL certificates for PostgreSQL...${NC}"
if [ -f "scripts/generate-ssl-certs.sh" ]; then
    bash scripts/generate-ssl-certs.sh ${AGGREGATOR_NAMESPACE}
    echo -e "${GREEN}✓ SSL certificates generated${NC}"
else
    echo -e "${YELLOW}Warning: SSL certificate script not found${NC}"
fi

echo -e "${YELLOW}Applying manifests...${NC}"
oc apply -f deploy/postgres-ssl-config.yml -n ${AGGREGATOR_NAMESPACE} 2>/dev/null || true
oc apply -f deploy/postgres-deployment.yml -n ${AGGREGATOR_NAMESPACE}
oc apply -f deploy/deployment.yml -n ${AGGREGATOR_NAMESPACE}
oc apply -f deploy/service.yml -n ${AGGREGATOR_NAMESPACE}
oc apply -f deploy/route.yml -n ${AGGREGATOR_NAMESPACE}

echo -e "${GREEN}✓ Aggregator installed${NC}"
echo ""

echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
oc wait --for=condition=ready pod -l app=postgres -n ${AGGREGATOR_NAMESPACE} --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}Warning: PostgreSQL readiness check timed out${NC}"
    sleep 30
}
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

echo -e "${YELLOW}Waiting for Cost Metrics Aggregator to be ready...${NC}"
oc wait --for=condition=ready pod -l app=cost-metrics-aggregator -n ${AGGREGATOR_NAMESPACE} --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}Warning: Aggregator readiness check timed out${NC}"
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
oc apply -f deploy/operator-serviceaccount.yml
oc apply -f deploy/operator-clusterrole.yml
oc apply -f deploy/operator-clusterrolebinding.yml
oc apply -f deploy/operator-prometheus-rolebinding.yml
oc apply -f deploy/operator-crd.yml
oc apply -f deploy/operator-deployment.yml

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

echo -e "${YELLOW}Waiting for operator to be ready...${NC}"
sleep 10

echo -e "${YELLOW}Applying CostManagementMetricsConfig...${NC}"
oc apply -f deploy/CostManagementMetricsConfig.yml -n ${OPERATOR_NAMESPACE}
echo -e "${GREEN}✓ Configuration applied${NC}"
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

# ============================================
# Summary
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"

# Made with Bob 1.0.1

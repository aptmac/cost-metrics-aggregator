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
if [ -f "../configuration/cost-metrics-db-secret.yml" ]; then
    oc apply -f ../configuration/cost-metrics-db-secret.yml -n ${AGGREGATOR_NAMESPACE}
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
  database-url: postgresql://costmetrics:costmetrics123@postgres:5432/costmetrics?sslmode=disable
  postgres-password: costmetrics123
  POSTGRES_USER: costmetrics
  POSTGRES_PASSWORD: costmetrics123
  POSTGRES_DB: costmetrics
EOF
    echo -e "${GREEN}✓ Default database secret created${NC}"
fi

echo -e "${YELLOW}Applying manifests...${NC}"

# Determine the correct path to manifests
if [ -d "../manifests" ]; then
    MANIFESTS_DIR="../manifests"
elif [ -d "../deploy" ]; then
    MANIFESTS_DIR="../deploy"
else
    echo -e "${RED}Error: Cannot find manifests directory${NC}"
    exit 1
fi

cd "${MANIFESTS_DIR}"

# Update image references to use internal registry
for file in postgres-deployment.yml deployment.yml; do
    if [ -f "$file" ]; then
        sed -i.bak "s|registry.redhat.io/rhel9/postgresql-16:latest|${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/postgresql-16:latest|g" "$file"
        sed -i.bak "s|quay.io/almacdon/cost-metrics-aggregator:latest|${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/cost-metrics-aggregator:latest|g" "$file"
        oc apply -f "$file" -n ${AGGREGATOR_NAMESPACE}
    fi
done

# Apply other manifests
for file in service.yml route.yml; do
    [ -f "$file" ] && oc apply -f "$file" -n ${AGGREGATOR_NAMESPACE}
done

# Return to scripts directory
cd - > /dev/null

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

echo -e "${YELLOW}Creating ServiceAccount...${NC}"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: koku-metrics-operator
  namespace: ${OPERATOR_NAMESPACE}
EOF

echo -e "${YELLOW}Creating comprehensive ClusterRole...${NC}"
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: koku-metrics-operator
rules:
- apiGroups: [""]
  resources: [pods, services, services/finalizers, endpoints, persistentvolumeclaims, events, configmaps, secrets, namespaces, nodes]
  verbs: [create, delete, get, list, patch, update, watch]
- apiGroups: [apps]
  resources: [deployments, daemonsets, replicasets, statefulsets]
  verbs: [create, delete, get, list, patch, update, watch]
- apiGroups: [monitoring.coreos.com]
  resources: [servicemonitors]
  verbs: [get, create, list, watch]
- apiGroups: [koku-metrics.openshift.io]
  resources: ['*', kokumetricsconfigs, kokumetricsconfigs/status, kokumetricsconfigs/finalizers]
  verbs: [create, delete, get, list, patch, update, watch]
- apiGroups: [costmanagement-metrics-cfg.openshift.io]
  resources: ['*', costmanagementmetricsconfigs, costmanagementmetricsconfigs/status, costmanagementmetricsconfigs/finalizers]
  verbs: [create, delete, get, list, patch, update, watch]
- apiGroups: [config.openshift.io]
  resources: [clusterversions, clusteroperators, infrastructures]
  verbs: [get, list, watch]
- apiGroups: [route.openshift.io]
  resources: [routes]
  verbs: [get, list, watch, create, update, patch, delete]
EOF

echo -e "${YELLOW}Creating ClusterRoleBinding...${NC}"
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: koku-metrics-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: koku-metrics-operator
subjects:
- kind: ServiceAccount
  name: koku-metrics-operator
  namespace: ${OPERATOR_NAMESPACE}
EOF

echo -e "${YELLOW}Granting Prometheus access...${NC}"
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: koku-metrics-operator-prometheus-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-monitoring-view
subjects:
- kind: ServiceAccount
  name: koku-metrics-operator
  namespace: ${OPERATOR_NAMESPACE}
EOF

echo -e "${YELLOW}Creating CostManagementMetricsConfig CRD...${NC}"
cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: costmanagementmetricsconfigs.costmanagement-metrics-cfg.openshift.io
spec:
  group: costmanagement-metrics-cfg.openshift.io
  names:
    kind: CostManagementMetricsConfig
    listKind: CostManagementMetricsConfigList
    plural: costmanagementmetricsconfigs
    singular: costmanagementmetricsconfig
  scope: Namespaced
  versions:
  - name: v1beta1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            x-kubernetes-preserve-unknown-fields: true
    subresources:
      status: {}
EOF

OPERATOR_IMAGE="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}/koku-metrics-operator:latest"

echo -e "${YELLOW}Creating image pull secret...${NC}"
oc create secret docker-registry koku-registry-pull-secret \
  --docker-server=${INTERNAL_REGISTRY} \
  --docker-username=kubeadmin \
  --docker-password=$(oc whoami -t) \
  -n ${OPERATOR_NAMESPACE} 2>/dev/null || echo "Secret already exists"

oc secrets link koku-metrics-operator koku-registry-pull-secret --for=pull -n ${OPERATOR_NAMESPACE} 2>/dev/null || true

echo -e "${YELLOW}Creating Operator Deployment...${NC}"
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: koku-metrics-operator
  namespace: ${OPERATOR_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      name: koku-metrics-operator
  template:
    metadata:
      labels:
        name: koku-metrics-operator
    spec:
      serviceAccountName: koku-metrics-operator
      imagePullSecrets:
      - name: koku-registry-pull-secret
      containers:
      - name: koku-metrics-operator
        image: ${OPERATOR_IMAGE}
        imagePullPolicy: IfNotPresent
        env:
        - name: WATCH_NAMESPACE
          value: ""
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: "koku-metrics-operator"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
EOF

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
if [ -f "../configuration/CostManagementMetricsConfig.yml" ]; then
    CONFIG_FILE="../configuration/CostManagementMetricsConfig.yml"
elif [ -f "../manifests/CostManagementMetricsConfig.yml" ]; then
    CONFIG_FILE="../manifests/CostManagementMetricsConfig.yml"
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

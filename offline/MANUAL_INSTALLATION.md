# Manual Installation Guide - Offline/Air-Gapped Environment

This guide provides step-by-step commands for installing the Cost Metrics Aggregator, Koku Metrics Operator, and Grafana in an offline/air-gapped OpenShift environment without using automated scripts.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Prepare Offline Bundle](#prepare-offline-bundle)
- [Load Images to Internal Registry](#load-images-to-internal-registry)
- [Install Cost Metrics Aggregator](#install-cost-metrics-aggregator)
- [Install Koku Metrics Operator](#install-koku-metrics-operator)
- [Install Grafana](#install-grafana)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Uninstallation](#uninstallation)

---

## Prerequisites

### Required Tools
- `oc` CLI (OpenShift command-line tool)
- `podman` (for image management)
- `helm` (for Grafana installation)
- Access to an OpenShift cluster with admin privileges

### Required Access
- Machine with internet access (for bundle preparation)
- Air-gapped OpenShift cluster with internal registry enabled
- Method to transfer files between environments (USB, secure transfer, etc.)

---

## Prepare Offline Bundle

### On Connected Machine (Internet Access)

#### 1. Clone Repository

```bash
git clone https://github.com/aptmac/cost-metrics-aggregator.git
cd cost-metrics-aggregator
```

#### 2. Run Bundle Preparation Script

```bash
cd offline
./prepare-offline-bundle.sh
```

This creates `offline-bundle/` containing:
- `images/` - Container image tar files
- `manifests/` - Kubernetes manifests
- `scripts/` - Installation scripts
- `helm-charts/` - Grafana Helm chart
- `grafana/` - Grafana dashboard

#### 3. Create Archive

```bash
tar -czf offline-bundle.tar.gz offline-bundle/
```

#### 4. Transfer to Air-Gapped Environment

Transfer `offline-bundle.tar.gz` to your air-gapped environment using your approved method (USB drive, secure file transfer, etc.).

### On Air-Gapped Machine

#### 5. Extract Bundle

```bash
tar -xzf offline-bundle.tar.gz
cd offline-bundle
```

---

## Load Images to Internal Registry

### 1. Get Internal Registry Route

```bash
export INTERNAL_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
echo $INTERNAL_REGISTRY
```

### 2. Set Registry Namespace

```bash
export INTERNAL_REGISTRY_NAMESPACE=cost-metrics
```

### 3. Login to Registry

```bash
# Option 1: Using cluster credentials
podman login $INTERNAL_REGISTRY --tls-verify=false

# Option 2: Using token
oc whoami -t | podman login $INTERNAL_REGISTRY \
  --username=$(oc whoami) \
  --password-stdin \
  --tls-verify=false
```

### 4. Create Namespace for Images

```bash
oc create namespace $INTERNAL_REGISTRY_NAMESPACE
```

### 5. Load and Push Images

```bash
cd images

# Cost Metrics Aggregator
podman load -i cost-metrics-aggregator.tar
podman tag quay.io/almacdon/cost-metrics-aggregator:latest \
  $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/cost-metrics-aggregator:latest
podman push $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/cost-metrics-aggregator:latest --tls-verify=false

# PostgreSQL
podman load -i postgresql-16.tar
podman tag registry.redhat.io/rhel9/postgresql-16:latest \
  $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/postgresql-16:latest
podman push $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/postgresql-16:latest --tls-verify=false

# Grafana
podman load -i grafana.tar
podman tag docker.io/grafana/grafana:11.4.0 \
  $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/grafana:11.4.0
podman push $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/grafana:11.4.0 --tls-verify=false

# Koku Metrics Operator
podman load -i koku-metrics-operator.tar
podman tag quay.io/project-koku/koku-metrics-operator:latest \
  $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/koku-metrics-operator:latest
podman push $INTERNAL_REGISTRY/$INTERNAL_REGISTRY_NAMESPACE/koku-metrics-operator:latest --tls-verify=false
```

### 6. Verify Images

```bash
# Check images in registry
oc get imagestream -n $INTERNAL_REGISTRY_NAMESPACE
```

---

## Install Cost Metrics Aggregator

### 1. Create Namespace

```bash
oc create namespace cost-metrics
```

### 2. Create Database Secret

```bash
oc apply -f manifests/cost-metrics-db-secret.yml -n cost-metrics
```

Or create manually:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cost-metrics-db
  namespace: cost-metrics
type: Opaque
stringData:
  database-url: postgresql://costmetrics:costmetrics123@postgres:5432/costmetrics?sslmode=require
  postgres-password: costmetrics123
  POSTGRES_USER: costmetrics
  POSTGRES_PASSWORD: costmetrics123
  POSTGRES_DB: costmetrics
EOF
```

### 3. Generate SSL Certificates

```bash
cd scripts
bash generate-ssl-certs.sh cost-metrics
cd ..
```

### 4. Apply SSL Configuration

```bash
oc apply -f manifests/postgres-ssl-config.yml -n cost-metrics
```

### 5. Deploy PostgreSQL

```bash
# Substitute registry placeholders and apply
sed "s|{{INTERNAL_REGISTRY}}|${INTERNAL_REGISTRY}|g; s|{{INTERNAL_REGISTRY_NAMESPACE}}|${INTERNAL_REGISTRY_NAMESPACE}|g" \
  manifests/postgres-deployment.yml | \
  oc apply -f - -n cost-metrics
```

### 6. Wait for PostgreSQL

```bash
oc wait --for=condition=ready pod -l app=postgres -n cost-metrics --timeout=300s
```

### 7. Deploy Cost Metrics Aggregator

```bash
# Substitute registry placeholders and apply
sed "s|{{INTERNAL_REGISTRY}}|${INTERNAL_REGISTRY}|g; s|{{INTERNAL_REGISTRY_NAMESPACE}}|${INTERNAL_REGISTRY_NAMESPACE}|g" \
  manifests/deployment.yml | \
  oc apply -f - -n cost-metrics
```

### 8. Apply Service and Route

```bash
oc apply -f manifests/service.yml -n cost-metrics
oc apply -f manifests/route.yml -n cost-metrics
```

### 9. Wait for Aggregator

```bash
oc wait --for=condition=ready pod -l app=cost-metrics-aggregator -n cost-metrics --timeout=300s
```

### 10. Verify Aggregator

```bash
# Check pods
oc get pods -n cost-metrics

# Get route
AGGREGATOR_ROUTE=$(oc get route cost-metrics-aggregator -n cost-metrics -o jsonpath='{.spec.host}')
echo "Aggregator URL: https://${AGGREGATOR_ROUTE}"

# Test API
curl https://${AGGREGATOR_ROUTE}/api/metrics/v1/sources
```

---

## Install Koku Metrics Operator

### 1. Create Namespace

```bash
oc create namespace koku-metrics-operator
```

### 2. Apply RBAC Resources

```bash
oc apply -f manifests/operator-serviceaccount.yml
oc apply -f manifests/operator-clusterrole.yml
oc apply -f manifests/operator-clusterrolebinding.yml
oc apply -f manifests/operator-prometheus-rolebinding.yml
```

### 3. Apply CRD

```bash
oc apply -f manifests/operator-crd.yml
```

### 4. Create Image Pull Secret

```bash
oc create secret docker-registry koku-registry-pull-secret \
  --docker-server=${INTERNAL_REGISTRY} \
  --docker-username=kubeadmin \
  --docker-password=$(oc whoami -t) \
  -n koku-metrics-operator

# Link secret to service account
oc secrets link koku-metrics-operator koku-registry-pull-secret --for=pull -n koku-metrics-operator
```

### 5. Deploy Operator

```bash
# Substitute registry placeholders and apply
sed "s|{{INTERNAL_REGISTRY}}|${INTERNAL_REGISTRY}|g; s|{{INTERNAL_REGISTRY_NAMESPACE}}|${INTERNAL_REGISTRY_NAMESPACE}|g" \
  manifests/operator-deployment.yml | \
  oc apply -f - -n koku-metrics-operator
```

### 6. Wait for Operator

```bash
oc wait --for=condition=ready pod -l name=koku-metrics-operator -n koku-metrics-operator --timeout=300s
```

### 7. Apply Configuration

```bash
# Wait for operator to initialize
sleep 10

# Apply configuration
oc apply -f manifests/CostManagementMetricsConfig.yml -n koku-metrics-operator
```

### 8. Verify Operator

```bash
# Check pods
oc get pods -n koku-metrics-operator

# Check CRD
oc get crd costmanagementmetricsconfigs.cost-mgmt.openshift.io

# Check configuration
oc get costmanagementmetricsconfig -n koku-metrics-operator
```

---

## Install Grafana

### 1. Create Namespace

```bash
oc new-project grafana
```

Or if the project already exists:

```bash
oc project grafana
```

### 2. Set Up Permissions

```bash
# Grant Grafana access to read from OpenShift monitoring
oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n grafana

# Allow Grafana to run with anyuid SCC
oc adm policy add-scc-to-user anyuid -z grafana -n grafana
```

### 3. Create Image Pull Secret

```bash
oc create secret docker-registry grafana-registry-pull-secret \
  --docker-server=${INTERNAL_REGISTRY} \
  --docker-username=kubeadmin \
  --docker-password=$(oc whoami -t) \
  -n grafana

# Link secret to default and grafana service accounts
oc secrets link default grafana-registry-pull-secret --for=pull -n grafana
oc secrets link grafana grafana-registry-pull-secret --for=pull -n grafana
```

### 4. Prepare Helm Values File

```bash
# Set Grafana image variables
export GRAFANA_REGISTRY="${INTERNAL_REGISTRY}/${INTERNAL_REGISTRY_NAMESPACE}"
export GRAFANA_REPOSITORY="grafana"
export GRAFANA_TAG="11.4.0"

# Create temporary values file with substitutions
sed -e "s|{{GRAFANA_REGISTRY}}|${GRAFANA_REGISTRY}|g" \
    -e "s|{{GRAFANA_REPOSITORY}}|${GRAFANA_REPOSITORY}|g" \
    -e "s|{{GRAFANA_TAG}}|${GRAFANA_TAG}|g" \
    manifests/grafana-openshift-values.yaml > /tmp/grafana-values.yaml
```

### 5. Install Grafana with Helm

```bash
# Find the Grafana chart
GRAFANA_CHART=$(ls helm-charts/grafana-*.tgz | head -1)

# Install Grafana
helm install grafana ${GRAFANA_CHART} -n grafana -f /tmp/grafana-values.yaml
```

### 6. Wait for Grafana ServiceAccount

```bash
# Wait for Helm to create the service account
sleep 5
```

### 7. Link Secret to Grafana ServiceAccount

```bash
# Ensure secret is linked to the grafana ServiceAccount created by Helm
oc secrets link grafana grafana-registry-pull-secret --for=pull -n grafana
```

### 8. Patch Deployment for ImagePullSecrets

```bash
# Ensure imagePullSecrets is set in the deployment
oc patch deployment grafana -n grafana --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "grafana-registry-pull-secret"}]}]'
```

### 9. Restart Grafana Deployment

```bash
oc rollout restart deployment/grafana -n grafana
```

### 10. Create Service Account Token for Prometheus

```bash
# Create a long-lived token for accessing OpenShift Prometheus
TOKEN=$(oc create token grafana -n grafana --duration=8760h)
```

### 11. Create Prometheus Datasource ConfigMap

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-prometheus
  namespace: grafana
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
```

### 12. Mount Datasource ConfigMap

```bash
oc set volume deployment/grafana -n grafana \
  --add \
  --name=datasource-prometheus \
  --type=configmap \
  --configmap-name=grafana-datasource-prometheus \
  --mount-path=/etc/grafana/provisioning/datasources/prometheus-datasource.yaml \
  --sub-path=prometheus-datasource.yaml
```

### 13. Wait for Grafana to be Ready

```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n grafana --timeout=300s
```

### 14. Get Grafana Route and Credentials

```bash
# Get the route
GRAFANA_ROUTE=$(oc get route -n grafana -o jsonpath='{.items[0].spec.host}')
echo "Grafana URL: https://${GRAFANA_ROUTE}"

# Get the admin password (generated by Helm)
GRAFANA_PASSWORD=$(oc get secret grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d)
echo "Username: admin"
echo "Password: ${GRAFANA_PASSWORD}"
```

### 15. Import Dashboard (Optional)

After logging into Grafana with the credentials above:

1. Navigate to **Dashboards** → **Import**
2. Click **Upload JSON file**
3. Select `grafana/dashboard.json` from the bundle
4. Choose the "OpenShift Prometheus" datasource
5. Click **Import**

---

## Verification

### Check All Pods

```bash
# Aggregator components
oc get pods -n cost-metrics

# Operator
oc get pods -n koku-metrics-operator

# Grafana
oc get pods -n grafana
```

### Check Services and Routes

```bash
# Aggregator
oc get svc,route -n cost-metrics

# Grafana
oc get svc,route -n grafana
```

### Check CRDs

```bash
oc get crd | grep -E "(koku|cost)"
```

### View Logs

```bash
# PostgreSQL
oc logs -l app=postgres -n cost-metrics --tail=50

# Aggregator
oc logs -l app=cost-metrics-aggregator -n cost-metrics --tail=50

# Operator
oc logs -l name=koku-metrics-operator -n koku-metrics-operator --tail=50

# Grafana
oc logs -l app.kubernetes.io/name=grafana -n grafana --tail=50
```

### Test Aggregator API

```bash
AGGREGATOR_ROUTE=$(oc get route cost-metrics-aggregator -n cost-metrics -o jsonpath='{.spec.host}')

# Test sources endpoint
curl https://${AGGREGATOR_ROUTE}/api/metrics/v1/sources

# Test nodes endpoint (requires data)
curl "https://${AGGREGATOR_ROUTE}/api/metrics/v1/nodes?start_date=2025-01-01&end_date=2025-12-31"
```

### Access Grafana

```bash
GRAFANA_ROUTE=$(oc get route grafana -n grafana -o jsonpath='{.spec.host}')
echo "Grafana: https://${GRAFANA_ROUTE}"
echo "Login: admin / admin"
```

---

## Troubleshooting

### PostgreSQL Not Starting

```bash
# Check pod events
oc describe pod -l app=postgres -n cost-metrics

# Check PVC
oc get pvc -n cost-metrics

# Check logs
oc logs -l app=postgres -n cost-metrics --tail=100

# Check SSL configuration
oc get secret postgres-ssl-config -n cost-metrics
```

### Aggregator Not Connecting to Database

```bash
# Check secret
oc get secret cost-metrics-db -n cost-metrics -o yaml

# Test database connectivity
oc exec -it deployment/cost-metrics-aggregator -n cost-metrics -- \
  sh -c 'echo "SELECT 1" | psql $DATABASE_URL'

# Check database logs
oc logs -l app=postgres -n cost-metrics --tail=100
```

### Operator Not Starting

```bash
# Check pod status
oc describe pod -l name=koku-metrics-operator -n koku-metrics-operator

# Check RBAC
oc get clusterrole koku-metrics-operator
oc get clusterrolebinding koku-metrics-operator

# Check CRD
oc get crd costmanagementmetricsconfigs.cost-mgmt.openshift.io

# Check logs
oc logs -l name=koku-metrics-operator -n koku-metrics-operator --tail=100
```

### Image Pull Errors

```bash
# Check images in registry
oc get imagestream -n ${INTERNAL_REGISTRY_NAMESPACE}

# Check image pull secrets
oc get secret koku-registry-pull-secret -n koku-metrics-operator
oc get secret grafana-registry-pull-secret -n grafana

# Verify registry route
oc get route default-route -n openshift-image-registry

# Test registry access
curl -k https://${INTERNAL_REGISTRY}/v2/

# Check if secret is linked to service account
oc describe sa koku-metrics-operator -n koku-metrics-operator
oc describe sa grafana -n grafana
```

### Grafana Not Starting

```bash
# Check pod status
oc describe pod -l app.kubernetes.io/name=grafana -n grafana

# Check PVC
oc get pvc -n grafana

# Check logs
oc logs -l app.kubernetes.io/name=grafana -n grafana --tail=100

# Check image pull secret
oc get secret grafana-registry-pull-secret -n grafana

# Verify Helm release
helm list -n grafana
```

### Grafana Can't Connect to Prometheus

```bash
# Check service account token
oc get sa grafana -n grafana

# Verify datasource ConfigMap
oc get configmap grafana-datasource-prometheus -n grafana -o yaml

# Test Prometheus connectivity from Grafana pod
oc exec -it deployment/grafana -n grafana -- \
  curl -k https://thanos-querier.openshift-monitoring.svc:9091/api/v1/query?query=up

# Check if datasource is mounted
oc describe deployment grafana -n grafana | grep -A 5 datasource-prometheus
```

### CRD Not Found

```bash
# Check if CRD exists
oc get crd costmanagementmetricsconfigs.cost-mgmt.openshift.io

# If missing, reapply
oc apply -f manifests/operator-crd.yml

# Verify CRD is established
oc get crd costmanagementmetricsconfigs.cost-mgmt.openshift.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}'
```

---

## Uninstallation

### Remove All Components

```bash
# Delete Grafana
helm uninstall grafana -n grafana
oc delete namespace grafana

# Delete aggregator namespace (includes PostgreSQL and aggregator)
oc delete namespace cost-metrics

# Delete operator namespace
oc delete namespace koku-metrics-operator

# Delete cluster-scoped resources
oc delete clusterrole koku-metrics-operator
oc delete clusterrolebinding koku-metrics-operator
oc delete crd costmanagementmetricsconfigs.cost-mgmt.openshift.io
```

### Remove Images from Internal Registry

```bash
# Delete image streams
oc delete imagestream cost-metrics-aggregator -n ${INTERNAL_REGISTRY_NAMESPACE}
oc delete imagestream postgresql-16 -n ${INTERNAL_REGISTRY_NAMESPACE}
oc delete imagestream grafana -n ${INTERNAL_REGISTRY_NAMESPACE}
oc delete imagestream koku-metrics-operator -n ${INTERNAL_REGISTRY_NAMESPACE}

# Optionally delete the registry namespace
oc delete namespace ${INTERNAL_REGISTRY_NAMESPACE}
```

---

## Additional Notes

### Customizing Database Credentials

Edit the secret before applying:

```yaml
stringData:
  database-url: postgresql://YOUR_USER:YOUR_PASSWORD@postgres:5432/YOUR_DB?sslmode=require
  postgres-password: YOUR_PASSWORD
  POSTGRES_USER: YOUR_USER
  POSTGRES_PASSWORD: YOUR_PASSWORD
  POSTGRES_DB: YOUR_DB
```

### Using Different Namespaces

Replace `cost-metrics`, `koku-metrics-operator`, and `grafana` with your desired namespace names in all commands.

### Updating Images

To update to newer versions:

1. Pull new images on connected machine
2. Save to tar files
3. Transfer to air-gapped environment
4. Load and push to internal registry
5. Update deployments to use new tags

---

**Made with Bob 1.0.1** - Complete manual installation guide for offline environments.
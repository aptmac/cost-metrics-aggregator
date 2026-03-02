#!/bin/bash

NAMESPACE="grafana"

oc new-project $NAMESPACE 2>/dev/null || oc project $NAMESPACE

helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana -n $NAMESPACE
oc adm policy add-scc-to-user anyuid -z grafana -n $NAMESPACE

helm upgrade --install grafana grafana/grafana \
  --namespace $NAMESPACE \
  --values grafana-values.yaml \
  --wait \
  --timeout 5m

TOKEN=$(oc create token grafana -n $NAMESPACE --duration=8760h)

# Create datasource ConfigMap
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-prometheus
  namespace: $NAMESPACE
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
        httpHeaderValue1: 'Bearer $TOKEN'
      editable: false
EOF

oc set volume deployment/grafana -n $NAMESPACE \
  --add \
  --name=datasource-prometheus \
  --type=configmap \
  --configmap-name=grafana-datasource-prometheus \
  --mount-path=/etc/grafana/provisioning/datasources/prometheus-datasource.yaml \
  --sub-path=prometheus-datasource.yaml

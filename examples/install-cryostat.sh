#!/bin/bash

NAMESPACE="cryostat"

echo "Creating namespace: $NAMESPACE"
oc new-project $NAMESPACE 2>/dev/null || oc project $NAMESPACE

helm repo add cryostat-charts https://cryostat.io/helm-charts 2>/dev/null || true
helm install cryostat cryostat-charts/cryostat

# The Cryostat helm chart doesn't have a rht.comp label, so we can add it in ourselves:
oc patch deployment cryostat-v4 -n cryostat --type=merge -p '{"spec":{"template":{"metadata":{"labels":{"rht.comp":"Cryostat"}}}}}'

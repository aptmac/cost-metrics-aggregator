# bash prepare-offline.sh

# log into Red Hat Registry

podman login registry.redhat.io

# go offline

export INTERNAL_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
export INTERNAL_REGISTRY_NAMESPACE="cost-metrics"
export INTERNAL_REGISTRY_USER=$(oc whoami)
export INTERNAL_REGISTRY_PASSWORD=$(oc whoami -t)

podman login ${INTERNAL_REGISTRY} -u ${INTERNAL_REGISTRY_USER} -p ${INTERNAL_REGISTRY_PASSWORD} --tls-verify=false

# cd into scripts

# bash load-images-offline
# bash install-complete-offline.sh
# bash install-cryostat-offline
# bash install-eap-offline
# bash install-grafana-offline
# cd ../../


# CMA
# oc set env deployment/koku-metrics-operator UPLOAD_URL="http://cost-metrics-aggregator.cost-metrics.svc.cluster.local/api/ingress/v1/upload" -n koku-metrics-operator
# kubectl port-forward -n cost-metrics svc/cost-metrics-aggregator 8080:80
# curl "http://localhost:8080/api/metrics/v1/pods?start_date=2026-03-02&end_date=2026-04-02" | jq

# GRAFANA
# oc port-forward -n grafana svc/grafana 3000:80
# oc get secret grafana -n grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

# Offline Demonstration

Setup internal registry:
```bash
export INTERNAL_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
export INTERNAL_REGISTRY_NAMESPACE="cost-metrics"
export INTERNAL_REGISTRY_USER=$(oc whoami)
export INTERNAL_REGISTRY_PASSWORD=$(oc whoami -t)

bash: podman login ${INTERNAL_REGISTRY} -u ${INTERNAL_REGISTRY_USER} -p ${INTERNAL_REGISTRY_PASSWORD} --tls-verify=false

fish: podman login {$INTERNAL_REGISTRY} -u {$INTERNAL_REGISTRY_USER} -p {$INTERNAL_REGISTRY_PASSWORD} --tls-verify=false
```

Using CMA & Grafana:
```bash
# CMA
kubectl port-forward -n cost-metrics svc/cost-metrics-aggregator 8080:80
curl "http://localhost:8080/api/metrics/v1/pods?start_date=2026-03-02&end_date=2026-04-02" | jq

# Grafana
oc get secret grafana -n grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
oc port-forward -n grafana svc/grafana 3000:80
```

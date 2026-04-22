# Demo Applications

This directory contains demo applications that can be used to demonstrate the offline monitoring capabilities of the Cost Metrics Aggregator.

Currently Cryostat 4.1.1 and EAP 7.4 are used.

1. Fetch and bundle images required to run the application:
```bash
bash prepare-offline-bundle.sh
```

<b>At this point you may proceed offline.</b>

2. Setup internal registry:
```bash
export INTERNAL_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
export INTERNAL_REGISTRY_NAMESPACE="cost-metrics"
export INTERNAL_REGISTRY_USER=$(oc whoami)
export INTERNAL_REGISTRY_PASSWORD=$(oc whoami -t)

bash: podman login ${INTERNAL_REGISTRY} -u ${INTERNAL_REGISTRY_USER} -p ${INTERNAL_REGISTRY_PASSWORD} --tls-verify=false

fish: podman login {$INTERNAL_REGISTRY} -u {$INTERNAL_REGISTRY_USER} -p {$INTERNAL_REGISTRY_PASSWORD} --tls-verify=false
```

3. Load the images into the internal registry, and install
```bash
cd demo-apps-bundle/scripts
bash load-images-offline.sh
bash install-cryostat-offline.sh
bash install-eap74-offline.sh
```

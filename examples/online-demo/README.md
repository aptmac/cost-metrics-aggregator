# Proof of Concept Demonstration

The following instructions were written for installation on a clean OpenShift Cluster (CRC).

It will detail the instructions for deploying the contents of this repository, as well as deploying some applications via helm charts that we can use to demonstrate the functionality of the Cost Metrics Aggregator (CMA) & Operator (CMO).

There are additional, but optional, steps to install and configure Grafana. There is a provided dashboard that can be loaded to display real-time metrics in order to help bridge the gaps between report uploads from the CMO.

## Installation

### Install and Setup the Cost Management Operator

Open your OpenShift Console, navigate to the OperatorHub page using the side-nav `Operator` > `OperatorHub`, and search for `Cost Management`.

Select the `Cost Management Operator`, and Install it using the defaults.

### Install Cost Metrics Aggregator

[OpenShift Deployment > Install on OpenShift](../README.md#deploy-on-openshift)

### Install basic workloads

```bash
bash install-eap.sh
```

The above script will simply add the helm chart for EAP 8, and install the application.

```bash
bash install-cryostat.sh
```

The above script will add the helm chart for Cryostat, install the application, and apply a `rht.comp` label to the deployment so that it can be found by the CMA and Grafana dashboard.

Now we will have two applications running in two different namespaces that are ready for monitoring.

## Usage

### Configure the Cost Management Operator

Navigate to the Cost Management Operator details page for the Operator we installed in the above section: `Operator` > `Installed Operators` > `Cost Management Operator`.

Select the "Cost Management Metrics Config" tab, and click "Create Cost Management Metrics Config" (CMMC). Alternatively, from the CMO details page you can click the "Create Instance" link inside of the CMMC card under "Provided APIs".

Copy over the contents from the `CostManagementMetricsConfig.yml` file into the editor, and save.

### Fetch data from the Cost Metrics Aggregator

Expose the cost-metrics-aggregator service so it can be reached at `localhost:8080`:

`oc port-forward -n cost-metrics svc/cost-metrics-aggregator 8080:80`

Current GET endpoints are:

http://localhost:8080/api/metrics/v1/nodes

http://localhost:8080/api/metrics/v1/pods

Now you can use `curl` to fetch data from CMA, for example:

`curl "http://localhost:8080/api/metrics/v1/pods?start_date=$(date +%Y-%m-%d)&end_date=$(date +%Y-%m-%d)" | jq`

Result:
```
{
  "data": [
    {
      "Date": "2026-02-26T00:00:00Z",
      "MaxCoresUsed": 0.0625,
      "TotalPodEffectiveCoreSeconds": 1170,
      "TotalHours": 1,
      "ClusterID": "9fa1c7bf-6453-4345-9335-0e53b8b48142",
      "ClusterName": "my-openshift-cluster",
      "PodName": "cryostat-v4-6864b87988-n7h75",
      "Namespace": "cryostat",
      "Component": "Cryostat"
    },
    {
      "Date": "2026-02-26T00:00:00Z",
      "MaxCoresUsed": 0.00016372660256410256,
      "TotalPodEffectiveCoreSeconds": 3.064962,
      "TotalHours": 1,
      "ClusterID": "9fa1c7bf-6453-4345-9335-0e53b8b48142",
      "ClusterName": "my-openshift-cluster",
      "PodName": "eap8-app-56579cb66b-zlbps",
      "Namespace": "middleware",
      "Component": "EAP"
    }
  ],
  "metadata": {
    "limit": 100,
    "offset": 0,
    "total": 2
  }
}
```

## Grafana (optional)

The CMO uploads data at specific intervals (once a day by default, but once every 15 minutes in our example), and if used in conjunction with the Cost Management tools at console.redhat.com there may be a delay of up to 24 hours between when data is pulled and when information is displayed.

See the included Grafana [README](../grafana/README.md) for additional steps to install a Grafana helm chart, which can make PromQL queries to the Prometheus instance that is supplied by OpenShift. This allows for real-time metrics to be gathered from our deployments, and plotted into visualizations with configurable time ranges.

# Observability Stack

Long-term metrics storage for Cost Metrics Aggregator using Prometheus + Thanos + SeaweedFS.

## Overview

This observability stack provides:
- **Prometheus** - Federates metrics from OpenShift monitoring
- **Thanos** - Long-term storage with intelligent downsampling
- **SeaweedFS** - Lightweight S3-compatible object storage
- **Grafana** - Visualization and dashboarding

## Quick Start

```bash
cd observability
./install.sh
```

This deploys the complete stack in the `cma-observability` namespace.

## What Gets Installed

- **Namespace**: `cma-observability`
- **Prometheus**: Scrapes from OpenShift monitoring via federation
- **Thanos Sidecar**: Ships data to SeaweedFS
- **Thanos Store**: Serves historical data from object storage
- **Thanos Compactor**: Downsamples and manages retention
- **Thanos Query**: Unified query interface
- **SeaweedFS**: Object storage (100Gi PVC)
- **Grafana**: Visualization with pre-configured datasource

## Data Retention

| Resolution | Retention | Use Case |
|------------|-----------|----------|
| Raw (30s) | 30 days | Recent detailed analysis |
| 5-minute | 180 days | Medium-term trends |
| 1-hour | 5 years | Long-term capacity planning |

## Access

After installation:

```bash
# Get routes
oc get routes -n cma-observability

# Thanos Query - Query interface
# Grafana - Visualization (admin/admin)
```

## Dashboard

Import the included dashboard:
1. Login to Grafana
2. Navigate to **Dashboards** → **Import**
3. Upload `dashboard.json`
4. Select the Thanos datasource

## Resource Requirements

- **CPU**: ~2.8 cores (requests)
- **Memory**: ~6.5 GiB (requests)
- **Storage**: ~155 GiB (Prometheus 50Gi + SeaweedFS 100Gi + Grafana 5Gi)

## Architecture

```
OpenShift Monitoring
       ↓ (federation)
   Prometheus (50Gi)
       ↓ (sidecar)
SeaweedFS (100Gi) ←→ Thanos Store
       ↓
 Thanos Compactor (downsampling)
       ↓
  Thanos Query ←→ Grafana
```

## Uninstall

```bash
oc delete namespace cma-observability
```

## Documentation

For detailed information, see the main repository README.

---

**Made with Bob 1.0.1** - Lightweight observability for cost metrics.
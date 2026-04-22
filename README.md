# Cost Metrics Aggregator

The Cost Metrics Aggregator is a Go-based application for collecting and aggregating cost-related metrics from Kubernetes clusters, focusing on node vCPU utilization and pod CPU usage for subscription purposes. It stores data in a PostgreSQL database with partitioned tables for efficient time-series management. The application is deployed on OpenShift with automated image builds via Quay.io and supports local development with Podman.

## Features
- Collects node metrics (e.g., core count) and pod metrics (e.g., CPU usage and request seconds) from clusters.
- Stores data in PostgreSQL with UUID-based identifiers and range-partitioned tables for time-series data.
- Aggregates daily node and pod metrics for efficient querying (e.g., total hours and effective core seconds).
- Manages database partitions with automated creation and deletion via OpenShift CronJobs.
- Provides RESTful API endpoints to upload metrics and query node and pod data.
- Deploys on OpenShift with a dedicated PostgreSQL instance and secrets.
- Supports local development with Podman and `podman-compose` for testing and debugging.
- Provides scripts for offline setup & installation

## Prerequisites
- **OpenShift Deployment**:
  - OpenShift cluster (v4.x) with admin access.
  - Quay.io account with permissions to push to `quay.io/almacdon/cost-metrics-aggregator`.
  - GitHub repository (`aptmac/cost-metrics-aggregator`) with push access.
  - `kubectl` installed locally.
- **Local Development**:
  - Go 1.20 or higher.
  - Podman and `podman-compose` installed.
  - `make` for using the `Makefile`.
  - A storage class (e.g., `standard`) available in OpenShift for PostgreSQL persistence (if deploying locally with OpenShift).

## Repository Structure
```
.
├── Containerfile              # Container build configuration
├── Makefile                   # Build, test, and deployment tasks
├── podman-compose.yaml        # Local development services (app, database)
├── go.mod                     # Go module dependencies
├── install.sh                 # Online installation script
├── api/
│   ├── handlers/              # API request handlers
│   │   ├── query.go
│   │   ├── sources.go
│   │   └── upload.go
│   ├── router.go              # API router
│   └── router_test.go
├── cmd/
│   └── server/
│       └── main.go            # Application entry point
├── internal/
│   ├── config/                # Server configuration
│   │   ├── config.go
│   │   └── config_test.go
│   ├── db/                    # Database layer
│   │   ├── repository.go
│   │   ├── repository_test.go
│   │   ├── testutils/
│   │   │   └── setup.go
│   │   └── migrations/        # SQL migrations
│   │       ├── 0001_init.up.sql
│   │       └── 0001_init.down.sql
│   └── processor/             # CSV processing logic
│       ├── csv_processor.go
│       ├── csv_processor_test.go
│       ├── tar_processor.go
│       ├── tar_processor_test.go
│       └── testutils/
│           └── setup.go
├── scripts/                   # Utility scripts
│   ├── generate-ssl-certs.sh  # SSL certificate generation
│   ├── reset_db.sh            # Database reset utility
│   ├── create/                # Partition creation script
│   │   └── main.go
│   ├── drop/                  # Partition deletion script
│   │   └── main.go
│   └── generate_test_upload/  # Test data generation
│       └── main.go
├── grafana/                   # Grafana dashboard and configuration
│   ├── dashboard.json         # Cost metrics dashboard
│   ├── grafana-values.yml     # Helm values for Grafana
│   ├── install-grafana.sh     # Grafana installation script
│   └── README.md
├── deploy/                    # Kubernetes deployment manifests
│   ├── namespace.yml          # CMA namespace
│   ├── deployment.yml         # CMA application deployment
│   ├── service.yml            # CMA service
│   ├── route.yml              # CMA route
│   ├── operator/              # Koku Metrics Operator
│   │   ├── operator-serviceaccount.yml
│   │   ├── operator-clusterrole.yml
│   │   ├── operator-clusterrolebinding.yml
│   │   ├── operator-prometheus-rolebinding.yml
│   │   ├── operator-crd.yml
│   │   ├── operator-deployment.yml
│   │   └── CostManagementMetricsConfig.yml
│   ├── postgres/              # PostgreSQL database
│   │   ├── postgres-deployment.yml
│   │   ├── postgres-ssl-config.yml
│   │   ├── cost-metrics-db-secret.yml
│   │   ├── cronjob-create-partitions.yml
│   │   └── cronjob-drop-partitions.yml
│   └── offline/               # Offline variants (registry placeholders)
│       ├── deployment.yml
│       ├── postgres-deployment.yml
│       ├── operator-deployment.yml
│       └── grafana-openshift-values.yaml
└── offline/                   # Offline/air-gapped deployment
    ├── prepare-offline-bundle.sh
    ├── README.md
    ├── demo-apps/             # Demo applications bundle
    │   ├── prepare-offline-demo-bundle.sh
    │   ├── README.md
    │   ├── config/            # Helm values
    │   │   ├── cryostat.yaml
    │   │   └── eap74.yaml
    │   └── installation-scripts/
    │       ├── install-cryostat-offline.sh
    │       ├── install-eap74-offline.sh
    │       └── load-images-offline.sh
    └── installation-scripts/
        ├── install-offline.sh
        ├── install-grafana-offline.sh
        └── load-images-offline.sh
```

## Database Schema
The database schema (`internal/db/migrations/0001_init.up.sql`) defines:
- `clusters`: Stores cluster metadata with UUID `id` and `name`.
- `nodes`: Stores node metadata with UUID `id`, `cluster_id`, `name`, `identifier`, and `type`.
- `node_metrics`: Stores time-series node metrics with UUID `id`, `node_id`, `timestamp`, `core_count`, and `cluster_id`, partitioned monthly by `timestamp`.
- `node_daily_summary`: Aggregates daily node metrics by `node_id`, `date`, and `core_count`, storing `total_hours`.
- `pods`: Stores pod metadata with UUID `id`, `cluster_id`, `node_id`, `name`, `namespace`, and `component`.
- `pod_metrics`: Stores time-series pod metrics with UUID `id`, `pod_id`, `timestamp`, `pod_usage_cpu_core_seconds`, `pod_request_cpu_core_seconds`, `node_capacity_cpu_core_seconds`, and `node_capacity_cpu_cores`, partitioned monthly by `timestamp`.
- `pod_daily_summary`: Aggregates daily pod metrics by `pod_id` and `date`, storing `max_cores_used`, `total_pod_effective_core_seconds`, and `total_hours`.

All `id` columns use UUIDs (via `gen_random_uuid()`). The `node_metrics` and `pod_metrics` tables are partitioned for performance.

## Local Development
### 1. Clone the Repository
```bash
git clone https://github.com/aptmac/cost-metrics-aggregator.git
cd cost-metrics-aggregator
```

### 2. Set Up Environment
Create a `./db.env` file for the application:
```bash
echo "DATABASE_URL=postgres://costmetrics:costmetrics@db:5432/costmetrics?sslmode=disable" > ./db.env
echo "POD_LABEL_KEYS=label_rht_comp" >> ./db.env
```
- `DATABASE_URL`: Matches the PostgreSQL service in `podman-compose.yaml`. Uses `sslmode=disable` for local development since the local PostgreSQL container doesn't have SSL configured.
- `POD_LABEL_KEYS`: Defines pod labels for filtering (e.g., `label_rht_comp`).

**Note**: For OpenShift/production deployments, SSL is enabled by default. The deployment uses `sslmode=require` in the secret configuration.

### 3. Start Services
Use the `Makefile` to start the application and PostgreSQL database:
```bash
make compose-up
```
This:
- Builds the application image using the `Containerfile`.
- Starts the `app` (aggregator) and `db` (PostgreSQL) services.
- Applies migrations from `internal/db/migrations` to initialize the database schema.

Verify services are running:
```bash
podman ps
```
Expected output includes containers `aggregator` and `aggregator-db`.

### 4. Run Tests
Execute unit tests to verify the application logic:
```bash
make test
```
This runs tests in all packages, including CSV processing for node and pod metrics.

### 5. Test the Application

Generate a test tar.gz file containing a manifest.json and sample CSV files for the previous 24 hours:
```bash
make generate-test-upload
```

Upload the generated test file to the application:
```bash
make upload-test
```

The generate-test-upload target creates a test_upload.tar.gz file with a manifest and two CSV files, each containing hourly metrics data compatible with the application's ingestion endpoint. The upload-test target sends this file to http://localhost:8080/api/ingress/v1/upload. Ensure the application is running before uploading.

> 💡 Tip:
> Substitute `start_date` and `end_date` with the current date
> (in `YYYY-MM-DD` format) to ensure you query data from current month partition.

Query node metrics:
```bash
curl "http://localhost:8080/api/metrics/v1/nodes?start_date=2025-05-17&end_date=2027-05-17"
```

Query pod metrics:
```bash
curl "http://localhost:8080/api/metrics/v1/pods?start_date=2025-05-17&end_date=2027-05-17&namespace=test"
```

### 6. Access the Database
Connect to the PostgreSQL database to inspect data:
```bash
podman exec -it aggregator-db psql -U costmetrics -d costmetrics
```
List tables and partitions:
```sql
\dt+ node_metrics*
\dt+ pod_metrics*
```
Query summaries:
```sql
SELECT * FROM node_daily_summary WHERE date = '2025-05-17';
SELECT * FROM pod_daily_summary WHERE date = '2025-05-17';
```

### 7. Stop Services
Shut down and remove containers:
```bash
make compose-down
```

## OpenShift Deployment

### Quick Start (Online Installation)
For a streamlined online deployment using public registries:
```bash
./install.sh
```

This script will:
- Create namespaces for the aggregator and operator
- Deploy PostgreSQL with SSL configuration
- Deploy the Cost Metrics Aggregator
- Install the Koku Metrics Operator
- Apply the CostManagementMetricsConfig

### Manual Deployment Steps

#### 1. Build and Push Image
```bash
make build
podman build -t quay.io/almacdon/cost-metrics-aggregator:latest .
podman push quay.io/almacdon/cost-metrics-aggregator:latest
```

#### 2. Deploy Core Components
1. Create the `cost-metrics` namespace:
   ```bash
   kubectl apply -f deploy/namespace.yml
   ```

2. Update `deploy/postgres/cost-metrics-db-secret.yml` with base64-encoded values:
   - `postgres-password`: Your PostgreSQL password (e.g., `echo -n "costmetrics" | base64`)
   - `database-url`: Connection string with SSL enabled
     - Format: `postgres://<username>:<password>@postgres:5432/costmetrics?sslmode=require`
     - Example: `echo -n "postgres://costmetrics:costmetrics@postgres:5432/costmetrics?sslmode=require" | base64`
     - Result: `cG9zdGdyZXM6Ly9jb3N0bWV0cmljczpjb3N0bWV0cmljc0Bwb3N0Z3Jlczo1NDMyL2Nvc3RtZXRyaWNzP3NzbG1vZGU9cmVxdWlyZQ==`
   
   **Note**: The PostgreSQL deployment is configured with `POSTGRESQL_ENABLE_TLS=true` to support SSL connections.

3. Deploy PostgreSQL and secret:
   ```bash
   kubectl apply -f deploy/postgres/cost-metrics-db-secret.yml -n cost-metrics
   kubectl apply -f deploy/postgres/postgres-deployment.yml -n cost-metrics
   ```

4. Deploy the application:
   ```bash
   kubectl apply -f deploy/deployment.yml -n cost-metrics
   kubectl apply -f deploy/service.yml -n cost-metrics
   kubectl apply -f deploy/route.yml -n cost-metrics
   ```

5. Deploy CronJobs for partition management:
   ```bash
   kubectl apply -f deploy/postgres/cronjob-create-partitions.yml -n cost-metrics
   kubectl apply -f deploy/postgres/cronjob-drop-partitions.yml -n cost-metrics
   ```

#### 3. Deploy Koku Metrics Operator (Optional)
If you need the Koku Metrics Operator for cost management:
```bash
kubectl apply -f deploy/operator/operator-serviceaccount.yml
kubectl apply -f deploy/operator/operator-clusterrole.yml
kubectl apply -f deploy/operator/operator-clusterrolebinding.yml
kubectl apply -f deploy/operator/operator-prometheus-rolebinding.yml
kubectl apply -f deploy/operator/operator-crd.yml
kubectl apply -f deploy/operator/operator-deployment.yml
kubectl apply -f deploy/operator/CostManagementMetricsConfig.yml -n koku-metrics-operator
```

### Offline Deployment
For air-gapped or offline environments, see the [offline deployment guide](offline/README.md).

### 3. Verify Deployment
1. Check pod status:
   ```bash
   kubectl get pods -n cost-metrics -l app=postgres
   kubectl get pods -n cost-metrics -l app=cost-metrics-aggregator
   ```

2. Verify database schema:
   ```bash
   kubectl exec -it <postgres-pod-name> -n cost-metrics -- psql -U costmetrics -d costmetrics -c "\dt+ node_metrics*"
   kubectl exec -it <postgres-pod-name> -n cost-metrics -- psql -U costmetrics -d costmetrics -c "\dt+ pod_metrics*"
   ```

3. Check application logs:
   ```bash
   kubectl logs -l app=cost-metrics-aggregator -n cost-metrics
   ```

4. Verify CronJob execution:
   ```bash
   kubectl get jobs -n cost-metrics
   kubectl logs <job-pod-name> -n cost-metrics
   ```

## Queries

You can use `kubectl` to query the database directly:
```bash
Template:

kubectl exec -n cost-metrics \
  $(kubectl get pod -n cost-metrics -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U costmetrics -d costmetrics -c "YOUR SQL QUERY HERE"

Example (count all records):

kubectl exec -n cost-metrics \
  $(kubectl get pod -n cost-metrics -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- \
  psql -U costmetrics -d costmetrics -c \
  "SELECT COUNT(*) FROM node_metrics; SELECT COUNT(*) FROM pod_metrics;"
```

## Partition Management
- **Creation**: The `create_partitions.go` script (run by an initContainer and `cronjob-create-partitions`) creates `node_metrics` and `pod_metrics` partitions for the previous and next 90 days.
- **Deletion**: The `drop_partitions.go` script (run by `cronjob-drop-partitions`) drops partitions older than 90 days.
- **Schedule**: Both CronJobs run monthly on the 1st at midnight (`0 0 1 * *`).

## Endpoints
- **POST /api/ingress/v1/upload**: Uploads a tar.gz file containing `manifest.json` and CSV files (e.g., `node.csv`) for metric ingestion.
- **GET /api/metrics/v1/nodes**: Queries node metrics (e.g., core count, total hours) with optional filters (`start_date`, `end_date`, `cluster_id`, `cluster_name`, `node_type`).
- **GET /api/metrics/v1/pods**: Queries pod metrics (e.g., max cores used, effective core seconds, total hours) with optional filters (`start_date`, `end_date`, `cluster_id`, `namespace`, `component`).

## Troubleshooting
- **Local Development**:
  - **Container Failures**: Check `podman logs aggregator` or `podman logs aggregator-db` for errors.
  - **Database Connectivity**: Ensure `vulnerability/db.env` has the correct `DATABASE_URL` and the `db` service is running.
  - **CSV Processing Errors**: Verify CSV format and `interval_start` timestamps (`2006-01-02 15:04:05 +0000 MST`).
- **OpenShift Deployment**:
  - **Build Failures**: Check Quay.io build logs for missing dependencies or network issues.
  - **Migration Errors**: Verify `DATABASE_URL` in `cost-metrics-db-secret.yml` and PostgreSQL pod logs.
  - **CronJob Failures**: Check job logs for script errors or database permissions.
- **Metrics Issues**:
  - Query `node_daily_summary` or `pod_daily_summary` to verify `total_hours`:
    ```sql
    SELECT * FROM node_daily_summary WHERE date = '2025-05-17';
    SELECT * FROM pod_daily_summary WHERE date = '2025-05-17';
    ```

## Contributing
- Submit pull requests to `almacdon/cost-metrics-aggregator`.
- Update `internal/db/migrations/` for schema changes and `internal/processor/` for metric processing logic.
- Add tests in relevant packages (e.g., `internal/processor`) for node and pod metric aggregation.
- Test locally with `make compose-up` and `make test` before pushing to Quay.io.
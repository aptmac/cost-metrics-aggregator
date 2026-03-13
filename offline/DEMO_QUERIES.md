# Cost Metrics Aggregator - Demo Queries

Quick reference for demonstrating CMA capabilities and troubleshooting.

## Quick Access to PostgreSQL

```bash
# Connect to PostgreSQL pod
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics

# Or run a single query
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "YOUR_QUERY_HERE"
```

## Database Overview Queries

### 1. List All Tables
```bash
# Interactive mode
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "\dt"

# With sizes
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT table_name, pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) AS size FROM information_schema.tables WHERE table_schema = 'public' ORDER BY pg_total_relation_size(quote_ident(table_name)) DESC;"
```

### 2. Check Table Row Counts
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT schemaname, tablename, n_live_tup AS row_count FROM pg_stat_user_tables ORDER BY n_live_tup DESC;"
```

## Clusters

### 3. List All Clusters
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT id, name FROM clusters ORDER BY name;"
```

### 4. Cluster Summary with Node and Pod Counts
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT c.name, COUNT(DISTINCT n.id) as node_count, COUNT(DISTINCT p.id) as pod_count FROM clusters c LEFT JOIN nodes n ON c.id = n.cluster_id LEFT JOIN pods p ON c.id = p.cluster_id GROUP BY c.id, c.name ORDER BY c.name;"
```

## Nodes

### 5. List All Nodes
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT n.name, n.type, c.name as cluster_name FROM nodes n JOIN clusters c ON n.cluster_id = c.id ORDER BY c.name, n.name;"
```

### 6. Node Metrics Summary (Last 24 Hours)
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT n.name, COUNT(*) as data_points, AVG(nm.core_count) as avg_cores, MIN(nm.timestamp) as first_metric, MAX(nm.timestamp) as last_metric FROM node_metrics nm JOIN nodes n ON nm.node_id = n.id WHERE nm.timestamp > NOW() - INTERVAL '24 hours' GROUP BY n.id, n.name ORDER BY n.name;"
```

### 7. Latest Node Metrics
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT n.name, c.name as cluster, nm.core_count, nm.timestamp FROM node_metrics nm JOIN nodes n ON nm.node_id = n.id JOIN clusters c ON n.cluster_id = c.id ORDER BY nm.timestamp DESC LIMIT 20;"
```

### 8. Node Daily Summary
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT n.name, nds.date, nds.core_count, nds.total_hours FROM node_daily_summary nds JOIN nodes n ON nds.node_id = n.id ORDER BY nds.date DESC, n.name LIMIT 20;"
```

## Pods

### 9. List All Pods
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT p.name, p.namespace, n.name as node_name, c.name as cluster_name FROM pods p JOIN nodes n ON p.node_id = n.id JOIN clusters c ON p.cluster_id = c.id ORDER BY p.namespace, p.name LIMIT 50;"
```

### 10. Pod Count by Namespace
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT namespace, COUNT(*) as pod_count FROM pods GROUP BY namespace ORDER BY pod_count DESC;"
```

### 11. Latest Pod Metrics
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT p.name, p.namespace, pm.pod_usage_cpu_core_seconds, pm.pod_request_cpu_core_seconds, pm.pod_effective_core_seconds, pm.timestamp FROM pod_metrics pm JOIN pods p ON pm.pod_id = p.id ORDER BY pm.timestamp DESC LIMIT 20;"
```

### 12. Pod Metrics by Namespace (Last 24 Hours)
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT p.namespace, COUNT(DISTINCT p.id) as unique_pods, COUNT(*) as data_points, AVG(pm.pod_request_cpu_core_seconds) as avg_request, AVG(pm.pod_usage_cpu_core_seconds) as avg_usage, AVG(pm.pod_effective_core_seconds) as avg_effective FROM pod_metrics pm JOIN pods p ON pm.pod_id = p.id WHERE pm.timestamp > NOW() - INTERVAL '24 hours' GROUP BY p.namespace ORDER BY avg_effective DESC;"
```

### 13. Top Resource Consuming Pods (Last 24 Hours)
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT p.name, p.namespace, AVG(pm.pod_effective_core_seconds) as avg_effective_cores, COUNT(*) as data_points FROM pod_metrics pm JOIN pods p ON pm.pod_id = p.id WHERE pm.timestamp > NOW() - INTERVAL '24 hours' GROUP BY p.id, p.name, p.namespace ORDER BY avg_effective_cores DESC LIMIT 10;"
```

### 14. Pod Daily Summary
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT p.name, p.namespace, pds.date, pds.max_cores_used, pds.total_pod_effective_core_seconds, pds.total_hours FROM pod_daily_summary pds JOIN pods p ON pds.pod_id = p.id ORDER BY pds.date DESC, p.namespace, p.name LIMIT 20;"
```

## Time-Based Analysis

### 15. Data Collection Timeline (Hourly)
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT DATE_TRUNC('hour', timestamp) as hour, COUNT(DISTINCT node_id) as nodes, COUNT(*) as node_metrics FROM node_metrics WHERE timestamp > NOW() - INTERVAL '7 days' GROUP BY DATE_TRUNC('hour', timestamp) ORDER BY hour DESC LIMIT 24;"
```

### 16. Pod Metrics Timeline (Hourly)
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT DATE_TRUNC('hour', timestamp) as hour, COUNT(DISTINCT pod_id) as pods, COUNT(*) as pod_metrics FROM pod_metrics WHERE timestamp > NOW() - INTERVAL '7 days' GROUP BY DATE_TRUNC('hour', timestamp) ORDER BY hour DESC LIMIT 24;"
```

### 17. Data Freshness Check
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT 'node_metrics' as table_name, MAX(timestamp) as latest_data, NOW() - MAX(timestamp) as age FROM node_metrics UNION ALL SELECT 'pod_metrics' as table_name, MAX(timestamp) as latest_data, NOW() - MAX(timestamp) as age FROM pod_metrics;"
```

## Partitioning Info

### 18. Check Partition Tables
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT schemaname, table_name, pg_size_pretty(pg_total_relation_size(quote_ident(schemaname)||'.'||quote_ident(table_name))) AS size FROM information_schema.tables WHERE table_schema = 'public' AND (table_name LIKE 'node_metrics_%' OR table_name LIKE 'pod_metrics_%') ORDER BY table_name;"
```

### 19. Partition Size Summary
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT CASE WHEN table_name LIKE 'node_metrics_%' THEN 'node_metrics' WHEN table_name LIKE 'pod_metrics_%' THEN 'pod_metrics' ELSE table_name END as base_table, COUNT(*) as partition_count, pg_size_pretty(SUM(pg_total_relation_size(quote_ident(schemaname)||'.'||quote_ident(table_name)))) AS total_size FROM information_schema.tables WHERE table_schema = 'public' AND (table_name LIKE 'node_metrics_%' OR table_name LIKE 'pod_metrics_%') GROUP BY base_table;"
```

## Demo Script

### Quick Demo Sequence
```bash
# 1. Show database is running
oc get pods -n cost-metrics

# 2. Check clusters
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT name FROM clusters;"

# 3. Show node count
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT COUNT(*) as total_nodes, COUNT(DISTINCT cluster_id) as clusters FROM nodes;"

# 4. Show node metrics count
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT COUNT(*) as node_metrics, COUNT(DISTINCT node_id) as unique_nodes FROM node_metrics;"

# 5. Show pod metrics count
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT COUNT(*) as pod_metrics, COUNT(DISTINCT namespace) as namespaces FROM pod_metrics pm JOIN pods p ON pm.pod_id = p.id;"

# 6. Show resource summary by namespace
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT p.namespace, COUNT(DISTINCT p.id) as pods, AVG(pm.pod_effective_core_seconds) as avg_effective_cores FROM pod_metrics pm JOIN pods p ON pm.pod_id = p.id WHERE pm.timestamp > NOW() - INTERVAL '1 hour' GROUP BY p.namespace ORDER BY avg_effective_cores DESC LIMIT 5;"
```

## Troubleshooting Queries

### 20. Find Data Gaps (Hourly Check)
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "WITH hourly_series AS (SELECT generate_series(DATE_TRUNC('hour', NOW() - INTERVAL '24 hours'), DATE_TRUNC('hour', NOW()), '1 hour'::interval) AS hour) SELECT hs.hour, COUNT(nm.node_id) as node_metrics_count, COUNT(pm.pod_id) as pod_metrics_count FROM hourly_series hs LEFT JOIN node_metrics nm ON DATE_TRUNC('hour', nm.timestamp) = hs.hour LEFT JOIN pod_metrics pm ON DATE_TRUNC('hour', pm.timestamp) = hs.hour GROUP BY hs.hour ORDER BY hs.hour DESC;"
```

### 21. Database Size and Growth
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT pg_size_pretty(pg_database_size('costmetrics')) as database_size, (SELECT COUNT(*) FROM node_metrics) as node_metrics_count, (SELECT COUNT(*) FROM pod_metrics) as pod_metrics_count, (SELECT COUNT(*) FROM clusters) as clusters_count, (SELECT COUNT(*) FROM nodes) as nodes_count, (SELECT COUNT(*) FROM pods) as pods_count;"
```

### 22. Check for Missing Relationships
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT 'nodes without cluster' as issue, COUNT(*) as count FROM nodes WHERE cluster_id IS NULL UNION ALL SELECT 'pods without cluster', COUNT(*) FROM pods WHERE cluster_id IS NULL UNION ALL SELECT 'pods without node', COUNT(*) FROM pods WHERE node_id IS NULL;"
```

### 23. Node Metrics Without Matching Nodes
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT COUNT(*) as orphaned_metrics FROM node_metrics nm LEFT JOIN nodes n ON nm.node_id = n.id WHERE n.id IS NULL;"
```

### 24. Pod Metrics Without Matching Pods
```bash
oc exec -it -n cost-metrics deployment/postgres -- psql -U costmetrics -d costmetrics -c "SELECT COUNT(*) as orphaned_metrics FROM pod_metrics pm LEFT JOIN pods p ON pm.pod_id = p.id WHERE p.id IS NULL;"
```

# Made with Bob 1.0.0

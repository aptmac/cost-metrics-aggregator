package processor

import (
	"context"
	"encoding/csv"
	"os"
	"strings"
	"testing"

	"github.com/aptmac/cost-metrics-aggregator/internal/db"
	"github.com/aptmac/cost-metrics-aggregator/internal/processor/testutils"
	"github.com/google/uuid"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AI-ASSISTED: Bob 1.0.1
func TestProcessCSV(t *testing.T) {
	pool := testutils.SetupTestDB(t)
	repo := db.NewRepository(pool)
	ctx := context.Background()

	os.Setenv("POD_LABEL_KEYS", "label_rht_comp")
	defer os.Unsetenv("POD_LABEL_KEYS")

	clusterID := "10f5a0f9-223a-41c1-8456-9a3eb0323a99"
	clusterUUID, _ := uuid.Parse(clusterID)
	nodeName := "ip-10-0-1-63.ec2.internal"
	podName := "zip-1"
	namespace := "test"

	// Setup cluster
	err := repo.UpsertCluster(clusterUUID, "test-cluster")
	require.NoError(t, err)

	// CSV with 2 records at different hours (14:00 and 15:00)
	csvData := `report_period_start,report_period_end,interval_start,interval_end,node,namespace,pod,pod_usage_cpu_core_seconds,pod_request_cpu_core_seconds,pod_limit_cpu_core_seconds,pod_usage_memory_byte_seconds,pod_request_memory_byte_seconds,pod_limit_memory_byte_seconds,node_capacity_cpu_cores,node_capacity_cpu_core_seconds,node_capacity_memory_bytes,node_capacity_memory_byte_seconds,node_role,resource_id,pod_labels
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 14:00:00 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,zip-1,150,250,350,1500,2500,3500,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web|label_rht_comp:EAP
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,2025-05-17 16:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,zip-1,200,300,400,2000,3000,4000,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web|label_rht_comp:EAP`

	reader := csv.NewReader(strings.NewReader(csvData))
	err = ProcessCSV(ctx, repo, reader, clusterID)
	assert.NoError(t, err)

	// Get node ID
	var nodeID string
	err = pool.QueryRow(context.Background(), "SELECT id FROM nodes WHERE name = $1 AND cluster_id = $2", nodeName, clusterID).Scan(&nodeID)
	require.NoError(t, err)
	nodeUUID, _ := uuid.Parse(nodeID)

	// Check node_daily_summary - should have 2 unique hours
	var totalHours int
	err = pool.QueryRow(context.Background(), "SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3", nodeUUID, "2025-05-17", 4).Scan(&totalHours)
	assert.NoError(t, err)
	assert.Equal(t, 2, totalHours, "node_daily_summary should have 2 hours (14:00, 15:00)")

	// Get pod ID
	var podID string
	err = pool.QueryRow(context.Background(), "SELECT id FROM pods WHERE name = $1 AND namespace = $2 AND cluster_id = $3", podName, namespace, clusterID).Scan(&podID)
	require.NoError(t, err)
	podUUID, _ := uuid.Parse(podID)

	// Check pod_daily_summary - should have 2 unique hours
	var podTotalHours int
	var totalEffectiveCoreSeconds float64
	err = pool.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podUUID, "2025-05-17").Scan(&podTotalHours, &totalEffectiveCoreSeconds)
	assert.NoError(t, err)
	assert.Equal(t, 2, podTotalHours, "pod_daily_summary should have 2 unique hours")
	// Hour 14:00: max(150, 250) = 250
	// Hour 15:00: max(200, 300) = 300
	// Total: 250 + 300 = 550
	assert.Equal(t, 550.0, totalEffectiveCoreSeconds, "pod_daily_summary should sum effective core seconds (250 + 300)")

	// Check pod_metrics for 14:00 - should have the values from the record
	var podUsage, podRequest float64
	err = pool.QueryRow(context.Background(),
		"SELECT pod_usage_cpu_core_seconds, pod_request_cpu_core_seconds FROM pod_metrics WHERE pod_id = $1 AND timestamp = $2",
		podUUID, "2025-05-17 14:00:00+00").Scan(&podUsage, &podRequest)
	assert.NoError(t, err)
	assert.Equal(t, 150.0, podUsage, "pod_metrics should have usage for 14:00")
	assert.Equal(t, 250.0, podRequest, "pod_metrics should have request for 14:00")

	// Check pod_metrics for 15:00
	err = pool.QueryRow(context.Background(),
		"SELECT pod_usage_cpu_core_seconds, pod_request_cpu_core_seconds FROM pod_metrics WHERE pod_id = $1 AND timestamp = $2",
		podUUID, "2025-05-17 15:00:00+00").Scan(&podUsage, &podRequest)
	assert.NoError(t, err)
	assert.Equal(t, 200.0, podUsage, "pod_metrics should have usage for 15:00")
	assert.Equal(t, 300.0, podRequest, "pod_metrics should have request for 15:00")
}

func TestProcessCSVInvalidTimestamp(t *testing.T) {
	pool := testutils.SetupTestDB(t)
	repo := db.NewRepository(pool)
	clusterID := "10f5a0f9-223a-41c1-8456-9a3eb0323a99"
	ctx := context.Background()

	csvData := `report_period_start,report_period_end,interval_start,interval_end,node,namespace,pod,pod_usage_cpu_core_seconds,pod_request_cpu_core_seconds,pod_limit_cpu_core_seconds,pod_usage_memory_byte_seconds,pod_request_memory_byte_seconds,pod_limit_memory_byte_seconds,node_capacity_cpu_cores,node_capacity_cpu_core_seconds,node_capacity_memory_bytes,node_capacity_memory_byte_seconds,node_role,resource_id,pod_labels
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,invalid-timestamp,2025-05-17 15:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,zip-1,100,200,300,1000,2000,3000,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web|label_rht_comp:EAP`

	reader := csv.NewReader(strings.NewReader(csvData))
	reader.Comma = ','
	reader.TrimLeadingSpace = true

	err := ProcessCSV(ctx, repo, reader, clusterID)
	assert.NoError(t, err)

	var count int
	err = pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM pod_metrics").Scan(&count)
	assert.NoError(t, err)
	assert.Equal(t, 0, count, "No metrics should be inserted for invalid timestamp")
}

func TestProcessCSVMissingLabel(t *testing.T) {
	pool := testutils.SetupTestDB(t)
	repo := db.NewRepository(pool)
	clusterID := "10f5a0f9-223a-41c1-8456-9a3eb0323a99"
	ctx := context.Background()

	os.Setenv("POD_LABEL_KEYS", "label_rht_comp")
	defer os.Unsetenv("POD_LABEL_KEYS")

	csvData := `report_period_start,report_period_end,interval_start,interval_end,node,namespace,pod,pod_usage_cpu_core_seconds,pod_request_cpu_core_seconds,pod_limit_cpu_core_seconds,pod_usage_memory_byte_seconds,pod_request_memory_byte_seconds,pod_limit_memory_byte_seconds,node_capacity_cpu_cores,node_capacity_cpu_core_seconds,node_capacity_memory_bytes,node_capacity_memory_byte_seconds,node_role,resource_id,pod_labels
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 14:00:00 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,zip-1,100,200,300,1000,2000,3000,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web`

	reader := csv.NewReader(strings.NewReader(csvData))
	reader.Comma = ','
	reader.TrimLeadingSpace = true

	err := ProcessCSV(ctx, repo, reader, clusterID)
	assert.NoError(t, err)

	var count int
	err = pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM pod_metrics").Scan(&count)
	assert.NoError(t, err)
	assert.Equal(t, 0, count, "No pod metrics should be inserted without matching label")
}

// Made with Bob 1.0.1
// TestProcessCSVTotalHoursCount verifies that total_hours counts unique hours, not total records
// This test reproduces the bug where 55 records would show 55 hours instead of the actual unique hours
func TestProcessCSVTotalHoursCount(t *testing.T) {
	pool := testutils.SetupTestDB(t)
	repo := db.NewRepository(pool)
	ctx := context.Background()

	os.Setenv("POD_LABEL_KEYS", "label_rht_comp")
	defer os.Unsetenv("POD_LABEL_KEYS")

	clusterID := "10f5a0f9-223a-41c1-8456-9a3eb0323a99"
	clusterUUID, _ := uuid.Parse(clusterID)

	// Setup cluster
	err := repo.UpsertCluster(clusterUUID, "test-cluster")
	require.NoError(t, err)

	// Create CSV with multiple records in the same hours
	// Simulates the scenario: 1 pod, 3 unique hours, but 55 total records
	// Hour 14:00 - 20 records
	// Hour 15:00 - 20 records
	// Hour 16:00 - 15 records
	// Total: 55 records, but only 3 unique hours
	csvBuilder := strings.Builder{}
	csvBuilder.WriteString("report_period_start,report_period_end,interval_start,interval_end,node,namespace,pod,pod_usage_cpu_core_seconds,pod_request_cpu_core_seconds,pod_limit_cpu_core_seconds,pod_usage_memory_byte_seconds,pod_request_memory_byte_seconds,pod_limit_memory_byte_seconds,node_capacity_cpu_cores,node_capacity_cpu_core_seconds,node_capacity_memory_bytes,node_capacity_memory_byte_seconds,node_role,resource_id,pod_labels\n")

	// Generate 20 records for hour 14:00
	for i := 0; i < 20; i++ {
		csvBuilder.WriteString("2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 14:00:00 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,eap-pod-1,100,200,300,1000,2000,3000,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web|label_rht_comp:EAP\n")
	}

	// Generate 20 records for hour 15:00
	for i := 0; i < 20; i++ {
		csvBuilder.WriteString("2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,2025-05-17 16:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,eap-pod-1,150,250,350,1500,2500,3500,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web|label_rht_comp:EAP\n")
	}

	// Generate 15 records for hour 16:00
	for i := 0; i < 15; i++ {
		csvBuilder.WriteString("2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 16:00:00 +0000 UTC,2025-05-17 17:00:00 +0000 UTC,ip-10-0-1-63.ec2.internal,test,eap-pod-1,200,300,400,2000,3000,4000,4,14400,17179869184,61729433600,worker,i-09ad6102842b9a786,app:web|label_rht_comp:EAP\n")
	}

	reader := csv.NewReader(strings.NewReader(csvBuilder.String()))
	err = ProcessCSV(ctx, repo, reader, clusterID)
	assert.NoError(t, err)

	// Query pod_daily_summary to check total_hours
	var totalHours int
	var totalPodEffectiveCoreSeconds float64
	err = pool.QueryRow(context.Background(),
		`SELECT total_hours, total_pod_effective_core_seconds 
		 FROM pod_daily_summary pds
		 JOIN pods p ON pds.pod_id = p.id
		 WHERE p.name = $1 AND pds.date = $2`,
		"eap-pod-1", "2025-05-17").Scan(&totalHours, &totalPodEffectiveCoreSeconds)

	require.NoError(t, err, "Should find pod_daily_summary record")

	// The fix: total_hours should be 3 (unique hours: 14:00, 15:00, 16:00)
	// NOT 55 (total number of records)
	assert.Equal(t, 3, totalHours, "total_hours should count unique hours (3), not total records (55)")

	// Verify the aggregated core seconds are correct
	// The new logic stores ONE metric per hour (not per record)
	// Hour 14:00: max(usage=100, request=200) = 200
	// Hour 15:00: max(usage=150, request=250) = 250
	// Hour 16:00: max(usage=200, request=300) = 300
	// Total: 200 + 250 + 300 = 750
	expectedTotalCoreSeconds := 200.0 + 250.0 + 300.0
	assert.InDelta(t, expectedTotalCoreSeconds, totalPodEffectiveCoreSeconds, 0.01,
		"total_pod_effective_core_seconds should sum the effective core seconds for each unique hour")
}

// Made with Bob 1.0.1
// TestProcessCSVMultipleDaysHours verifies total_hours across multiple days
func TestProcessCSVMultipleDaysHours(t *testing.T) {
	pool := testutils.SetupTestDB(t)
	repo := db.NewRepository(pool)
	ctx := context.Background()

	os.Setenv("POD_LABEL_KEYS", "label_rht_comp")
	defer os.Unsetenv("POD_LABEL_KEYS")

	clusterID := "10f5a0f9-223a-41c1-8456-9a3eb0323a99"
	clusterUUID, _ := uuid.Parse(clusterID)

	err := repo.UpsertCluster(clusterUUID, "test-cluster")
	require.NoError(t, err)

	// CSV with data across 2 days
	// Day 1 (May 17): 2 unique hours (14:00, 15:00) with 10 records each
	// Day 2 (May 18): 3 unique hours (10:00, 11:00, 12:00) with 5 records each
	csvData := `report_period_start,report_period_end,interval_start,interval_end,node,namespace,pod,pod_usage_cpu_core_seconds,pod_request_cpu_core_seconds,pod_limit_cpu_core_seconds,pod_usage_memory_byte_seconds,pod_request_memory_byte_seconds,pod_limit_memory_byte_seconds,node_capacity_cpu_cores,node_capacity_cpu_core_seconds,node_capacity_memory_bytes,node_capacity_memory_byte_seconds,node_role,resource_id,pod_labels
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 14:00:00 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,node-1,test,pod-1,100,200,300,1000,2000,3000,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 14:00:00 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,node-1,test,pod-1,100,200,300,1000,2000,3000,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,2025-05-17 16:00:00 +0000 UTC,node-1,test,pod-1,150,250,350,1500,2500,3500,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP
2025-05-17 00:00:00 +0000 UTC,2025-05-17 23:59:59 +0000 UTC,2025-05-17 15:00:00 +0000 UTC,2025-05-17 16:00:00 +0000 UTC,node-1,test,pod-1,150,250,350,1500,2500,3500,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP
2025-05-18 00:00:00 +0000 UTC,2025-05-18 23:59:59 +0000 UTC,2025-05-18 10:00:00 +0000 UTC,2025-05-18 11:00:00 +0000 UTC,node-1,test,pod-1,200,300,400,2000,3000,4000,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP
2025-05-18 00:00:00 +0000 UTC,2025-05-18 23:59:59 +0000 UTC,2025-05-18 11:00:00 +0000 UTC,2025-05-18 12:00:00 +0000 UTC,node-1,test,pod-1,250,350,450,2500,3500,4500,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP
2025-05-18 00:00:00 +0000 UTC,2025-05-18 23:59:59 +0000 UTC,2025-05-18 12:00:00 +0000 UTC,2025-05-18 13:00:00 +0000 UTC,node-1,test,pod-1,300,400,500,3000,4000,5000,4,14400,17179869184,61729433600,worker,i-123,label_rht_comp:EAP`

	reader := csv.NewReader(strings.NewReader(csvData))
	err = ProcessCSV(ctx, repo, reader, clusterID)
	assert.NoError(t, err)

	// Check Day 1 (May 17) - should have 2 unique hours
	var day1Hours int
	err = pool.QueryRow(context.Background(),
		`SELECT total_hours FROM pod_daily_summary pds
		 JOIN pods p ON pds.pod_id = p.id
		 WHERE p.name = $1 AND pds.date = $2`,
		"pod-1", "2025-05-17").Scan(&day1Hours)
	require.NoError(t, err)
	assert.Equal(t, 2, day1Hours, "Day 1 should have 2 unique hours (14:00, 15:00)")

	// Check Day 2 (May 18) - should have 3 unique hours
	var day2Hours int
	err = pool.QueryRow(context.Background(),
		`SELECT total_hours FROM pod_daily_summary pds
		 JOIN pods p ON pds.pod_id = p.id
		 WHERE p.name = $1 AND pds.date = $2`,
		"pod-1", "2025-05-18").Scan(&day2Hours)
	require.NoError(t, err)
	assert.Equal(t, 3, day2Hours, "Day 2 should have 3 unique hours (10:00, 11:00, 12:00)")
}

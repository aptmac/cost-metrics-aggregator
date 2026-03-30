package db

import (
	"context"
	"testing"
	"time"

	"github.com/aptmac/cost-metrics-aggregator/internal/db/testutils"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUpsertNode(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"

	time.Sleep(500 * time.Millisecond)
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	assert.NoError(t, err)
	assert.NotEqual(t, uuid.Nil, nodeID)
	time.Sleep(500 * time.Millisecond)

	var count int
	err = tx.QueryRow(context.Background(), "SELECT COUNT(*) FROM nodes WHERE id = $1", nodeID).Scan(&count)
	assert.NoError(t, err)
	assert.Equal(t, 1, count)
}

func TestInsertNodeMetric(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"

	// Ensure node exists
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)
	time.Sleep(500 * time.Millisecond)
	now := time.Now().UTC()
	year, month := now.Year(), now.Month()

	timestamp := time.Date(year, month, 15, 14, 0, 0, 0, time.UTC)
	coreCount := 4

	err = repo.InsertNodeMetric(nodeID, timestamp, coreCount, clusterID)
	assert.NoError(t, err)

	var count int
	err = tx.QueryRow(context.Background(), "SELECT COUNT(*) FROM node_metrics WHERE node_id = $1", nodeID).Scan(&count)
	assert.NoError(t, err)
	assert.Equal(t, 1, count, "Expected one row in node_metrics")
}

func TestUpdateNodeDailySummary(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"

	// Ensure node exists
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	timestamp, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")
	coreCount := 4

	err = repo.UpdateNodeDailySummary(nodeID, timestamp, coreCount)
	assert.NoError(t, err)

	var totalHours int
	err = tx.QueryRow(context.Background(), "SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2", nodeID, "2025-05-17").Scan(&totalHours)
	assert.NoError(t, err)
	assert.Equal(t, 1, totalHours)
}

// Made with Bob 1.0.1
// TestUpdateNodeDailySummary_NoDoubleAggregation verifies that calling UpdateNodeDailySummary
// multiple times with the same node_id, date, and core_count correctly increments total_hours
// without double-counting. This tests the fix for the double aggregation issue.
func TestUpdateNodeDailySummary_NoDoubleAggregation(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"

	// Create node
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	timestamp, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")
	coreCount := 4

	// First update - should create entry with total_hours = 1
	err = repo.UpdateNodeDailySummary(nodeID, timestamp, coreCount)
	require.NoError(t, err)

	var totalHours int
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, "2025-05-17", coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours, "First update should set total_hours to 1")

	// Second update with same parameters - should increment to 2
	err = repo.UpdateNodeDailySummary(nodeID, timestamp, coreCount)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, "2025-05-17", coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 2, totalHours, "Second update should increment total_hours to 2")

	// Third update - should increment to 3
	err = repo.UpdateNodeDailySummary(nodeID, timestamp, coreCount)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, "2025-05-17", coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 3, totalHours, "Third update should increment total_hours to 3")
}

// Made with Bob 1.0.1
// TestUpdateNodeDailySummary_DifferentCoreCountsSameDay verifies that different core counts
// on the same day create separate entries in node_daily_summary
func TestUpdateNodeDailySummary_DifferentCoreCountsSameDay(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"

	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	timestamp, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")

	// Update with core_count = 4
	err = repo.UpdateNodeDailySummary(nodeID, timestamp, 4)
	require.NoError(t, err)

	// Update with core_count = 8
	err = repo.UpdateNodeDailySummary(nodeID, timestamp, 8)
	require.NoError(t, err)

	// Verify two separate entries exist
	var count int
	err = tx.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM node_daily_summary WHERE node_id = $1 AND date = $2",
		nodeID, "2025-05-17").Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 2, count, "Should have two entries for different core counts")

	// Verify each has total_hours = 1
	var totalHours4, totalHours8 int
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, "2025-05-17", 4).Scan(&totalHours4)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours4)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, "2025-05-17", 8).Scan(&totalHours8)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours8)
}

func TestUpsertPod(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"
	podName := "zip-1"
	namespace := "test"
	component := "EAP"

	// Ensure node exists
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	assert.NoError(t, err)
	assert.NotEqual(t, uuid.Nil, podID)

	var count int
	err = tx.QueryRow(context.Background(), "SELECT COUNT(*) FROM pods WHERE id = $1 AND name = $2 AND namespace = $3", podID, podName, namespace).Scan(&count)
	assert.NoError(t, err)
	assert.Equal(t, 1, count)
}

func TestInsertPodMetric(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"
	podName := "zip-1"
	namespace := "test"
	component := "EAP"

	// Ensure node exists
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	// Insert pod to satisfy foreign key constraint
	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)
	now := time.Now().UTC()
	year, month := now.Year(), now.Month()

	// Pick a day in this month
	timestamp := time.Date(year, month, 15, 14, 0, 0, 0, time.UTC)

	usage := 100.0
	request := 200.0
	nodeCap := 14400.0
	coreCount := 4

	err = repo.InsertPodMetric(podID, timestamp, usage, request, nodeCap, coreCount)
	assert.NoError(t, err)

	var count int
	err = tx.QueryRow(context.Background(), "SELECT COUNT(*) FROM pod_metrics WHERE pod_id = $1 AND timestamp = $2", podID, timestamp).Scan(&count)
	assert.NoError(t, err)
	assert.Equal(t, 1, count, "Expected one row in pod_metrics")
}

// Made with Bob 1.0.1
// TestInsertPodMetric_NoDoubleAggregation verifies that calling InsertPodMetric
// multiple times with the same pod_id and timestamp replaces values instead of
// aggregating them. This tests the fix for the double aggregation bug.
func TestInsertPodMetric_NoDoubleAggregation(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"
	podName := "test-pod"
	namespace := "test-namespace"
	component := "test-component"

	// Create node and pod
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)

	now := time.Now().UTC()
	year, month := now.Year(), now.Month()
	timestamp := time.Date(year, month, 15, 14, 0, 0, 0, time.UTC)

	// First insert
	usage1 := 100.0
	request1 := 200.0
	nodeCap := 14400.0
	coreCount := 4

	err = repo.InsertPodMetric(podID, timestamp, usage1, request1, nodeCap, coreCount)
	require.NoError(t, err)

	// Verify first insert
	var storedUsage, storedRequest float64
	err = tx.QueryRow(context.Background(),
		"SELECT pod_usage_cpu_core_seconds, pod_request_cpu_core_seconds FROM pod_metrics WHERE pod_id = $1 AND timestamp = $2",
		podID, timestamp).Scan(&storedUsage, &storedRequest)
	require.NoError(t, err)
	assert.InDelta(t, 100.0, storedUsage, 0.001, "First insert should set usage to 100.0")
	assert.InDelta(t, 200.0, storedRequest, 0.001, "First insert should set request to 200.0")

	// Second insert with same timestamp - should REPLACE, not aggregate
	usage2 := 150.0
	request2 := 250.0

	err = repo.InsertPodMetric(podID, timestamp, usage2, request2, nodeCap, coreCount)
	require.NoError(t, err)

	// Verify second insert replaced the values (not aggregated)
	err = tx.QueryRow(context.Background(),
		"SELECT pod_usage_cpu_core_seconds, pod_request_cpu_core_seconds FROM pod_metrics WHERE pod_id = $1 AND timestamp = $2",
		podID, timestamp).Scan(&storedUsage, &storedRequest)
	require.NoError(t, err)

	// With the FIX: values should be replaced (150.0, 250.0)
	// With the BUG: values would be aggregated (100+150=250.0, 200+250=450.0)
	assert.InDelta(t, 150.0, storedUsage, 0.001, "Second insert should REPLACE usage to 150.0, not aggregate to 250.0")
	assert.InDelta(t, 250.0, storedRequest, 0.001, "Second insert should REPLACE request to 250.0, not aggregate to 450.0")

	// Verify only one row exists
	var count int
	err = tx.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM pod_metrics WHERE pod_id = $1 AND timestamp = $2",
		podID, timestamp).Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 1, count, "Should have exactly one row for this pod_id and timestamp")
}

func TestUpdatePodDailySummary(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"
	podName := "zip-1"
	namespace := "test"
	component := "EAP"

	// Ensure node exists
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	// Insert pod to satisfy foreign key constraint
	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)

	timestamp, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")
	effectiveCoreSeconds := 200.0
	coreUsage := 0.013888 // 200 / 14400

	err = repo.UpdatePodDailySummary(podID, timestamp, effectiveCoreSeconds, coreUsage)
	assert.NoError(t, err)

	var totalHours int
	var maxCoresUsed float64
	err = tx.QueryRow(context.Background(), "SELECT total_hours FROM pod_daily_summary WHERE pod_id = $1 AND date = $2", podID, "2025-05-17").Scan(&totalHours)
	assert.NoError(t, err)
	err = tx.QueryRow(context.Background(), "SELECT max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2", podID, "2025-05-17").Scan(&maxCoresUsed)
	assert.NoError(t, err)
	assert.Equal(t, 1, totalHours)
	assert.InDelta(t, 0.013888, maxCoresUsed, 0.000001)
}

// Made with Bob 1.0.1
// TestUpdatePodDailySummary_NoDoubleAggregation verifies that calling UpdatePodDailySummary
// multiple times correctly aggregates total_pod_effective_core_seconds and total_hours
// without double-counting. This tests the fix for the double aggregation issue.
func TestUpdatePodDailySummary_NoDoubleAggregation(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"
	podName := "test-pod"
	namespace := "test-namespace"
	component := "test-component"

	// Create node and pod
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)

	timestamp, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")
	effectiveCoreSeconds := 200.0
	coreUsage := 0.013888

	// First update - should create entry with total_hours = 1, total_pod_effective_core_seconds = 200.0
	err = repo.UpdatePodDailySummary(podID, timestamp, effectiveCoreSeconds, coreUsage)
	require.NoError(t, err)

	var totalHours int
	var totalEffectiveCoreSeconds float64
	var maxCoresUsed float64
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds, max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, "2025-05-17").Scan(&totalHours, &totalEffectiveCoreSeconds, &maxCoresUsed)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours, "First update should set total_hours to 1")
	assert.InDelta(t, 200.0, totalEffectiveCoreSeconds, 0.001, "First update should set total_pod_effective_core_seconds to 200.0")
	assert.InDelta(t, 0.013888, maxCoresUsed, 0.000001, "First update should set max_cores_used to 0.013888")

	// Second update with same parameters - should increment total_hours to 2 and add to total_pod_effective_core_seconds
	err = repo.UpdatePodDailySummary(podID, timestamp, effectiveCoreSeconds, coreUsage)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds, max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, "2025-05-17").Scan(&totalHours, &totalEffectiveCoreSeconds, &maxCoresUsed)
	require.NoError(t, err)
	assert.Equal(t, 2, totalHours, "Second update should increment total_hours to 2")
	assert.InDelta(t, 400.0, totalEffectiveCoreSeconds, 0.001, "Second update should add to total_pod_effective_core_seconds (200 + 200 = 400)")
	assert.InDelta(t, 0.013888, maxCoresUsed, 0.000001, "max_cores_used should remain the same")

	// Third update with higher core usage - should update max_cores_used
	higherCoreUsage := 0.025
	err = repo.UpdatePodDailySummary(podID, timestamp, effectiveCoreSeconds, higherCoreUsage)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds, max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, "2025-05-17").Scan(&totalHours, &totalEffectiveCoreSeconds, &maxCoresUsed)
	require.NoError(t, err)
	assert.Equal(t, 3, totalHours, "Third update should increment total_hours to 3")
	assert.InDelta(t, 600.0, totalEffectiveCoreSeconds, 0.001, "Third update should add to total_pod_effective_core_seconds (400 + 200 = 600)")
	assert.InDelta(t, 0.025, maxCoresUsed, 0.000001, "max_cores_used should be updated to the higher value")
}

// Made with Bob 1.0.1
// TestUpdatePodDailySummary_MaxCoresUsedTracking verifies that max_cores_used
// correctly tracks the maximum value across multiple updates
func TestUpdatePodDailySummary_MaxCoresUsedTracking(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"
	podName := "test-pod"
	namespace := "test-namespace"
	component := "test-component"

	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)

	timestamp, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")

	// Update with increasing core usage values
	coreUsageValues := []float64{0.01, 0.05, 0.03, 0.08, 0.02}
	effectiveCoreSeconds := 200.0

	for _, coreUsage := range coreUsageValues {
		err = repo.UpdatePodDailySummary(podID, timestamp, effectiveCoreSeconds, coreUsage)
		require.NoError(t, err)
	}

	var maxCoresUsed float64
	err = tx.QueryRow(context.Background(),
		"SELECT max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, "2025-05-17").Scan(&maxCoresUsed)
	require.NoError(t, err)
	assert.InDelta(t, 0.08, maxCoresUsed, 0.000001, "max_cores_used should be the maximum value (0.08)")
}

// Made with Bob 1.0.1
// TestUpdatePodDailySummary_DifferentDays verifies that updates on different days
// create separate entries in pod_daily_summary
func TestUpdatePodDailySummary_DifferentDays(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"
	podName := "test-pod"
	namespace := "test-namespace"
	component := "test-component"

	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)

	timestamp1, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-17 14:00:00 +0000 UTC")
	timestamp2, _ := time.Parse("2006-01-02 15:04:05 +0000 MST", "2025-05-18 14:00:00 +0000 UTC")
	effectiveCoreSeconds := 200.0
	coreUsage := 0.013888

	// Update for day 1
	err = repo.UpdatePodDailySummary(podID, timestamp1, effectiveCoreSeconds, coreUsage)
	require.NoError(t, err)

	// Update for day 2
	err = repo.UpdatePodDailySummary(podID, timestamp2, effectiveCoreSeconds, coreUsage)
	require.NoError(t, err)

	// Verify two separate entries exist
	var count int
	err = tx.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM pod_daily_summary WHERE pod_id = $1",
		podID).Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 2, count, "Should have two entries for different days")

	// Verify each has total_hours = 1
	var totalHours1, totalHours2 int
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, "2025-05-17").Scan(&totalHours1)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours1)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, "2025-05-18").Scan(&totalHours2)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours2)
}

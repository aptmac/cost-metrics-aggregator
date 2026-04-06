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
	pool, _ := testutils.SetupTestDB(t)

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "ip-10-0-1-63.ec2.internal"
	identifier := "i-09ad6102842b9a786"
	nodeRole := "worker"

	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	assert.NoError(t, err)
	assert.NotEqual(t, uuid.Nil, nodeID)

	// Verify the node was created using the pool
	var count int
	err = pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM nodes WHERE id = $1", nodeID).Scan(&count)
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

	// Use fixed date in May 2025 (partition exists for this month)
	timestamp := time.Date(2025, 5, 15, 14, 0, 0, 0, time.UTC)
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

	dateStr := "2025-05-17"
	coreCount := 4
	hourCount := 1

	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, hourCount)
	assert.NoError(t, err)

	var totalHours int
	err = tx.QueryRow(context.Background(), "SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2", nodeID, dateStr).Scan(&totalHours)
	assert.NoError(t, err)
	assert.Equal(t, 1, totalHours)
}

// Made with Bob 1.0.1
// TestUpdateNodeDailySummary_NoDoubleAggregation verifies that calling UpdateNodeDailySummary
// multiple times with the same node_id, date, and core_count uses GREATEST for total_hours
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

	dateStr := "2025-05-17"
	coreCount := 4

	// First update - should create entry with total_hours = 1
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, 1)
	require.NoError(t, err)

	var totalHours int
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, dateStr, coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours, "First update should set total_hours to 1")

	// Second update with same parameters - should keep at 1 (using GREATEST, not adding)
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, 1)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, dateStr, coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours, "Second update should keep total_hours at 1 (not 2)")

	// Third update with more hours - should update to 3
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, 3)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, dateStr, coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 3, totalHours, "Third update should set total_hours to 3 (GREATEST of 1 and 3)")
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

	dateStr := "2025-05-17"

	// Update with core_count = 4
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, 4, 1)
	require.NoError(t, err)

	// Update with core_count = 8
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, 8, 1)
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

	// Use fixed date in May 2025 (partition exists for this month)
	timestamp := time.Date(2025, 5, 15, 14, 0, 0, 0, time.UTC)

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

	// Use fixed date in May 2025 (partition exists for this month)
	timestamp := time.Date(2025, 5, 15, 14, 0, 0, 0, time.UTC)

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

	dateStr := "2025-05-17"
	effectiveCoreSeconds := 200.0
	coreUsage := 0.013888 // 200 / 14400

	err = repo.UpdatePodDailySummary(podID, dateStr, coreUsage, effectiveCoreSeconds, 1)
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

	dateStr := "2025-05-17"
	effectiveCoreSeconds := 200.0
	coreUsage := 0.013888

	// First update - should create entry with total_hours = 1, total_pod_effective_core_seconds = 200.0
	err = repo.UpdatePodDailySummary(podID, dateStr, coreUsage, effectiveCoreSeconds, 1)
	require.NoError(t, err)

	var totalHours int
	var totalEffectiveCoreSeconds float64
	var maxCoresUsed float64
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds, max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds, &maxCoresUsed)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours, "First update should set total_hours to 1")
	assert.InDelta(t, 200.0, totalEffectiveCoreSeconds, 0.001, "First update should set total_pod_effective_core_seconds to 200.0")
	assert.InDelta(t, 0.013888, maxCoresUsed, 0.000001, "First update should set max_cores_used to 0.013888")

	// Second update with same parameters - should keep total_hours at 1 (GREATEST) and REPLACE total_pod_effective_core_seconds
	err = repo.UpdatePodDailySummary(podID, dateStr, coreUsage, effectiveCoreSeconds, 1)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds, max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds, &maxCoresUsed)
	require.NoError(t, err)
	assert.Equal(t, 1, totalHours, "Second update should keep total_hours at 1 (using GREATEST, not adding)")
	assert.InDelta(t, 200.0, totalEffectiveCoreSeconds, 0.001, "Second update should REPLACE total_pod_effective_core_seconds (stays at 200, not 400)")
	assert.InDelta(t, 0.013888, maxCoresUsed, 0.000001, "max_cores_used should remain the same")

	// Third update with higher core usage and more hours - should update max_cores_used, total_hours, and replace core_seconds
	higherCoreUsage := 0.025
	higherEffectiveCoreSeconds := 300.0
	err = repo.UpdatePodDailySummary(podID, dateStr, higherCoreUsage, higherEffectiveCoreSeconds, 3)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds, max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds, &maxCoresUsed)
	require.NoError(t, err)
	assert.Equal(t, 3, totalHours, "Third update should set total_hours to 3 (GREATEST of 1 and 3)")
	assert.InDelta(t, 300.0, totalEffectiveCoreSeconds, 0.001, "Third update should REPLACE total_pod_effective_core_seconds (300, not 500)")
	assert.InDelta(t, 0.025, maxCoresUsed, 0.000001, "max_cores_used should be updated to the higher value")
}

// Made with Bob 1.0.1
// TestUpdatePodDailySummary_IdempotentHourCounting verifies that processing the same
// CSV data multiple times (e.g., due to re-uploads or overlapping data) does not
// inflate the total_hours count. This is the fix for the bug where 5 unique hours
// became 15 hours after processing the same data 3 times.
func TestUpdatePodDailySummary_IdempotentHourCounting(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "test-node"
	identifier := "test-identifier"
	nodeRole := "worker"
	podName := "eap74-helloworld-5575bdb44c-mk9j4"
	namespace := "eap74"
	component := "EAP"

	// Create node and pod
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	podID, err := repo.UpsertPod(clusterID, nodeID, podName, namespace, component)
	require.NoError(t, err)

	dateStr := "2026-03-30"
	effectiveCoreSeconds := 963.264898
	maxCoreUsage := 0.0018430536805555554

	// Simulate first CSV upload with 5 unique hours of data
	err = repo.UpdatePodDailySummary(podID, dateStr, maxCoreUsage, effectiveCoreSeconds, 5)
	require.NoError(t, err)

	var totalHours int
	var totalEffectiveCoreSeconds float64
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds)
	require.NoError(t, err)
	assert.Equal(t, 5, totalHours, "First upload: should have 5 hours")
	assert.InDelta(t, 963.264898, totalEffectiveCoreSeconds, 0.001, "First upload: correct core seconds")

	// Simulate second CSV upload with the SAME 5 hours (overlapping data)
	// This should NOT increase total_hours (should use GREATEST, not add)
	// Core seconds should be REPLACED (not added) to prevent inflation
	err = repo.UpdatePodDailySummary(podID, dateStr, maxCoreUsage, effectiveCoreSeconds, 5)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds)
	require.NoError(t, err)
	assert.Equal(t, 5, totalHours, "Second upload: should STILL have 5 hours (not 10)")
	assert.InDelta(t, 963.264898, totalEffectiveCoreSeconds, 0.001, "Second upload: core seconds should be REPLACED (stays at 963, not 1926)")

	// Simulate third CSV upload with the SAME 5 hours
	// Before the fix, this would result in 15 hours (5+5+5) and 2889 core-seconds
	// After the fix, it should remain 5 hours and 963 core-seconds
	err = repo.UpdatePodDailySummary(podID, dateStr, maxCoreUsage, effectiveCoreSeconds, 5)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds)
	require.NoError(t, err)
	assert.Equal(t, 5, totalHours, "Third upload: should STILL have 5 hours (not 15) - THIS IS THE BUG FIX")
	assert.InDelta(t, 963.264898, totalEffectiveCoreSeconds, 0.001, "Third upload: core seconds should STILL be 963 (not 2889) - THIS IS THE BUG FIX")

	// Now simulate a legitimate update with MORE hours (e.g., new data arrived)
	newEffectiveCoreSeconds := 1200.0
	err = repo.UpdatePodDailySummary(podID, dateStr, maxCoreUsage, newEffectiveCoreSeconds, 7)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours, total_pod_effective_core_seconds FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&totalHours, &totalEffectiveCoreSeconds)
	require.NoError(t, err)
	assert.Equal(t, 7, totalHours, "Fourth upload: should update to 7 hours (GREATEST of 5 and 7)")
	assert.InDelta(t, 1200.0, totalEffectiveCoreSeconds, 0.001, "Fourth upload: core seconds should be REPLACED with new value (1200)")
}

// Made with Bob 1.0.1
// TestUpdateNodeDailySummary_IdempotentHourCounting verifies the same idempotent
// behavior for node metrics
func TestUpdateNodeDailySummary_IdempotentHourCounting(t *testing.T) {
	pool, newTx := testutils.SetupTestDB(t)
	tx := newTx()
	defer tx.Rollback(context.Background())

	repo := NewRepository(pool)

	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	nodeName := "worker-node-1"
	identifier := "i-1234567890"
	nodeRole := "worker"

	// Create node
	nodeID, err := repo.UpsertNode(clusterID, nodeName, identifier, nodeRole)
	require.NoError(t, err)

	dateStr := "2026-03-30"
	coreCount := 12

	// First upload: 4 unique hours
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, 4)
	require.NoError(t, err)

	var totalHours int
	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, dateStr, coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 4, totalHours, "First upload: should have 4 hours")

	// Second upload: same 4 hours (overlapping data)
	// Before fix: would become 8 hours (4+4)
	// After fix: should remain 4 hours
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, 4)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, dateStr, coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 4, totalHours, "Second upload: should STILL have 4 hours (not 8) - THIS IS THE BUG FIX")

	// Third upload: more hours (legitimate new data)
	err = repo.UpdateNodeDailySummary(nodeID, dateStr, coreCount, 6)
	require.NoError(t, err)

	err = tx.QueryRow(context.Background(),
		"SELECT total_hours FROM node_daily_summary WHERE node_id = $1 AND date = $2 AND core_count = $3",
		nodeID, dateStr, coreCount).Scan(&totalHours)
	require.NoError(t, err)
	assert.Equal(t, 6, totalHours, "Third upload: should update to 6 hours (GREATEST of 4 and 6)")
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

	dateStr := "2025-05-17"

	// Update with increasing core usage values
	coreUsageValues := []float64{0.01, 0.05, 0.03, 0.08, 0.02}
	effectiveCoreSeconds := 200.0

	for _, coreUsage := range coreUsageValues {
		err = repo.UpdatePodDailySummary(podID, dateStr, coreUsage, effectiveCoreSeconds, 1)
		require.NoError(t, err)
	}

	var maxCoresUsed float64
	err = tx.QueryRow(context.Background(),
		"SELECT max_cores_used FROM pod_daily_summary WHERE pod_id = $1 AND date = $2",
		podID, dateStr).Scan(&maxCoresUsed)
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

	dateStr1 := "2025-05-17"
	dateStr2 := "2025-05-18"
	effectiveCoreSeconds := 200.0
	coreUsage := 0.013888

	// Update for day 1
	err = repo.UpdatePodDailySummary(podID, dateStr1, coreUsage, effectiveCoreSeconds, 1)
	require.NoError(t, err)

	// Update for day 2
	err = repo.UpdatePodDailySummary(podID, dateStr2, coreUsage, effectiveCoreSeconds, 1)
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

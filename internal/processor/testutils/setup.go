package testutils

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

// Global mutex to prevent concurrent schema setup across all tests
var setupMutex sync.Mutex

func SetupTestDB(t *testing.T) *pgxpool.Pool {
	// Lock to prevent concurrent schema setup
	setupMutex.Lock()
	defer setupMutex.Unlock()

	dbURL := "postgres://costmetrics:costmetrics@localhost:5432/costmetrics?sslmode=disable"
	config, err := pgxpool.ParseConfig(dbURL)
	require.NoError(t, err)

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	require.NoError(t, err)

	// Check if schema exists by trying to query a table
	var schemaExists bool
	err = pool.QueryRow(context.Background(), "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clusters')").Scan(&schemaExists)

	if err != nil || !schemaExists {
		// Drop and recreate schema completely to avoid type conflicts
		_, err = pool.Exec(context.Background(), `
			DROP SCHEMA IF EXISTS public CASCADE;
			CREATE SCHEMA public;
			GRANT ALL ON SCHEMA public TO costmetrics;
			GRANT ALL ON SCHEMA public TO public;
		`)
		require.NoError(t, err)

		_, currentFile, _, ok := runtime.Caller(0)
		if !ok {
			panic("Could not get caller information")
		}
		currentDir := filepath.Dir(currentFile)

		schemaPath := filepath.Join(currentDir, "..", "..", "db", "migrations", "0001_init.up.sql")
		schema, err := os.ReadFile(schemaPath)
		require.NoError(t, err)
		_, err = pool.Exec(context.Background(), string(schema))
		require.NoError(t, err)

		// Create partition for May 2025 - all test data uses dates in this month (17, 18, 20)
		_, err = pool.Exec(context.Background(), `
			CREATE TABLE IF NOT EXISTS node_metrics_202505 PARTITION OF node_metrics
			FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
			CREATE TABLE IF NOT EXISTS pod_metrics_202505 PARTITION OF pod_metrics
			FOR VALUES FROM ('2025-05-01') TO ('2025-06-01')
		`)
		require.NoError(t, err)
	} else {
		// Schema exists, clean up data from previous tests
		_, err = pool.Exec(context.Background(), `
			TRUNCATE TABLE pod_metrics CASCADE;
			TRUNCATE TABLE node_metrics CASCADE;
			TRUNCATE TABLE pod_daily_summary CASCADE;
			TRUNCATE TABLE node_daily_summary CASCADE;
			TRUNCATE TABLE pods CASCADE;
			TRUNCATE TABLE nodes CASCADE;
			TRUNCATE TABLE clusters CASCADE;
		`)
		require.NoError(t, err)
		// Small delay to ensure cleanup completes
		time.Sleep(50 * time.Millisecond)
	}

	// Always ensure test partitions exist (in case DB was initialized by migrations without partitions)
	_, err = pool.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS node_metrics_202505 PARTITION OF node_metrics
		FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
		CREATE TABLE IF NOT EXISTS pod_metrics_202505 PARTITION OF pod_metrics
		FOR VALUES FROM ('2025-05-01') TO ('2025-06-01')
	`)
	require.NoError(t, err)

	// Insert test cluster and node for each test
	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	_, err = pool.Exec(context.Background(), `
		INSERT INTO clusters (id, name) VALUES ($1, 'test-cluster')
		ON CONFLICT (id) DO NOTHING
	`, clusterID)
	require.NoError(t, err)

	// Small delay to ensure cluster insert completes
	time.Sleep(100 * time.Millisecond)

	nodeID, _ := uuid.Parse("fba4e7cd-4ee2-4f24-880d-082eb2b41128")
	_, err = pool.Exec(context.Background(), `
		INSERT INTO nodes (id, cluster_id, name, identifier, type)
		VALUES ($1, $2, 'ip-10-0-1-63.ec2.internal', 'i-09ad6102842b9a786', 'worker')
		ON CONFLICT (identifier) DO NOTHING
	`, nodeID, clusterID)
	require.NoError(t, err)

	t.Cleanup(func() {
		pool.Close()
	})

	return pool
}

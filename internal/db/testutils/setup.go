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
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

// Global mutex to prevent concurrent schema setup across all tests
var setupMutex sync.Mutex

// SetupTestDB creates a database connection pool and sets up the schema for testing.
// It returns the pool and a function to start a new transaction for each test case.
// The pool is closed only after all tests in the suite complete.
func SetupTestDB(t *testing.T) (*pgxpool.Pool, func() pgx.Tx) {
	// Lock to prevent concurrent schema setup
	setupMutex.Lock()
	defer setupMutex.Unlock()

	dbURL := "postgres://costmetrics:costmetrics@localhost:5432/costmetrics?sslmode=disable"
	config, err := pgxpool.ParseConfig(dbURL)
	require.NoError(t, err)

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	require.NoError(t, err)

	// Use a mutex to ensure pool is closed only once
	var mu sync.Mutex
	closed := false

	// Close pool after all tests, ensuring it's called only once
	t.Cleanup(func() {
		mu.Lock()
		defer mu.Unlock()
		if !closed {
			pool.Close()
			closed = true
		}
	})

	// Check if schema exists by trying to query a table
	var schemaExists bool
	err = pool.QueryRow(context.Background(), "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'clusters')").Scan(&schemaExists)

	if err != nil || !schemaExists {
		// Drop and recreate schema completely to avoid type conflicts
		tx, err := pool.Begin(context.Background())
		require.NoError(t, err)

		_, err = tx.Exec(context.Background(), `
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

		schemaPath := filepath.Join(currentDir, "..", "migrations", "0001_init.up.sql")
		schema, err := os.ReadFile(schemaPath)
		require.NoError(t, err)
		_, err = tx.Exec(context.Background(), string(schema))
		require.NoError(t, err)

		// May 2025 partition (all tests use dates in this month)
		_, err = tx.Exec(context.Background(), `
			CREATE TABLE IF NOT EXISTS node_metrics_202505 PARTITION OF node_metrics
			FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
			CREATE TABLE IF NOT EXISTS pod_metrics_202505 PARTITION OF pod_metrics
			FOR VALUES FROM ('2025-05-01') TO ('2025-06-01')
		`)
		require.NoError(t, err)

		// Commit initial setup
		err = tx.Commit(context.Background())
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

	// Insert test cluster for each test
	clusterID, _ := uuid.Parse("10f5a0f9-223a-41c1-8456-9a3eb0323a99")
	_, err = pool.Exec(context.Background(), `
		INSERT INTO clusters (id, name) VALUES ($1, 'test-cluster')
		ON CONFLICT (id) DO NOTHING
	`, clusterID)
	require.NoError(t, err)

	// Return a function to start a new transaction
	newTx := func() pgx.Tx {
		tx, err := pool.Begin(context.Background())
		require.NoError(t, err)
		return tx
	}

	return pool, newTx
}

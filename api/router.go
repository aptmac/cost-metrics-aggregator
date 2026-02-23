package api

import (
	"github.com/aptmac/cost-metrics-aggregator/api/handlers"
	"github.com/aptmac/cost-metrics-aggregator/internal/config"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

func SetupRouter(db *pgxpool.Pool, cfg *config.Config) *gin.Engine {
	r := gin.Default()

	api := r.Group("/api")
	{
		api.POST("/ingress/v1/upload", handlers.UploadHandler(db))
		api.GET("/metrics/v1/nodes", handlers.QueryNodeMetricsHandler(db))
		api.GET("/metrics/v1/pods", handlers.QueryPodMetricsHandler(db))
	}

	return r
}

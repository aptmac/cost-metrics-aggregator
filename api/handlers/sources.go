package handlers

// AI-ASSISTED: Bob/2026-02-24
// This file contains mock implementations of the Sources API endpoints required
// for compatibility with the Cost Management Operator.
//
// /api/sources/v1.0/application [GET & POST]
// /api/sources/v1.0/application_types [GET]
// /api/sources/v1.0/sources [GET & POST]
// /api/sources/v1.0/source_types [GET]
import (
	"net/http"
	"github.com/gin-gonic/gin"
)

func ApplicationsHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"data": []gin.H{},
			"meta": gin.H{
				"count": 0,
			},
		})
	}
}

func ApplicationTypesHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"data": []gin.H{
				{
					"id":           "2",
					"name":         "/insights/platform/cost-management",
					"display_name": "Cost Management",
				},
			},
			"meta": gin.H{
				"count": 1,
			},
		})
	}
}

func SourcesHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Return empty list - operator will create source if needed
		c.JSON(http.StatusOK, gin.H{
			"data": []gin.H{},
			"meta": gin.H{
				"count": 1,
			},
		})
	}
}

func SourceTypesHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"data": []gin.H{
				{
					"id":   "1",
					"name": "openshift",
				},
			},
			"meta": gin.H{
				"count": 1,
			},
		})
	}
}

func CreateApplicationHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		var body map[string]interface{}
		if err := c.BindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		
		c.JSON(http.StatusCreated, gin.H{
			"id":                  "mock-app-id",
			"source_id":           body["source_id"],
			"application_type_id": body["application_type_id"],
		})
	}
}

func CreateSourceHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		var body map[string]interface{}
		if err := c.BindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		
		c.JSON(http.StatusCreated, gin.H{
			"id":             "mock-source-id",
			"name":           body["name"],
			"source_type_id": "1",
			"uid":            body["name"],
		})
	}
}

package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"retail-store/catalog/api"
	"retail-store/catalog/config"
	"retail-store/catalog/controller"
	"retail-store/catalog/middleware"
	"retail-store/catalog/repository"

	"github.com/gin-gonic/gin"
	"github.com/sethvargo/go-envconfig/pkg/envconfig"
	ginprometheus "github.com/zsais/go-gin-prometheus"

	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// @title Catalog API
// @version 1.0
// @description This API serves the product catalog

// @license.name Apache 2.0
// @license.url http://www.apache.org/licenses/LICENSE-2.0.html

// @host localhost:8080
// @BasePath /

func main() {
	configureLogging()
	ctx := context.Background()

	_, otelPresent := os.LookupEnv("OTEL_SERVICE_NAME")

	if otelPresent {
		_, err := initTracer(ctx)
		if err != nil {
			slog.Error("Tracing initialization failed", "error_type", fmt.Sprintf("%T", err))
			os.Exit(1)
		}
	}

	var config config.AppConfiguration
	if err := envconfig.Process(ctx, &config); err != nil {
		slog.Error("Configuration failed", "error_type", fmt.Sprintf("%T", err))
		os.Exit(1)
	}

	db, err := repository.NewRepository(config.Database)
	if err != nil {
		slog.Error("Repository initialization failed", "error_type", fmt.Sprintf("%T", err))
		os.Exit(1)
	}

	api, err := api.NewCatalogAPI(db)
	if err != nil {
		slog.Error("Catalog API initialization failed", "error_type", fmt.Sprintf("%T", err))
		os.Exit(1)
	}

	r := gin.New()
	r.Use(requestLogger(), recoveryLogger())

	p := ginprometheus.NewPrometheus("gin")
	p.Use(r)

	c, err := controller.NewController(api)
	if err != nil {
		slog.Error("Controller initialization failed", "error_type", fmt.Sprintf("%T", err))
		os.Exit(1)
	}

	chaosController := middleware.NewChaosController()

	chaosController.SetupChaosRoutes(r)

	catalog := r.Group("/catalog")

	catalog.Use(chaosController.ChaosMiddleware())
	catalog.Use(otelgin.Middleware("catalog-server"))

	catalog.GET("/products", c.GetProducts)

	catalog.GET("/size", c.CatalogSize)
	catalog.GET("/tags", c.ListTags)
	catalog.GET("/products/:id", c.GetProduct)

	r.GET("/health", func(c *gin.Context) {
		if !chaosController.IsHealthy() {
			c.AbortWithError(503, fmt.Errorf("health check failed"))
			return
		}

		c.String(http.StatusOK, "OK")
	})

	r.GET("/topology", func(c *gin.Context) {
		topology := make(map[string]string)

		topology["persistenceProvider"] = config.Database.Type
		topology["databaseEndpoint"] = "N/A"

		if config.Database.Type != "in-memory" {
			topology["databaseEndpoint"] = config.Database.Endpoint
		}

		c.JSON(http.StatusOK, topology)
	})

	srv := &http.Server{
		Addr:    ":" + strconv.Itoa(config.Port),
		Handler: r,
	}
	slog.Info("Catalog listening", "port", config.Port)

	// Initializing the server in a goroutine so that
	// it won't block the graceful shutdown handling below
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("HTTP server failed", "error_type", fmt.Sprintf("%T", err))
			os.Exit(1)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server with
	// a timeout of 5 seconds.
	quit := make(chan os.Signal, 1)
	// kill (no param) default send syscall.SIGTERM
	// kill -2 is syscall.SIGINT
	// kill -9 is syscall.SIGKILL but can't be catch, so don't need add it
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	slog.Info("Shutting down server")

	// The context is used to inform the server it has 5 seconds to finish
	// the request it is currently handling
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("Server shutdown failed", "error_type", fmt.Sprintf("%T", err))
		os.Exit(1)
	}

	slog.Info("Server exiting")
}

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
	client := otlptracehttp.NewClient()
	exporter, err := otlptrace.New(ctx, client)
	if err != nil {
		return nil, fmt.Errorf("creating OTLP trace exporter: %w", err)
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
	)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))
	otel.SetTracerProvider(tp)
	return tp, nil
}

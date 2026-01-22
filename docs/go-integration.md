# Go Integration Guide

This guide shows how to integrate your Go application with the OpenTelemetry observability stack.

## Prerequisites

- Go 1.20+ application
- OpenTelemetry stack running (`./scripts/start.sh`)

## 1. Install Dependencies

```bash
go get go.opentelemetry.io/otel \
       go.opentelemetry.io/otel/sdk \
       go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc \
       go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc \
       go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc \
       go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp \
       go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc
```

## 2. Create Telemetry Package

Create `internal/telemetry/telemetry.go`:

```go
package telemetry

import (
	"context"
	"log"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
)

// Config holds telemetry configuration
type Config struct {
	ServiceName    string
	ServiceVersion string
	Environment    string
	OTLPEndpoint   string
}

// LoadConfigFromEnv loads configuration from environment variables
func LoadConfigFromEnv() Config {
	return Config{
		ServiceName:    getEnv("SERVICE_NAME", "my-go-service"),
		ServiceVersion: getEnv("SERVICE_VERSION", "1.0.0"),
		Environment:    getEnv("ENVIRONMENT", "development"),
		OTLPEndpoint:   getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "localhost:4317"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// Telemetry holds the initialized providers
type Telemetry struct {
	TracerProvider *trace.TracerProvider
	MeterProvider  *metric.MeterProvider
	Shutdown       func(context.Context) error
}

// Initialize sets up OpenTelemetry with traces, metrics, and logs
func Initialize(ctx context.Context, cfg Config) (*Telemetry, error) {
	// Create resource with service information
	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(cfg.ServiceName),
			semconv.ServiceVersion(cfg.ServiceVersion),
			semconv.DeploymentEnvironment(cfg.Environment),
			attribute.String("service.namespace", "default"),
		),
	)
	if err != nil {
		return nil, err
	}

	// Setup trace exporter
	traceExporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(cfg.OTLPEndpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	// Setup trace provider
	tracerProvider := trace.NewTracerProvider(
		trace.WithBatcher(traceExporter,
			trace.WithBatchTimeout(5*time.Second),
			trace.WithMaxExportBatchSize(512),
		),
		trace.WithResource(res),
		trace.WithSampler(trace.AlwaysSample()), // Change for production
	)

	// Setup metric exporter
	metricExporter, err := otlpmetricgrpc.New(ctx,
		otlpmetricgrpc.WithEndpoint(cfg.OTLPEndpoint),
		otlpmetricgrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	// Setup meter provider
	meterProvider := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExporter,
			metric.WithInterval(10*time.Second),
		)),
		metric.WithResource(res),
	)

	// Set global providers
	otel.SetTracerProvider(tracerProvider)
	otel.SetMeterProvider(meterProvider)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("OpenTelemetry initialized for %s", cfg.ServiceName)

	// Create shutdown function
	shutdown := func(ctx context.Context) error {
		var err error
		if e := tracerProvider.Shutdown(ctx); e != nil {
			err = e
		}
		if e := meterProvider.Shutdown(ctx); e != nil {
			err = e
		}
		return err
	}

	return &Telemetry{
		TracerProvider: tracerProvider,
		MeterProvider:  meterProvider,
		Shutdown:       shutdown,
	}, nil
}
```

## 3. HTTP Server Example

Create `main.go`:

```go
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"

	"myapp/internal/telemetry"
)

var (
	tracer         trace.Tracer
	meter          metric.Meter
	requestCounter metric.Int64Counter
	requestLatency metric.Float64Histogram
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Initialize telemetry
	cfg := telemetry.LoadConfigFromEnv()
	tel, err := telemetry.Initialize(ctx, cfg)
	if err != nil {
		log.Fatalf("Failed to initialize telemetry: %v", err)
	}
	defer tel.Shutdown(ctx)

	// Get tracer and meter
	tracer = otel.Tracer(cfg.ServiceName)
	meter = otel.Meter(cfg.ServiceName)

	// Create metrics
	requestCounter, _ = meter.Int64Counter("http_requests_total",
		metric.WithDescription("Total HTTP requests"),
		metric.WithUnit("1"),
	)
	requestLatency, _ = meter.Float64Histogram("http_request_duration_seconds",
		metric.WithDescription("HTTP request latency"),
		metric.WithUnit("s"),
	)

	// Setup HTTP server with instrumentation
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/users/", getUserHandler)
	mux.HandleFunc("/api/orders", createOrderHandler)

	// Wrap with OpenTelemetry instrumentation
	handler := otelhttp.NewHandler(mux, "server",
		otelhttp.WithMessageEvents(otelhttp.ReadEvents, otelhttp.WriteEvents),
	)

	server := &http.Server{
		Addr:    ":8080",
		Handler: handler,
	}

	// Graceful shutdown
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		log.Println("Shutting down server...")
		shutdownCtx, shutdownCancel := context.WithTimeout(ctx, 10*time.Second)
		defer shutdownCancel()
		server.Shutdown(shutdownCtx)
	}()

	log.Printf("Server starting on :8080")
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func getUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	start := time.Now()

	// Get user ID from path
	userID := r.URL.Path[len("/api/users/"):]

	// Get current span and add attributes
	span := trace.SpanFromContext(ctx)
	span.SetAttributes(attribute.String("user.id", userID))

	log.Printf("Fetching user %s", userID)

	// Create child span for database operation
	ctx, dbSpan := tracer.Start(ctx, "db.getUser",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("db.system", "postgresql"),
			attribute.String("db.operation", "SELECT"),
		),
	)

	// Simulate database call
	time.Sleep(50 * time.Millisecond)
	dbSpan.End()

	// Record metrics
	duration := time.Since(start).Seconds()
	requestCounter.Add(ctx, 1,
		metric.WithAttributes(
			attribute.String("method", r.Method),
			attribute.String("endpoint", "/api/users"),
			attribute.String("status", "200"),
		),
	)
	requestLatency.Record(ctx, duration,
		metric.WithAttributes(
			attribute.String("method", r.Method),
			attribute.String("endpoint", "/api/users"),
		),
	)

	// Return response
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"id":    userID,
		"name":  "John Doe",
		"email": "john@example.com",
	})
}

func createOrderHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	span := trace.SpanFromContext(ctx)

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Decode request
	var orderReq struct {
		UserID string   `json:"user_id"`
		Items  []string `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&orderReq); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "Invalid request body")
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	span.SetAttributes(
		attribute.String("order.user_id", orderReq.UserID),
		attribute.Int("order.items_count", len(orderReq.Items)),
	)

	log.Printf("Creating order for user %s", orderReq.UserID)

	// Process order with nested spans
	ctx, processSpan := tracer.Start(ctx, "processOrder")

	// Validate order
	_, validateSpan := tracer.Start(ctx, "validateOrder")
	time.Sleep(10 * time.Millisecond)
	validateSpan.End()

	// Process payment
	_, paymentSpan := tracer.Start(ctx, "processPayment",
		trace.WithSpanKind(trace.SpanKindClient),
	)
	time.Sleep(100 * time.Millisecond)
	paymentSpan.End()

	// Save to database
	_, saveSpan := tracer.Start(ctx, "saveOrder",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(attribute.String("db.system", "postgresql")),
	)
	time.Sleep(50 * time.Millisecond)
	saveSpan.End()

	processSpan.End()

	// Return response
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"order_id": "12345",
		"status":   "created",
	})
}
```

## 4. Add Custom Spans

```go
package main

import (
	"context"
	"errors"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

var tracer = otel.Tracer("my-service")

// Using context manager pattern
func ProcessItem(ctx context.Context, itemID string) error {
	ctx, span := tracer.Start(ctx, "processItem",
		trace.WithAttributes(attribute.String("item.id", itemID)),
	)
	defer span.End()

	// Add events during processing
	span.AddEvent("Starting validation")
	if err := validate(ctx, itemID); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}

	span.AddEvent("Validation complete")
	span.SetAttributes(attribute.Bool("item.validated", true))

	// Process the item
	result, err := process(ctx, itemID)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}

	span.SetAttributes(attribute.String("item.result", result))
	span.SetStatus(codes.Ok, "")
	return nil
}

// Different span kinds
func CallExternalService(ctx context.Context, url string) error {
	ctx, span := tracer.Start(ctx, "callExternalService",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("http.url", url),
			attribute.String("http.method", "GET"),
		),
	)
	defer span.End()

	// Make HTTP call...
	statusCode := 200
	span.SetAttributes(attribute.Int("http.status_code", statusCode))

	return nil
}

// Internal processing span
func InternalProcess(ctx context.Context) error {
	ctx, span := tracer.Start(ctx, "internalProcess",
		trace.WithSpanKind(trace.SpanKindInternal),
	)
	defer span.End()

	// Processing logic...
	return nil
}

// Producer span (for message queues)
func PublishMessage(ctx context.Context, topic string, message []byte) error {
	ctx, span := tracer.Start(ctx, "publishMessage",
		trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			attribute.String("messaging.system", "kafka"),
			attribute.String("messaging.destination", topic),
		),
	)
	defer span.End()

	// Publish to queue...
	return nil
}

// Consumer span (for message queues)
func ConsumeMessage(ctx context.Context, topic string) error {
	ctx, span := tracer.Start(ctx, "consumeMessage",
		trace.WithSpanKind(trace.SpanKindConsumer),
		trace.WithAttributes(
			attribute.String("messaging.system", "kafka"),
			attribute.String("messaging.destination", topic),
		),
	)
	defer span.End()

	// Process message...
	return nil
}
```

## 5. Add Custom Metrics

```go
package main

import (
	"context"
	"runtime"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

var meter = otel.Meter("my-service")

// Counter - for counting events
var (
	requestsTotal metric.Int64Counter
	errorsTotal   metric.Int64Counter
)

// Histogram - for measuring distributions
var (
	requestDuration metric.Float64Histogram
	requestSize     metric.Int64Histogram
)

// UpDownCounter - for values that go up and down
var activeConnections metric.Int64UpDownCounter

// Gauge - for point-in-time measurements (using observable)
func InitMetrics() error {
	var err error

	// Counter
	requestsTotal, err = meter.Int64Counter("http_requests_total",
		metric.WithDescription("Total number of HTTP requests"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

	errorsTotal, err = meter.Int64Counter("http_errors_total",
		metric.WithDescription("Total number of HTTP errors"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

	// Histogram
	requestDuration, err = meter.Float64Histogram("http_request_duration_seconds",
		metric.WithDescription("HTTP request duration in seconds"),
		metric.WithUnit("s"),
		metric.WithExplicitBucketBoundaries(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
	)
	if err != nil {
		return err
	}

	// UpDownCounter
	activeConnections, err = meter.Int64UpDownCounter("active_connections",
		metric.WithDescription("Number of active connections"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

	// Observable Gauge (async)
	_, err = meter.Int64ObservableGauge("goroutines_count",
		metric.WithDescription("Number of goroutines"),
		metric.WithUnit("1"),
		metric.WithInt64Callback(func(ctx context.Context, o metric.Int64Observer) error {
			o.Observe(int64(runtime.NumGoroutine()))
			return nil
		}),
	)
	if err != nil {
		return err
	}

	// Observable for memory stats
	_, err = meter.Int64ObservableGauge("memory_heap_bytes",
		metric.WithDescription("Heap memory in bytes"),
		metric.WithUnit("By"),
		metric.WithInt64Callback(func(ctx context.Context, o metric.Int64Observer) error {
			var m runtime.MemStats
			runtime.ReadMemStats(&m)
			o.Observe(int64(m.HeapAlloc))
			return nil
		}),
	)

	return err
}

// Usage examples
func RecordRequest(ctx context.Context, method, endpoint, status string, duration time.Duration) {
	attrs := []attribute.KeyValue{
		attribute.String("method", method),
		attribute.String("endpoint", endpoint),
		attribute.String("status", status),
	}

	requestsTotal.Add(ctx, 1, metric.WithAttributes(attrs...))
	requestDuration.Record(ctx, duration.Seconds(), metric.WithAttributes(attrs...))

	if status[0] == '5' { // 5xx errors
		errorsTotal.Add(ctx, 1, metric.WithAttributes(attrs...))
	}
}

func ConnectionOpened(ctx context.Context) {
	activeConnections.Add(ctx, 1)
}

func ConnectionClosed(ctx context.Context) {
	activeConnections.Add(ctx, -1)
}
```

## 6. Context Propagation

```go
package main

import (
	"context"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// Inject context into outgoing HTTP request
func CallDownstreamService(ctx context.Context, url string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	// Inject trace context into headers
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header))

	return http.DefaultClient.Do(req)
}

// Extract context from incoming HTTP request
func ExtractContext(r *http.Request) context.Context {
	return otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
}

// Middleware for automatic extraction
func TracingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := ExtractContext(r)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
```

## 7. Logging with Trace Context

```go
package main

import (
	"context"
	"log/slog"
	"os"

	"go.opentelemetry.io/otel/trace"
)

// Create a logger that includes trace context
type TraceHandler struct {
	slog.Handler
}

func (h *TraceHandler) Handle(ctx context.Context, r slog.Record) error {
	span := trace.SpanFromContext(ctx)
	if span.SpanContext().IsValid() {
		r.AddAttrs(
			slog.String("trace_id", span.SpanContext().TraceID().String()),
			slog.String("span_id", span.SpanContext().SpanID().String()),
		)
	}
	return h.Handler.Handle(ctx, r)
}

func NewLogger() *slog.Logger {
	handler := &TraceHandler{
		Handler: slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
			Level: slog.LevelInfo,
		}),
	}
	return slog.New(handler)
}

// Usage
func ExampleUsage(ctx context.Context) {
	logger := NewLogger()

	logger.InfoContext(ctx, "Processing request",
		slog.String("user_id", "123"),
		slog.String("action", "create_order"),
	)

	// This will output JSON with trace_id and span_id automatically included
}
```

## 8. gRPC Integration

```go
package main

import (
	"context"
	"log"
	"net"

	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"google.golang.org/grpc"
)

// Server setup
func StartGRPCServer() {
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	server := grpc.NewServer(
		grpc.StatsHandler(otelgrpc.NewServerHandler()),
	)

	// Register your services...

	if err := server.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}

// Client setup
func CreateGRPCClient(addr string) (*grpc.ClientConn, error) {
	return grpc.Dial(addr,
		grpc.WithInsecure(),
		grpc.WithStatsHandler(otelgrpc.NewClientHandler()),
	)
}
```

## 9. Environment Variables

```bash
# OpenTelemetry Configuration
OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4317
SERVICE_NAME=my-go-service
SERVICE_VERSION=1.0.0
ENVIRONMENT=development

# Optional: Sampling
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

## 10. Docker Compose Integration

```yaml
services:
  my-go-app:
    build: .
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=otel-collector:4317
      - SERVICE_NAME=my-go-service
      - ENVIRONMENT=production
    networks:
      - observability

networks:
  observability:
    external: true
    name: observability
```

## 11. Complete Example Module Structure

```
myapp/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── telemetry/
│   │   └── telemetry.go
│   ├── handlers/
│   │   └── handlers.go
│   └── middleware/
│       └── middleware.go
├── go.mod
├── go.sum
└── Dockerfile
```

## Viewing Your Data

- **Traces**: http://localhost:16686 (Jaeger)
- **Metrics**: http://localhost:3000 (Grafana)
- **Logs**: http://localhost:3000 (Grafana → Explore → Loki)

## Troubleshooting

### Traces not appearing
1. Verify OTel stack is running: `./scripts/status.sh`
2. Check endpoint (should be `host:port` without protocol for gRPC)
3. Ensure `defer span.End()` is called for all spans

### High memory usage
- Enable sampling for high-traffic services
- Reduce batch sizes in exporter configuration
- Monitor goroutine count

### Context not propagating
- Use `context.Context` throughout your application
- Ensure `otel.SetTextMapPropagator()` is called during initialization
- Use `otelhttp` wrapper for HTTP clients

# .NET Integration Guide

This guide shows how to integrate your .NET application with the OpenTelemetry observability stack.

## Prerequisites

- .NET 6.0+ application
- OpenTelemetry stack running (`./scripts/start.sh --seq`)

## 1. Install NuGet Packages

```bash
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Instrumentation.Http
dotnet add package OpenTelemetry.Instrumentation.SqlClient
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
dotnet add package Serilog.Sinks.Seq
```

## 2. Configure OpenTelemetry in Program.cs

```csharp
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;

var builder = WebApplication.CreateBuilder(args);

// Define service resource
var serviceName = "MyService";
var serviceVersion = "1.0.0";

// Configure OpenTelemetry
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: serviceName, serviceVersion: serviceVersion)
        .AddAttributes(new[]
        {
            new KeyValuePair<string, object>("deployment.environment", 
                builder.Environment.EnvironmentName)
        }))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(opts =>
        {
            opts.RecordException = true;
            opts.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/health");
        })
        .AddHttpClientInstrumentation()
        .AddSqlClientInstrumentation(opts => opts.SetDbStatementForText = true)
        .AddOtlpExporter(opts =>
        {
            opts.Endpoint = new Uri("http://localhost:4317");
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddProcessInstrumentation()
        .AddOtlpExporter(opts =>
        {
            opts.Endpoint = new Uri("http://localhost:4317");
        }));
```

## 3. Configure Serilog for Seq

```csharp
// In Program.cs
using Serilog;

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Application", serviceName)
    .WriteTo.Console()
    .WriteTo.Seq("http://localhost:5341")
    .CreateLogger();

builder.Host.UseSerilog();
```

## 4. Add Custom Spans

```csharp
using System.Diagnostics;

public class MyService
{
    private static readonly ActivitySource ActivitySource = new("MyService");
    
    public async Task DoWorkAsync()
    {
        using var activity = ActivitySource.StartActivity("DoWork");
        activity?.SetTag("custom.tag", "value");
        
        // Your code here
        
        activity?.SetStatus(ActivityStatusCode.Ok);
    }
}
```

## 5. Add Custom Metrics

```csharp
using System.Diagnostics.Metrics;

public class MyService
{
    private static readonly Meter Meter = new("MyService");
    private static readonly Counter<int> RequestCounter = Meter.CreateCounter<int>("requests_total");
    private static readonly Histogram<double> RequestDuration = Meter.CreateHistogram<double>("request_duration_ms");
    
    public async Task ProcessRequest()
    {
        RequestCounter.Add(1, new("endpoint", "/api/data"));
        
        var sw = Stopwatch.StartNew();
        // Process request
        sw.Stop();
        
        RequestDuration.Record(sw.ElapsedMilliseconds);
    }
}
```

## 6. Environment Variables

Set these in your `appsettings.json` or environment:

```json
{
  "OpenTelemetry": {
    "Endpoint": "http://localhost:4317",
    "ServiceName": "MyService"
  },
  "Serilog": {
    "SeqServerUrl": "http://localhost:5341"
  }
}
```

## 7. Docker Compose Integration

If your app runs in Docker, use the network:

```yaml
services:
  my-app:
    image: my-app:latest
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
      - SEQ_SERVER_URL=http://otel-seq:5341
    networks:
      - observability

networks:
  observability:
    external: true
    name: observability
```

## Viewing Your Data

- **Traces**: http://localhost:16686 (Jaeger)
- **Metrics**: http://localhost:3000 (Grafana)
- **Logs**: http://localhost:5380 (Seq)

# Building a Scalable Observability Platform Without Breaking the Bank

**A Practical Guide for Teams Who Need Enterprise-Grade Observability on a Real-World Budget**

---

## The Story Behind This Document

If you're reading this, chances are you've been in one of these situations:

You're debugging a production incident at 2 AM. A customer reports that their checkout is failing. You check the logs—nothing obvious. You look at metrics—CPU and memory seem fine. You try to trace the request through your microservices, but the data is incomplete, scattered across different tools, and nothing correlates. Two hours later, you finally discover that a downstream payment service was timing out, but only for certain customers, and only when their cart had more than ten items.

Or maybe you've had the budget conversation. Your team finally gets approval for a proper observability solution. You evaluate Datadog, New Relic, Splunk—they're fantastic tools. Then you see the quote. For your 50-service architecture processing 20,000 events per second, you're looking at $20,000 to $40,000 per month. That's $240,000 to $480,000 per year—just to understand what your own software is doing.

This guide exists because we believe there's a better way. Not better than the commercial tools in terms of features—they're genuinely excellent—but better for organizations where that kind of budget simply isn't realistic, or where spending that much on observability means sacrificing other critical investments.

What follows is a battle-tested architecture for building a self-hosted observability platform using open-source software. It's the same architecture we've used to achieve 97% cost savings while maintaining the visibility we need to run reliable production systems.

---

## Who This Document Is For

This guide is written for **senior developers, platform engineers, and architects** who:

- Need comprehensive observability (traces, metrics, logs) but can't justify six-figure annual licensing costs
- Want to understand not just *what* to build, but *why* each component exists and how they work together
- Value data ownership and want telemetry to stay within their infrastructure
- Are comfortable with infrastructure-as-code and can dedicate some engineering time to setup and maintenance

If you're looking for a fully-managed, zero-maintenance solution and budget isn't a constraint, this probably isn't for you. But if you're willing to invest some engineering effort in exchange for dramatically lower costs and complete control over your observability data, read on.

---

## Document Structure

This document is organized as a journey from understanding the problem to designing a solution:

| Part | What You'll Learn |
|------|-------------------|
| **Part I: The Foundation** | Why observability matters, what the three pillars actually mean in practice, and why we chose OpenTelemetry |
| **Part II: Where We Start** | Understanding the single-node architecture, its capabilities, and honest assessment of its limitations |
| **Part III: The Scalable Architecture** | The multi-tier design that handles high volume, provides high availability, and grows with your needs |
| **Part IV: Making Decisions** | Technology choices, trade-offs we've accepted, and how to think about costs |

When you're ready to actually build this, head to the [Implementation Guide](./implementation-guide.md) for step-by-step instructions.

---

# Part I: The Foundation

## Why Observability Actually Matters

Let's start with a scenario that's probably familiar.

Your e-commerce platform handles a flash sale. Traffic spikes 10x. Orders start failing. The on-call engineer sees elevated error rates but can't pinpoint the cause. Is it the database? The payment gateway? A network issue? A code bug that only manifests under load?

Without proper observability, debugging this is like trying to diagnose a car problem by only looking at the "check engine" light. You know something's wrong, but you have no idea what.

**Observability is the ability to understand what's happening inside your system by examining what it outputs.** It's not just monitoring (is it up or down?), and it's not just logging (what events occurred?). It's the capability to ask arbitrary questions about your system's behavior and get meaningful answers—even questions you didn't anticipate when you built it.

The three outputs that make this possible are **traces**, **metrics**, and **logs**. Each tells you something different, and the magic happens when you can correlate all three.

### The Three Pillars: A Practical Explanation

Let me explain each pillar not in abstract terms, but in terms of the questions they help you answer.

#### Traces: Following a Request's Journey

Imagine you're a detective following a suspect through a city. A trace is like a complete record of everywhere they went, how long they spent at each location, and what they did there.

In software terms, a trace follows a single request as it travels through your distributed system. When a user clicks "Place Order," that request might touch your API gateway, authentication service, inventory service, payment processor, order service, notification system, and database—all before returning a response.

A trace captures this entire journey:

```
User Request: Place Order (trace_id: abc123)
│
├── API Gateway (total: 850ms)
│   ├── Request validation (15ms)
│   └── Route to order service
│       │
│       └── Order Service (450ms)
│           ├── Validate cart (25ms)
│           ├── Check inventory (180ms) ← Why so slow?
│           │   └── Database query (175ms) ← Found it!
│           ├── Process payment (200ms)
│           │   └── External API call (195ms)
│           └── Send confirmation (40ms)
│
└── Total response time: 850ms
```

With this trace, you can immediately see that the 850ms response time is primarily caused by a slow inventory database query (175ms) and the external payment API (195ms). Without tracing, you'd be guessing.

**When traces shine:**
- "Why did this specific request take so long?"
- "Where in my system did this error originate?"
- "What's the actual call path between my services?"
- "Which downstream service is causing my latency?"

#### Metrics: Understanding System Behavior Over Time

If traces are for investigating individual requests, metrics are for understanding patterns and trends across millions of requests.

Metrics are numerical measurements collected at regular intervals. They're highly compressed (a number rather than a log line), which makes them efficient to store and fast to query, even over long time periods.

Think of metrics like your car's dashboard. You don't need to know everything happening inside the engine, but you do need to know the speed, fuel level, and engine temperature. These numbers give you a continuous picture of system health.

```
Example metrics for an API service:

http_requests_total{service="order-api", status="200"}: 1,234,567
http_requests_total{service="order-api", status="500"}: 234
http_request_duration_seconds_p99{service="order-api"}: 0.45
active_database_connections{pool="primary"}: 42
order_processing_queue_depth: 127
```

From these five numbers, you can understand:
- How much traffic you're serving (1.2M successful requests)
- Your error rate (234/1,234,801 ≈ 0.02%)
- Your worst-case latency (99th percentile at 450ms)
- Database connection pool utilization (42 connections in use)
- Whether you're keeping up with orders (127 in queue)

**When metrics shine:**
- "What's our error rate trending over the past week?"
- "Are we approaching capacity limits?"
- "How does today's latency compare to yesterday?"
- "Should I wake someone up?" (alerting)

#### Logs: The Detailed Record

Logs are the narrative of your system—discrete events that describe what happened at specific moments. They're the most familiar observability signal because developers have been writing print statements since the beginning of programming.

But there's a crucial distinction between logs that help you debug and logs that just fill up your disk.

**Unhelpful log:**
```
2024-01-15 10:23:45 ERROR Payment failed
```

This tells you almost nothing. Which payment? Which user? Why did it fail? What was the request context?

**Helpful log:**
```json
{
  "timestamp": "2024-01-15T10:23:45.123Z",
  "level": "error",
  "service": "payment-service",
  "message": "Payment processing failed",
  "trace_id": "abc123def456",
  "user_id": "user_789",
  "order_id": "order_456",
  "payment_amount": 99.99,
  "payment_provider": "stripe",
  "error_code": "card_declined",
  "error_message": "Your card was declined.",
  "request_id": "req_xyz"
}
```

Now you can:
- Find this log entry quickly using any of these fields
- Jump to the related trace using `trace_id`
- See exactly what went wrong (`card_declined`)
- Correlate with other events for the same user or order

**When logs shine:**
- "What exactly happened when this error occurred?"
- "What did the user do before the failure?"
- "Are there audit requirements I need to satisfy?"
- "What was the full error message and stack trace?"

### The Real Power: Correlation

Here's where it gets interesting. Each pillar is useful on its own, but the real power comes from combining them.

Picture this debugging flow:

```
┌───────────────────────────────────────────────────────────────────────┐
│  1. ALERT FIRES                                                       │
│     "Error rate > 1% for order-service"                               │
│     (Metric told us something is wrong)                               │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│  2. INVESTIGATE METRICS                                               │
│     Error rate spiked at 10:15 AM                                     │
│     Latency also increased                                            │
│     Database connection pool at 100%                                  │
│     (Metrics narrow down the time and potential cause)                │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│  3. SEARCH LOGS                                                       │
│     Filter: service=order-service, level=error, time=10:15-10:20      │
│     Found: "Connection pool exhausted, cannot acquire connection"     │
│     Found: "Timeout waiting for database connection"                  │
│     (Logs tell us what errors occurred)                               │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│  4. EXAMINE TRACES                                                    │
│     Click trace_id from error log                                     │
│     See: inventory-service making 50 DB queries per request           │
│     See: Each query holding connection for 2+ seconds                 │
│     (Trace shows us WHY the pool was exhausted)                       │
└───────────────────────────────────┬───────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│  5. ROOT CAUSE                                                        │
│     A recent deployment introduced an N+1 query bug in inventory      │
│     Under high load, this exhausted the connection pool               │
│     (Now we know exactly what to fix)                                 │
└───────────────────────────────────────────────────────────────────────┘
```

This investigation took 10 minutes with proper observability. Without it? Could easily be hours of guessing, adding debug logging, redeploying, and hoping you get lucky.

---

## Why OpenTelemetry is the Right Foundation

When we started building this platform, we had to make a fundamental choice: what instrumentation standard should we use?

We could have gone with vendor-specific SDKs (Datadog's libraries, New Relic's agents), but that would create lock-in. We could have used multiple specialized tools (Jaeger for traces, Prometheus client for metrics, Fluentd for logs), but that meant maintaining multiple instrumentation systems.

We chose **OpenTelemetry** because it solves both problems.

### What OpenTelemetry Actually Is

OpenTelemetry is three things:

1. **A specification** that defines how telemetry data should be structured
2. **SDKs for every major language** that implement this specification
3. **The OpenTelemetry Collector**, a vendor-agnostic data pipeline

The key insight is separation of concerns. Your application code instruments itself using the OpenTelemetry SDK, speaking a standard protocol (OTLP). Where that data goes—Jaeger, Datadog, Honeycomb, your own backends—is a deployment-time decision, not a code-time decision.

```
┌───────────────────────────────────────────────────────────────────────┐
│                         YOUR APPLICATION CODE                         │
│    ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│    │  Go SDK  │  │ Java SDK │  │ .NET SDK │  │  Python  │  ...        │
│    └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘             │
│         │             │             │             │                   │
│         └─────────────┴──────┬──────┴─────────────┘                   │
│                              │                                        │
│                        OTLP Protocol                                  │
│                       (Open Standard)                                 │
└──────────────────────────────┬────────────────────────────────────────┘
                               │
                               ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      OPENTELEMETRY COLLECTOR                          │
│              Receive → Process → Export (your choice)                 │
└──────────────────────────────┬────────────────────────────────────────┘
                               │
             ┌─────────────────┼─────────────────┐
             │                 │                 │
             ▼                 ▼                 ▼
        ┌─────────┐       ┌─────────┐       ┌─────────┐
        │ Jaeger  │       │  Your   │       │ Datadog │
        │ (Self-  │       │ Backend │       │ (If you │
        │ hosted) │       │  Here   │       │  want)  │
        └─────────┘       └─────────┘       └─────────┘
```

### Why This Matters for Your Team

**No vendor lock-in.** If you start with self-hosted backends and later decide you want a managed service, you change your Collector configuration—not your application code. Your investment in instrumentation is protected.

**One SDK to learn.** Instead of teaching your team Jaeger's SDK for traces, Prometheus client for metrics, and some logging framework for logs, everyone learns OpenTelemetry. One set of concepts, one set of APIs.

**Industry momentum.** OpenTelemetry is a CNCF project with contributions from Google, Microsoft, Amazon, Splunk, Datadog, and most other major players. It's rapidly becoming the standard way to instrument applications. Learning it now is a career investment.

**Rich ecosystem.** Auto-instrumentation libraries exist for most common frameworks. In many cases, you can add observability to an existing application with minimal code changes.

### The OpenTelemetry Collector: Your Swiss Army Knife

The Collector deserves special attention because it's the component that gives you flexibility. It's a standalone service that can receive telemetry from anywhere, transform it however you need, and send it wherever you want.

Think of it as a universal adapter for observability data:

**Receive from anything:**
- OTLP (native OpenTelemetry protocol)
- Jaeger format (for existing Jaeger instrumentation)
- Zipkin format
- Prometheus scrape targets
- Syslog
- AWS CloudWatch
- ...dozens more

**Process however you need:**
- Filter out noisy or low-value telemetry
- Sample traces intelligently (keep errors, sample successes)
- Add metadata (Kubernetes labels, deployment info)
- Transform attribute names for consistency
- Batch data for efficient export
- Redact sensitive information

**Export to anywhere:**
- Your self-hosted backends (Jaeger, Prometheus, Loki)
- Commercial services (Datadog, New Relic, Honeycomb)
- Cloud-native services (AWS X-Ray, Google Cloud Trace)
- Multiple destinations simultaneously

This flexibility is why the Collector is the heart of our architecture. Applications talk to the Collector, and the Collector handles everything else.

---

# Part II: Starting Point and Limitations

*Now that we understand what we're building and why, let's look at where most teams should actually start—and when that starting point stops being enough.*

## The Single-Node Architecture

Let's be honest about where most teams should start: a single-node deployment running everything in Docker Compose.

This isn't a compromise or a "demo" setup—it's a legitimate production architecture for many use cases. Understanding what it can and can't do will help you make informed decisions about when to scale.

### What You Get

```
┌───────────────────────────────────────────────────────────────────────┐
│                            SINGLE SERVER                              │
│                     (Your $100-200/month VM)                          │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                     Docker Compose Stack                        │  │
│  │                                                                 │  │
│  │    ┌─────────────────────────────────────────────────────────┐  │  │
│  │    │               OpenTelemetry Collector                   │  │  │
│  │    │  ┌───────────────────────────────────────────────────┐  │  │  │
│  │    │  │  • Receives OTLP from your applications           │  │  │  │
│  │    │  │  • Queues data to disk (survives restarts)        │  │  │  │
│  │    │  │  • Routes to appropriate backends                 │  │  │  │
│  │    │  └───────────────────────────────────────────────────┘  │  │  │
│  │    └─────────────────────────────────────────────────────────┘  │  │
│  │                              │                                  │  │
│  │            ┌─────────────────┼─────────────────┐                │  │
│  │            │                 │                 │                │  │
│  │            ▼                 ▼                 ▼                │  │
│  │    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐          │  │
│  │    │   Jaeger    │   │ Prometheus  │   │    Loki     │          │  │
│  │    │  (Traces)   │   │  (Metrics)  │   │   (Logs)    │          │  │
│  │    │             │   │             │   │             │          │  │
│  │    │ ~50K spans/ │   │  ~1M active │   │ ~50K lines/ │          │  │
│  │    │   second    │   │   series    │   │   second    │          │  │
│  │    └─────────────┘   └─────────────┘   └─────────────┘          │  │
│  │            │                 │                 │                │  │
│  │            └─────────────────┼─────────────────┘                │  │
│  │                              │                                  │  │
│  │                              ▼                                  │  │
│  │                      ┌─────────────┐                            │  │
│  │                      │   Grafana   │                            │  │
│  │                      │ Dashboards  │                            │  │
│  │                      │  Alerting   │                            │  │
│  │                      └─────────────┘                            │  │
│  │                                                                 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

With this setup, running on a single 8-CPU, 16GB RAM server, you can:

- **Ingest approximately 50,000 events per second** across traces, metrics, and logs
- **Store 30 days of data** with reasonable retention policies
- **Query dashboards with sub-second response times** for typical time windows
- **Alert on any metric or log pattern** with Grafana's built-in alerting
- **Survive service restarts** without losing data (persistent queues)
- **Auto-recover from failures** (Docker restart policies)

For a team of 5-20 developers running 10-50 microservices, this is often more than enough.

### What's Already Production-Ready

I want to emphasize that the single-node setup isn't a toy. It includes:

**Persistent queues**: The OpenTelemetry Collector writes data to disk before attempting to export it. If Jaeger is temporarily down, data queues up and gets delivered when it recovers. This isn't just "buffering"—it survives collector restarts.

**Resource limits**: Each container has CPU and memory limits. This prevents one component from starving others and makes behavior predictable under load.

**Health checks**: Every service exposes a health endpoint. Docker monitors these and automatically restarts unhealthy containers.

**Graceful shutdown**: When you deploy updates, services have 30 seconds to drain in-flight data before stopping. Combined with persistent queues, this means zero data loss during deployments.

### Being Honest About Limitations

Here's where I need to be direct about what this architecture can't do:

**Single point of failure.** If the server goes down—hardware failure, network issue, cloud provider problem—you have zero observability until it's back. For many teams, brief observability gaps are acceptable. For teams with strict SLAs, they're not.

**Vertical scaling only.** When you hit capacity limits, your only option is a bigger server. At some point, bigger servers don't exist or aren't cost-effective.

**Shared resources.** A heavy Prometheus query can affect Jaeger write performance. A log ingestion spike can slow down everything. Components compete for CPU, memory, and disk I/O.

**No geographic distribution.** If your applications run in multiple regions, telemetry from distant regions has higher latency. You can't have region-local observability.

### When Single-Node Is the Right Choice

Stay with single-node if:

- Your sustained throughput is comfortably under 50,000 events per second
- Your uptime SLA allows for occasional brief outages (99% uptime = 3.6 days/year)
- Your team is small and prefers operational simplicity
- Your applications are in a single region
- Observability is important but not mission-critical

### When You Need to Scale

Consider scaling when:

- You're consistently hitting 50,000+ events per second
- You need 99.9%+ uptime for observability itself
- You're running multi-region and need low-latency telemetry collection everywhere
- Compliance requirements mandate no data loss
- Query performance is suffering during peak load

---

# Part III: The Scalable Architecture

## The Design Philosophy

Before diving into components, let me explain the principles that guide this architecture. These aren't arbitrary choices—they're lessons learned from running observability at scale.

### Principle 1: Decouple Ingestion from Processing

In the single-node setup, the Collector directly exports to backends. If a backend is slow or down, the Collector slows down or queues up. Under high load, this coupling becomes a problem.

The scalable architecture introduces a message queue (Kafka) between ingestion and processing. Collectors can accept data at full speed regardless of backend health. Data is durably stored in Kafka until processors are ready for it.

Think of it like a warehouse between a factory and retail stores. The factory doesn't slow down just because one store is restocking. The warehouse absorbs the variation.

### Principle 2: Scale Components Independently

Different bottlenecks require different solutions. If you're CPU-bound on processing, add more processors. If you're network-bound on ingestion, add more gateways. If you're storage-bound, add object storage capacity.

The architecture separates concerns so each component can scale based on its own constraints.

### Principle 3: Accept Graceful Degradation

Total system failure should be extraordinarily rare. Partial degradation—slower queries, some data sampling, delayed processing—is an acceptable trade-off for resilience.

When a component fails, others continue working. When you're overloaded, you shed load intelligently (sampling) rather than failing completely.

### Principle 4: Optimize for the Common Case

Most telemetry isn't interesting. Most traces are successful requests. Most logs are routine. Most metrics are within normal ranges.

The architecture optimizes for high-volume, low-value data (sampling, compression, cheap storage) while ensuring high-value data (errors, anomalies, slow requests) is always preserved.

## The Architecture at a Glance

Before we dive into details, here's the big picture in one sentence:

> **Applications send telemetry to gateway collectors, which buffer it in Kafka, where processor collectors consume it, apply sampling and enrichment, and write to specialized storage backends that Grafana queries for visualization.**

That's the whole thing. If you understand that sentence, you understand the architecture. Everything else is details about how to make each piece reliable and scalable.

Here's a simplified view:

```
Applications → Gateways → Kafka → Processors → Storage → Grafana
                 ↑                    ↑           ↑
              (scale)             (sample)    (cheap S3)
```

Now let's unpack each layer.

## The Five-Layer Architecture

Here's the complete picture:

```
                               YOUR APPLICATIONS
                     (Instrumented with OpenTelemetry SDKs)
                                     │
                                     │ OTLP Protocol
                                     ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                       LAYER 1: INGESTION                          │
    │                                                                   │
    │                    ┌─────────────────┐                            │
    │                    │  Load Balancer  │  HAProxy, NGINX, or cloud  │
    │                    │   (Port 4317)   │  LB, Health-aware routing  │
    │                    └────────┬────────┘                            │
    │                             │                                     │
    │          ┌──────────────────┼──────────────────┐                  │
    │          │         │        │        │         │                  │
    │          ▼         ▼        ▼        ▼         ▼                  │
    │       ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                │
    │       │ GW 1 │ │ GW 2 │ │ GW 3 │ │ ...  │ │ GW N │                │
    │       │      │ │      │ │      │ │      │ │      │                │
    │       └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘                │
    │          │        │        │        │        │                    │
    │          │        │        │        │        │  OTel Collector    │
    │          │        │        │        │        │  (Gateway mode)    │
    │          │        │        │        │        │  Stateless, fast   │
    └──────────┼────────┼────────┼────────┼────────┼────────────────────┘
               │        │        │        │        │
               └────────┴────────┼────────┴────────┘
                                 │
                                 ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                       LAYER 2: BUFFERING                          │
    │                                                                   │
    │                ┌────────────────────────────┐                     │
    │                │        Apache Kafka        │                     │
    │                │                            │                     │
    │                │  Topics:                   │                     │
    │                │  • otlp-traces   (12 part) │                     │
    │                │  • otlp-metrics  (12 part) │                     │
    │                │  • otlp-logs     (12 part) │                     │
    │                │                            │                     │
    │                │  Replicated, durable       │                     │
    │                │  24-hour retention         │                     │
    │                └────────────────────────────┘                     │
    │                                                                   │
    │    Why Kafka?                                                     │
    │    • Decouples ingestion from processing                          │
    │    • Survives backend outages (data stays in Kafka)               │
    │    • Enables replay if you need to reprocess                      │
    │    • Horizontal scaling via partitions                            │
    └─────────────────────────────┬─────────────────────────────────────┘
                                  │
                                  ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                       LAYER 3: PROCESSING                         │
    │                                                                   │
    │          ┌──────────────────┼──────────────────┐                  │
    │          │         │        │        │         │                  │
    │          ▼         ▼        ▼        ▼         ▼                  │
    │       ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                │
    │       │ P1   │ │ P2   │ │ P3   │ │ ...  │ │ PN   │                │
    │       │      │ │      │ │      │ │      │ │      │                │
    │       │ ┌──┐ │ │ ┌──┐ │ │ ┌──┐ │ │      │ │ ┌──┐ │                │
    │       │ │ T│ │ │ │ T│ │ │ │ T│ │ │      │ │ │ T│ │                │
    │       │ │ M│ │ │ │ M│ │ │ │ M│ │ │      │ │ │ M│ │                │
    │       │ │ L│ │ │ │ L│ │ │ │ L│ │ │      │ │ │ L│ │                │
    │       │ └──┘ │ │ └──┘ │ │ └──┘ │ │      │ │ └──┘ │                │
    │       └──────┘ └──────┘ └──────┘ └──────┘ └──────┘                │
    │                                                                   │
    │    OTel Collector (Processor mode)                                │
    │    Each processor handles:                                        │
    │    • Sampling (keep all errors, sample 10% success)               │
    │    • Filtering (drop health checks, internal noise)               │
    │    • Enrichment (add K8s labels, environment info)                │
    │    • Batching (efficient writes to backends)                      │
    └─────────────────────────────┬─────────────────────────────────────┘
                                  │
                                  ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                        LAYER 4: STORAGE                           │
    │                                                                   │
    │       ┌─────────────┐   ┌─────────────┐   ┌─────────────┐         │
    │       │   Tempo     │   │   Mimir     │   │    Loki     │         │
    │       │  (Traces)   │   │  (Metrics)  │   │   (Logs)    │         │
    │       │             │   │             │   │             │         │
    │       │  TraceQL    │   │  PromQL     │   │  LogQL      │         │
    │       │  queries    │   │  queries    │   │  queries    │         │
    │       └──────┬──────┘   └──────┬──────┘   └──────┬──────┘         │
    │              │                 │                 │                │
    │              └─────────────────┼─────────────────┘                │
    │                                │                                  │
    │                                ▼                                  │
    │                ┌────────────────────────────┐                     │
    │                │      Object Storage        │                     │
    │                │     (S3 / MinIO / GCS)     │                     │
    │                │                            │                     │
    │                │  • Hot data in local SSD   │                     │
    │                │  • Cold data in S3 (cheap) │                     │
    │                │  • Unlimited retention     │                     │
    │                └────────────────────────────┘                     │
    └─────────────────────────────┬─────────────────────────────────────┘
                                  │
                                  ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                     LAYER 5: VISUALIZATION                        │
    │                                                                   │
    │                ┌────────────────────────────┐                     │
    │                │         Grafana            │                     │
    │                │    (Multiple instances)    │                     │
    │                │                            │                     │
    │                │  • Unified dashboards      │                     │
    │                │  • Trace exploration       │                     │
    │                │  • Log search              │                     │
    │                │  • Alerting                │                     │
    │                └────────────────────────────┘                     │
    │                                │                                  │
    │                                ▼                                  │
    │                ┌────────────────────────────┐                     │
    │                │        PostgreSQL          │                     │
    │                │    (Shared state for HA)   │                     │
    │                │                            │                     │
    │                │  Dashboards, users,        │                     │
    │                │  alerts stored here        │                     │
    │                └────────────────────────────┘                     │
    └───────────────────────────────────────────────────────────────────┘
```

### Layer 1: Ingestion — The Front Door

The ingestion layer is deliberately simple. Its job is to accept telemetry as fast as possible and get it into Kafka reliably.

**Gateway Collectors** are OpenTelemetry Collectors configured in "gateway mode." They:
- Accept OTLP over gRPC (port 4317) and HTTP (port 4318)
- Perform minimal validation (is this valid OTLP?)
- Batch data for efficient Kafka writes
- Publish to appropriate Kafka topics

Gateway collectors are stateless—they hold no data beyond what's in-flight. This makes them easy to scale: just add more instances behind the load balancer.

**The Load Balancer** distributes traffic across healthy gateways. It monitors gateway health and stops sending traffic to unhealthy instances. This is where you get your ingestion high availability.

For most deployments, HAProxy or NGINX works well. In Kubernetes, you can use a Service with multiple pod replicas. In cloud environments, you might use an ALB or NLB.

**Scaling this layer:** If gateways are CPU-bound or network-bound, add more gateway instances. The load balancer automatically distributes traffic.

### Layer 2: Buffering — The Shock Absorber

This is arguably the most important layer for reliability. Kafka acts as a buffer between your high-speed ingestion layer and your (potentially slower or temporarily unavailable) processing layer.

**Why Kafka specifically?**

We evaluated several options:

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Redis Streams** | Simple, low latency | Limited durability, memory-bound | Good for small scale |
| **RabbitMQ** | Feature-rich, easy to use | Not designed for this throughput | Not suitable |
| **Apache Pulsar** | Modern, cloud-native | Smaller community, more complex | Viable alternative |
| **Apache Kafka** | Proven at massive scale, excellent durability | Operational complexity | Our choice |

Kafka wins because:
1. **Durability**: Data is written to disk and replicated across brokers. Losing a broker doesn't lose data.
2. **Throughput**: A modest Kafka cluster handles millions of messages per second.
3. **Replay**: Consumer groups track position independently. You can reprocess historical data.
4. **Ecosystem**: Well-understood, widely deployed, lots of operational knowledge available.

**Topic design:**

We use three topics, one per signal type:
- `otlp-traces` — Trace data (spans)
- `otlp-metrics` — Metric data (counters, gauges, histograms)
- `otlp-logs` — Log data

Each topic has multiple partitions (12 is a good starting point) for parallel processing. Messages within a partition are ordered, but there's no ordering guarantee across partitions.

**Retention:** We typically configure 24-hour retention. This means you have 24 hours to recover from downstream problems before data is dropped. In practice, processing catches up within minutes, so this is very conservative.

**Sizing guidance:**
- 3 brokers handles ~100K events/sec comfortably
- Add brokers and partitions to scale horizontally
- Kafka's storage is cheap—don't be afraid of retention

### Layer 3: Processing — The Smart Filter

The processing layer is where intelligence happens. Processor collectors consume from Kafka, apply transformations, and export to storage backends.

**Key processing functions:**

**Tail-based sampling for traces:** This is crucial for cost control. Instead of keeping every trace, we keep:
- All traces that contain an error
- All traces that exceed a latency threshold (e.g., > 1 second)
- A random 10% sample of remaining traces

This reduces trace storage by 80-90% while preserving all the traces you'd actually investigate.

```
Example sampling policy:

Input: 100,000 traces
├── 500 contain errors → Keep all 500 (0.5%)
├── 2,000 are slow (>1s) → Keep all 2,000 (2%)
└── 97,500 are normal, fast traces → Keep ~9,750 (10% sample)

Output: ~12,250 traces (87.75% reduction)

What you lose: Random successful, fast traces (which you'd never look at anyway)
What you keep: Everything you'd actually investigate
```

**Attribute enrichment:** Processors add context that's useful for querying:
- Kubernetes metadata (namespace, deployment, pod name)
- Environment labels (production, staging)
- Service version information

**Filtering:** Remove telemetry that's noise:
- Health check endpoints (high volume, low value)
- Internal infrastructure requests
- Debug logging in production

**Sensitive data handling:** Remove or hash PII before it reaches storage:
- Credit card numbers in logs
- Email addresses in span attributes
- API keys in HTTP headers

**Scaling this layer:** Kafka consumer groups automatically rebalance partitions across processors. Add more processor instances, and Kafka distributes the load.

### Layer 4: Storage — The Long-Term Memory

Each telemetry signal has different access patterns, so we use different storage systems optimized for each.

**Tempo for Traces**

Tempo is Grafana's distributed tracing backend. We chose it over Jaeger for the scalable architecture because:

- **Object storage native**: Tempo stores trace data directly in S3/MinIO. No need to manage Cassandra or Elasticsearch clusters.
- **Cost efficient**: Object storage is dramatically cheaper than database storage.
- **Simple operations**: Far fewer components to manage than Jaeger with Cassandra.
- **TraceQL**: Powerful query language for finding traces by attributes.

Tempo works by writing incoming traces to a local disk temporarily, then flushing completed blocks to object storage. Queries check both the recent data in memory and historical data in object storage.

**Mimir for Metrics**

Mimir is Grafana's horizontally scalable metrics backend. It's 100% Prometheus-compatible, so your existing PromQL queries and dashboards work unchanged.

Why Mimir over plain Prometheus?

- **Horizontal scaling**: Prometheus is single-node. Mimir distributes across many nodes.
- **Long-term storage**: Prometheus stores on local disk. Mimir stores in object storage.
- **Global view**: Query across all data, not federated queries across multiple Prometheus instances.

For teams already using Prometheus, Mimir is a drop-in replacement that removes scaling limitations.

**Loki for Logs**

Loki is Grafana's log aggregation system. It takes a radically different approach from Elasticsearch:

Elasticsearch indexes every word in every log line. This enables powerful full-text search but requires massive storage (10x+ the raw log size) and expensive compute.

Loki indexes only labels (metadata) and stores log content as compressed chunks. Search works by first filtering by labels (fast), then scanning matching chunks (slower, but fewer chunks to scan).

```
Elasticsearch approach:
┌────────────────────────────────────────────────────────────┐
│ Index: "user" → doc1, doc7, doc15                          │
│ Index: "logged" → doc1, doc5, doc9                         │
│ Index: "in" → doc1, doc2, doc3, doc4, doc5...              │
│ Index: "error" → doc3, doc8, doc12                         │
│ ... (index entry for every word in every log)              │
└────────────────────────────────────────────────────────────┘
Storage: 10x raw log size

Loki approach:
┌────────────────────────────────────────────────────────────┐
│ Index: {app="auth", level="error"} → chunk17, chunk23      │
│ Index: {app="api", level="info"} → chunk1, chunk4, chunk8  │
│ ... (index entry for each unique label combination)        │
│                                                            │
│ Chunks: compressed, stored in object storage               │
└────────────────────────────────────────────────────────────┘
Storage: 3x raw log size
```

The trade-off: Loki search is slower for "find all logs containing word X." But for observability use cases (find logs for service Y in the last hour with level=error), it's fast and dramatically cheaper.

**Object Storage: The Cost Secret**

All three backends (Tempo, Mimir, Loki) use object storage for long-term data. This is the key to our cost advantage.

Object storage (S3, MinIO, GCS) costs about $0.02 per GB per month. Block storage costs $0.10+ per GB per month. Over terabytes of observability data, this difference is significant.

Object storage also provides:
- **Eleven nines durability** (99.999999999%)—your data won't disappear
- **Unlimited capacity**—just keep adding data
- **No disk management**—no RAID arrays, no disk replacements

For on-premises deployments, MinIO provides S3-compatible object storage you can run yourself.

### Layer 5: Visualization — The Single Pane of Glass

Grafana ties everything together. It queries all three backends (Tempo, Mimir, Loki) through their respective data sources and presents a unified interface.

**Why Grafana?**

- **Native integration** with Tempo, Mimir, and Loki (all Grafana Labs projects)
- **Trace-to-logs correlation**: Click a trace span, see related logs
- **Explore mode**: Ad-hoc investigation without building dashboards first
- **Mature alerting**: Alert on any metric or log pattern
- **Large community**: Pre-built dashboards for common scenarios

**High Availability for Grafana**

Default Grafana uses SQLite for its own data (dashboards, users, alerts). For HA, we use PostgreSQL as a shared backend. Multiple Grafana instances can serve requests, any of which can access all dashboards and configuration.

**What About Alerting?**

Grafana's alerting engine evaluates rules and sends notifications. In an HA setup, you need to ensure alerts don't fire multiple times (once per Grafana instance). Grafana handles this with a distributed alert state stored in PostgreSQL—only one instance evaluates each alert rule at a time.

For more sophisticated alerting, you might add Alertmanager (Prometheus's alert routing and deduplication system). It handles:
- Grouping related alerts (all instances of same service)
- Silencing during maintenance windows
- Routing different alerts to different channels (PagerDuty for critical, Slack for warnings)
- Deduplication across multiple sources

---

## How Data Actually Flows

Understanding the data flow helps with debugging and capacity planning. When something isn't working, you can trace where in the pipeline the problem is occurring.

Let me walk you through a concrete example. Your payment service processes an order, and here's what happens to the observability data:

```
1. Your Code Executes
   ────────────────────────────────────────────────────────────
   PaymentService.processPayment() runs
   OTel SDK automatically creates spans for HTTP calls, DB queries
   SDK batches telemetry locally (1-5 seconds)
   
2. SDK Sends to Collector
   ────────────────────────────────────────────────────────────
   OTLP/gRPC to load balancer:4317
   Load balancer routes to healthy gateway
   Gateway validates OTLP structure
   Gateway batches for Kafka (1 second batches)
   Gateway publishes to kafka:otlp-traces
   
   Latency so far: ~2-6 seconds
   
3. Kafka Persists and Replicates
   ────────────────────────────────────────────────────────────
   Broker 0 receives message (partition leader)
   Replicates to Broker 1 and Broker 2
   Acknowledges to gateway after replication
   Message is now durable (survives broker failure)
   
4. Processor Consumes from Kafka
   ────────────────────────────────────────────────────────────
   Processor's Kafka receiver pulls batch from partition
   Tail sampling evaluates trace:
     - Is there an error? → Keep
     - Duration > 1s? → Keep
     - Neither? → 10% random sample
   Attribute processor adds k8s metadata
   Batch processor groups for efficient export
   
5. Processor Writes to Tempo
   ────────────────────────────────────────────────────────────
   OTLP/gRPC to Tempo distributor
   Distributor forwards to appropriate ingester (based on trace ID hash)
   Ingester holds trace in memory
   After flush interval, ingester writes block to S3
   
   Latency so far: ~10-30 seconds
   
6. User Queries in Grafana
   ────────────────────────────────────────────────────────────
   User clicks "Find traces for payment-service, last 1 hour"
   Grafana sends TraceQL query to Tempo
   Tempo querier checks:
     - Recent data in ingesters (last ~30 minutes)
     - Historical data in S3 blocks
   Results returned to Grafana
   User clicks trace, sees full span tree
   
   Query latency: ~1-5 seconds for typical queries
```

The end-to-end latency from application code to queryable in Grafana is typically 10-30 seconds. For most use cases, this is perfectly acceptable.

---

## Sampling: The Economics of Observability

I want to spend some time on sampling because it's often misunderstood, and getting it right dramatically affects your costs and the value you get from observability.

### The Problem with Keeping Everything

Let's do some math. Say you have:
- 100 services
- Each handling 100 requests/second
- Each request generates 5 spans (inter-service calls, DB queries, etc.)

That's 100 × 100 × 5 = 50,000 spans per second = 4.3 billion spans per day.

At ~1KB per span, that's 4.3 TB of trace data per day, or 130 TB per month.

Even with cheap object storage at $0.02/GB, that's $2,600/month just for trace storage. And you still need to process, index, and query this data.

### The Insight: Most Traces Are Boring

Here's the thing: 99% of your traces look exactly like each other. Successful request, normal latency, no errors. You don't need to keep all of them.

What you actually investigate:
- **Errors**: Always interesting, always worth keeping
- **Slow requests**: Latency outliers indicate problems
- **Specific users/requests**: When debugging a specific issue
- **A representative sample**: To understand normal behavior

### Tail-Based Sampling Strategy

Our recommended sampling policy:

```yaml
policies:
  # Policy 1: Keep all errors
  # When something goes wrong, you need the trace
  - name: keep-errors
    type: status_code
    status_code:
      status_codes: [ERROR]
    
  # Policy 2: Keep slow traces
  # Latency outliers often indicate problems
  - name: keep-slow
    type: latency
    latency:
      threshold_ms: 1000  # Adjust based on your SLOs
    
  # Policy 3: Keep traces for specific attributes
  # VIP customers, beta features, etc.
  - name: keep-vip
    type: string_attribute
    string_attribute:
      key: customer.tier
      values: [enterprise, premium]
    
  # Policy 4: Sample the rest
  # Representative sample of normal traffic
  - name: sample-rest
    type: probabilistic
    probabilistic:
      sampling_percentage: 10
```

With this policy:
- 100% of error traces are kept
- 100% of slow traces are kept
- 100% of VIP customer traces are kept
- 10% of remaining (normal, fast) traces are kept

Typical result: 80-90% reduction in trace volume while keeping everything you'd actually investigate.

### Head vs. Tail Sampling

**Head sampling** decides at the start of a trace: "Should I sample this?" The decision is made before you know if the trace will be interesting.

**Tail sampling** waits until the trace is complete, then decides. This lets you keep all errors even if you're sampling 1% overall.

The trade-off: Tail sampling requires holding incomplete traces in memory until they're complete (or a timeout is reached). This uses more memory but gives you much better sampling decisions.

For observability, tail sampling is almost always the right choice.

---

## Security Considerations

Observability data often contains sensitive information—user IDs, request parameters, internal service names, error messages with stack traces. You need to think about security from the start.

### Protecting Data in Transit

All communication between components should be encrypted. In practice, this means:

**Application to Collector:** Your SDKs should connect to collectors over TLS. In internal networks, you might accept unencrypted traffic, but for anything crossing network boundaries, use TLS.

```
# Good: TLS for external traffic
Application (external) → TLS → Load Balancer → Internal network

# Acceptable: Plain OTLP within trusted network
Application (internal) → Plain OTLP → Collector (same VPC)
```

**Between Components:** Within your observability cluster, traffic between collectors, Kafka, and backends should use TLS or be isolated in a private network. Most Kubernetes deployments rely on network policies rather than universal TLS, but it depends on your threat model.

### Protecting Data at Rest

**Object Storage:** Enable server-side encryption for S3/MinIO buckets. This is usually one configuration flag and protects against physical disk theft or accidental bucket exposure.

**Kafka:** Enable encryption at rest if your Kafka data contains sensitive information. For most observability data, the 24-hour retention means the exposure window is limited, but encryption is still good practice.

### Scrubbing Sensitive Data

The most important security measure is ensuring sensitive data never reaches your observability backends in the first place. Use the OTel Collector's attribute processor to remove or redact sensitive fields:

```yaml
processors:
  attributes:
    actions:
      # Remove sensitive headers
      - key: http.request.header.authorization
        action: delete
      - key: http.request.header.cookie
        action: delete
      
      # Redact email addresses
      - key: user.email
        action: hash  # or delete
      
      # Remove query parameters from URLs
      - key: http.url
        pattern: '\?.*'
        replacement: '?[REDACTED]'
        action: update
```

This processing happens before data reaches Kafka, so sensitive information never persists anywhere.

### Access Control

**Grafana:** Use your organization's identity provider (OIDC/OAuth2) for authentication. Configure team-based access to dashboards—not everyone needs to see everything.

**Backends:** Tempo, Mimir, and Loki all support multi-tenancy. You can separate data by team or environment, ensuring production and development data don't mix and teams only access their own data.

**Infrastructure:** Use your cloud provider's IAM to restrict who can access the underlying infrastructure. The people who view dashboards shouldn't necessarily have SSH access to the collectors.

---

## Common Mistakes to Avoid

After helping teams build observability platforms, I've seen the same mistakes repeatedly. Here's how to avoid them:

### Mistake 1: Instrumenting Everything from Day One

**The Problem:** Teams try to add traces, metrics, and logs to every service simultaneously. The project stalls because it's too big.

**The Fix:** Start with your most critical user-facing service. Get traces working for that service's main endpoints. Expand incrementally once you've proven value.

### Mistake 2: Keeping All Traces

**The Problem:** Without sampling, trace storage costs explode. Teams either run out of budget or start dropping data randomly.

**The Fix:** Implement tail-based sampling immediately. Keep 100% of errors, 100% of slow requests, sample the rest. You won't miss anything you'd actually investigate.

### Mistake 3: High-Cardinality Labels

**The Problem:** Adding labels like `user_id` or `request_id` to metrics creates millions of unique time series. Prometheus/Mimir performance collapses.

**The Fix:** Use high-cardinality data in traces and logs, not metrics. Metrics should use low-cardinality labels (service name, environment, HTTP method, status code bucket). If you need per-user metrics, use exemplars (links from metrics to traces) instead.

```
# Bad: Creates one time series per user
http_requests_total{user_id="12345"}  ← Millions of users = millions of series

# Good: Low cardinality, use traces for user-level detail
http_requests_total{service="api", status="200"}  ← Dozens of combinations
```

### Mistake 4: Not Setting Resource Limits

**The Problem:** A traffic spike causes the collector to consume all available memory, crashing other services on the same node.

**The Fix:** Always set memory limits in Docker/Kubernetes. Use the memory_limiter processor in the collector to drop data gracefully before hitting the hard limit.

### Mistake 5: Treating Observability as Optional

**The Problem:** Observability is added after launch. When the first production incident happens, there's no data to debug with.

**The Fix:** Observability is part of the definition of "done." No service goes to production without basic traces and metrics. It's much easier to add instrumentation during development than during a 2 AM outage.

### Mistake 6: Ignoring Your Own Observability Stack

**The Problem:** The observability platform itself has no monitoring. When Kafka runs out of disk or a collector OOMs, you find out when dashboards go blank.

**The Fix:** Monitor the monitoring. Set up alerts for:
- Collector queue length (backing up)
- Kafka consumer lag (processors falling behind)
- Storage capacity (running out of space)
- Component health (restarts, errors)

Use a separate, simpler monitoring path for these critical alerts—even just Prometheus with local storage and PagerDuty integration.

### Mistake 7: Skipping Structured Logging

**The Problem:** Applications log unstructured text. Engineers spend time parsing strings instead of querying fields.

**The Fix:** Log JSON from the start. Include trace_id in every log entry. Use consistent field names across services. The small upfront effort pays off enormously in debugging speed.

---

# Part IV: Making Decisions

## Technology Selection Rationale

Every technology choice in this architecture was a decision, not an inevitability. I want to share the reasoning so you can make informed choices for your own situation. Your constraints might lead to different conclusions.

### OpenTelemetry Collector vs. Alternatives

When we started, we asked: "What should sit between our applications and our backends?" We considered Fluentd (mature, widely used), Logstash (powerful, ELK integration), and Vector (modern, efficient). Here's why we landed on the OTel Collector:

The fundamental issue is that Fluentd and Logstash were designed for logs. They've added trace support over time, but it's not native. The OTel Collector was designed from the ground up to handle all three signals—traces, metrics, and logs—as first-class citizens.

More importantly, the Collector speaks OTLP natively. Since our applications use OpenTelemetry SDKs that output OTLP, there's no protocol translation needed. With Fluentd or Logstash, we'd need to convert OTLP to their internal format and back, adding complexity and potential failure modes.

| Factor | OTel Collector | Fluentd/Logstash | Vector |
|--------|----------------|------------------|--------|
| **Protocol support** | Native OTLP, plus many others | Log-focused, trace support varies | Good protocol support |
| **Trace handling** | First-class (spans, traces, sampling) | Limited/None | Good but less mature |
| **Metrics handling** | Native OTLP + Prometheus | Limited | Good |
| **Community** | CNCF, massive momentum | Mature, stable | Growing |
| **Configuration** | YAML, declarative | Ruby (Fluentd) or JSON (Logstash) | TOML, declarative |

Vector deserves special mention—it's technically excellent, well-designed, and performs well. If you already have Vector in your stack, it can work. But for a greenfield observability deployment, the Collector's native OTLP support and CNCF backing make it the natural choice.

### Tempo vs. Jaeger: The Storage Question

This decision came down to a practical question: "How do we want to store traces at scale?"

Jaeger is a fantastic project. It's battle-tested, well-documented, and the all-in-one deployment is perfect for getting started. We use it for Phase 1 (single-node) deployments.

But Jaeger's distributed deployment options—Cassandra or Elasticsearch as storage backends—require managing another complex distributed system. Cassandra clusters need care and feeding. Elasticsearch clusters need JVM tuning, shard management, and index lifecycle policies. These are operational burdens we didn't want.

Tempo takes a different approach: store everything in object storage (S3). No database cluster to manage. S3 is effectively infinitely scalable, highly durable, and cheap. The trade-off is that Tempo can't do arbitrary searches the way Jaeger with Elasticsearch can—but for observability use cases (find trace by ID, find traces by service and time range), it works well.

| Factor | Jaeger | Tempo |
|--------|--------|-------|
| **Storage options** | Badger, Cassandra, Elasticsearch | Object storage (S3) |
| **Operational complexity** | Low (all-in-one) to High (distributed) | Low (object storage is simple) |
| **Cost at scale** | Higher (Cassandra/ES clusters expensive) | Lower (S3 is cheap) |
| **Query capabilities** | Tag search, trace by ID | TraceQL (more powerful) |
| **Grafana integration** | Good | Native |

For the scalable architecture, Tempo's object storage model is a better fit. You don't need to manage database clusters.

### Mimir vs. Prometheus: The Scaling Question

Prometheus is the gold standard for metrics. It's reliable, well-understood, and has an enormous ecosystem. For single-node deployments, it's perfect.

The challenge is scaling. Prometheus is fundamentally single-node. When you outgrow one instance, your options are:

1. **Federation**: Run multiple Prometheus servers, query them through a central instance. Works, but federated queries are slow and complex to manage.

2. **Thanos**: Add sidecar components to Prometheus that enable long-term storage in S3 and global querying. Good option if you're already running Prometheus and want an upgrade path.

3. **Mimir**: Purpose-built for horizontal scaling. Effectively "Cortex 2.0" (Cortex was the original CNCF scalable Prometheus project, now sunset in favor of Mimir).

We chose Mimir because it was designed for horizontal scaling from the start, uses object storage natively, and comes from Grafana Labs (ensuring tight integration with our visualization layer). If you already have Prometheus and just need HA without massive scale, Thanos is a pragmatic upgrade path.

| Factor | Prometheus | Thanos | Cortex | Mimir |
|--------|------------|--------|--------|-------|
| **Scalability** | Single node | Adds HA to Prometheus | Horizontally scalable | Horizontally scalable |
| **Long-term storage** | Local disk | Object storage | Object storage | Object storage |
| **Operational complexity** | Low | Medium (sidecars, querier) | High | Medium |
| **Maturity** | Very mature | Mature | Mature | Newer (Grafana Labs) |
| **PromQL compatible** | Native | Yes | Yes | Yes |

### Loki vs. Elasticsearch: The Indexing Trade-off

This is perhaps the most opinionated choice in our stack. Elasticsearch is powerful, flexible, and industry-standard. So why Loki?

It comes down to how you use logs. If you're building a product that searches arbitrary text (like a log analytics SaaS, or searching email content), Elasticsearch's full-text indexing is essential. But for debugging production issues, you almost always know what you're looking for:

- "Show me logs from the payment service in the last hour"
- "Show me error logs from production"
- "Show me logs containing this trace ID"

For these queries, you don't need full-text indexing. You need efficient filtering by metadata (labels), followed by scanning the matching log content.

Loki's approach—index only labels, store content as compressed chunks—is dramatically cheaper. We've seen 10x cost reductions compared to Elasticsearch for similar log volumes. The trade-off is that pure text search ("find all logs containing 'NullPointerException'") requires scanning more data. But structured logging with proper labels largely eliminates this need.

| Factor | Elasticsearch | Loki |
|--------|---------------|------|
| **Indexing** | Full-text (every word) | Labels only |
| **Storage cost** | ~10x raw data | ~3x raw data |
| **Query flexibility** | Very flexible (Lucene) | Label filtering + grep |
| **Operational complexity** | High (JVM tuning, sharding) | Low |
| **Best for** | General-purpose search | Observability logs |

### Kafka vs. Alternatives: The Durability Question

The message queue layer is what turns "direct export" into "reliable pipeline." When a backend is temporarily unavailable, the queue holds data until it recovers. This is essential for production reliability.

We chose Kafka because durability is non-negotiable for us. When a message is acknowledged by Kafka, it's written to disk and replicated to multiple brokers. Hardware failure, process crash, network partition—the data survives.

Redis Streams is simpler to operate and performs well. For smaller deployments where you can accept some data loss during failures, it's a legitimate choice. RabbitMQ, while excellent for other use cases, wasn't designed for the high-throughput, persistent streaming that observability requires.

Apache Pulsar is technically excellent and arguably more modern than Kafka. If you're already running Pulsar, use it. But Kafka's ecosystem, community knowledge, and operational tooling are more mature.

| Factor | Kafka | Redis Streams | RabbitMQ | Pulsar |
|--------|-------|---------------|----------|--------|
| **Durability** | Excellent (replicated disk) | Good (with persistence) | Good | Excellent |
| **Throughput** | Very high | High | Moderate | Very high |
| **Replay capability** | Excellent | Limited | None | Excellent |
| **Operational complexity** | Medium | Low | Low | High |
| **Community/Ecosystem** | Very large | Large | Large | Growing |

We chose Kafka for its durability, throughput, and replay capabilities. For smaller deployments, Redis Streams is a simpler alternative.

---

## Cost Analysis: What Will This Actually Cost?

Let's be concrete about costs. I'll use AWS pricing, but the ratios are similar on other clouds.

### Single-Node Deployment (Phase 1)

For a team processing ~10,000 events/second:

| Component | Instance Type | Monthly Cost |
|-----------|--------------|--------------|
| Single server | c5.2xlarge (8 vCPU, 16GB) | $245 |
| Storage | 500GB gp3 SSD | $40 |
| **Total** | | **~$285/month** |

What you get:
- Full traces, metrics, and logs
- 30 days retention
- Grafana dashboards and alerting
- Good enough for most small-medium teams

### Multi-Node Deployment (Phase 2)

For a team processing ~50,000 events/second:

| Component | Instances | Monthly Cost |
|-----------|-----------|--------------|
| HAProxy | 2 × t3.small | $30 |
| Gateway collectors | 3 × c5.large | $220 |
| Kafka brokers | 3 × r5.large (16GB RAM) | $380 |
| Processor collectors | 3 × c5.large | $220 |
| Tempo | 3 × c5.large | $220 |
| Mimir | 3 × r5.large | $380 |
| Loki | 3 × c5.large | $220 |
| Grafana | 2 × t3.medium | $60 |
| PostgreSQL | 1 × db.t3.medium | $50 |
| Object storage (S3) | ~2TB | $50 |
| **Total** | | **~$1,830/month** |

### Enterprise-Scale Deployment (5,000+ Hosts)

This is where the economics become impossible to ignore. Let me share real numbers from enterprise deployments.

**The Datadog Reality at Scale:**

When you're monitoring 5,000+ hosts with full infrastructure monitoring, APM, and log management, commercial solutions like Datadog can easily exceed **$1.5 million per year**. Here's how that breaks down:

| Component | Hosts/Volume | Datadog Pricing | Annual Cost |
|-----------|--------------|-----------------|-------------|
| Infrastructure monitoring | 5,000 hosts | ~$15-23/host/month | $900K - $1.38M |
| APM (traces) | 5,000 hosts | ~$31-40/host/month | $1.86M - $2.4M |
| Log management | 500GB/day ingestion | ~$0.10/GB ingested + retention | $200K - $400K |
| **Total (typical bundle)** | | | **$1.5M - $2.5M/year** |

*Note: Datadog offers volume discounts and custom enterprise agreements. Real pricing varies based on negotiation, commitment length, and specific feature mix. These figures represent typical enterprise quotes we've seen.*

**The same scale with self-hosted:**

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| **Ingestion Layer** | | |
| HAProxy (HA pair) | 2 × c5.xlarge | $250 |
| Gateway collectors | 10 × c5.2xlarge | $2,450 |
| **Buffering Layer** | | |
| Kafka cluster | 5 × r5.2xlarge (64GB each) | $3,200 |
| **Processing Layer** | | |
| Processor collectors | 8 × c5.2xlarge | $1,960 |
| **Storage Layer** | | |
| Mimir cluster | 6 × r5.2xlarge | $3,840 |
| Tempo cluster | 4 × c5.2xlarge | $980 |
| Loki cluster | 6 × c5.2xlarge | $1,470 |
| **Visualization** | | |
| Grafana (HA) | 3 × c5.large | $220 |
| PostgreSQL (RDS) | db.r5.large | $180 |
| **Object Storage** | | |
| S3 storage | ~20TB/month | $500 |
| S3 requests | ~100M requests/month | $50 |
| **Networking** | | |
| Data transfer | ~5TB/month | $450 |
| **Total Infrastructure** | | **~$15,550/month** |
| **Annual Infrastructure** | | **~$186,600/year** |

**Add engineering costs for a realistic comparison:**

| Cost Category | Self-Hosted | Datadog |
|---------------|-------------|---------|
| Infrastructure | $186,600 | $0 (included) |
| Engineering (1 FTE dedicated) | $180,000 | $0 |
| On-call premium | $20,000 | $0 |
| Training (amortized) | $15,000 | $5,000 |
| **Total Annual Cost** | **~$400,000** | **~$1,500,000+** |
| **5-Year Total Cost** | **~$2,000,000** | **~$7,500,000+** |

**The savings at enterprise scale: $1.1 million per year, or $5.5 million over 5 years.**

Even with a dedicated full-time engineer and generous overhead estimates, self-hosted saves over 70% at this scale. That's not a rounding error—that's the budget for an entire engineering team.

### Why Commercial Pricing Explodes at Scale

It's worth understanding why commercial solutions become so expensive at scale:

**Per-host pricing models:** Datadog, Dynatrace, and others charge per host. This seemed reasonable when companies had 50 servers, but in the era of Kubernetes where you might run 5,000 pods across 500 nodes, the math breaks down. You're paying the same per-host fee for a 2-vCPU pod as for a 96-vCPU bare metal server.

**Log ingestion pricing:** Commercial log platforms charge by volume ingested. At enterprise scale with hundreds of services, logs can easily hit 500GB-1TB per day. At $0.10/GB, that's $50-100 per day just for ingestion, before retention costs.

**Feature bundling:** You often need multiple products (Infrastructure, APM, Logs, Synthetics) that each have their own pricing. What looks like $15/host becomes $50+/host when you add everything.

**The "success tax":** As your company grows and succeeds, your observability bill grows proportionally—often faster than your revenue. This creates perverse incentives to reduce observability coverage exactly when you need it most.

**Self-hosted scales differently:**
- Object storage costs ~$0.02/GB/month regardless of who wrote the data
- Adding hosts means adding metrics, but Mimir handles millions of series efficiently
- Log volume is compressed and stored cheaply, not priced per-GB ingested
- Your observability cost grows with actual resource usage, not host count

### Real-World Enterprise Comparison

Here's a concrete example comparing three approaches for a 5,000-host deployment:

```
                    Commercial         Self-Hosted         Self-Hosted
                    (Datadog)          (Phase 2)           (Phase 3/K8s)
                    ─────────────      ──────────────      ──────────────
Year 1 Cost         $1,500,000         $500,000            $450,000
                                       (includes setup)
                    
Year 2-5 Cost       $1,500,000/yr      $350,000/yr         $300,000/yr
                    
5-Year Total        $7,500,000         $1,900,000          $1,650,000
                    
Savings vs DD       —                  $5,600,000          $5,850,000
                                       (75% savings)        (78% savings)

Engineering FTE     0                  1.0                 1.5
Required

Time to             Days               Months              Months
Production

Customization       Limited            Full                Full

Data Residency      Vendor cloud       Your control        Your control
```

**The bottom line:** At enterprise scale, self-hosted observability isn't just a cost optimization—it's a strategic decision that can save millions of dollars while giving you complete control over your data and unlimited customization.

### Cost Comparison at Medium Scale

At 50,000 events/second (~500 hosts):

| Solution | Monthly Cost | Annual Cost |
|----------|--------------|-------------|
| **Self-hosted (our architecture)** | $1,830 | $22,000 |
| **Datadog** | $25,000-40,000 | $300,000-480,000 |
| **New Relic** | $20,000-30,000 | $240,000-360,000 |
| **Splunk** | $30,000-50,000 | $360,000-600,000 |

Even accounting for engineering time to maintain the self-hosted solution (say, 0.25 FTE at $150K/year = $37,500), you're still saving 85-95% at medium scale.

### Hidden Costs to Consider

Be honest about the full cost:

| Cost Type | Estimate | Notes |
|-----------|----------|-------|
| **Initial setup** | 2-4 weeks engineering time | One-time |
| **Ongoing maintenance** | 0.25 FTE | Updates, troubleshooting, optimization |
| **Training** | 1-2 weeks per engineer | Learning the stack |
| **On-call** | Part of existing rotation | Monitoring the monitoring |
| **Upgrades** | 1-2 days per quarter | Coordinated updates |

If your team is stretched thin and can't dedicate any time to infrastructure, a managed solution might be worth the cost. But for most engineering organizations, the cost savings justify the investment.

---

## The Real Human Cost: What You're Signing Up For

Let me be brutally honest about what running your own observability infrastructure actually entails. The dollar savings are real, but so is the work. You deserve to know exactly what you're getting into before you commit.

### The Operational Reality

**This is not "set and forget."** Unlike a SaaS solution where you install an agent and walk away, self-hosted observability requires ongoing attention. Here's what a typical month looks like:

```
Week 1:
├── Monday: Review weekend alerts, check disk usage trends
├── Wednesday: Investigate slow Grafana queries, optimize dashboard
└── Friday: Apply security patches to collector images

Week 2:
├── Tuesday: Kafka disk filling up faster than expected
│            Investigate: one team started logging request bodies
│            Resolution: Add log filtering, educate team
└── Thursday: Prometheus scrape targets failing health checks
             Root cause: Network policy change by platform team

Week 3:
├── Monday: Quarterly review - plan capacity for next quarter
├── Wednesday: Test backup restoration (it's been 90 days)
└── Friday: Update Grafana dashboards for new service

Week 4:
├── Tuesday: On-call page: Loki ingestion rate limit hit
│            3 AM investigation, increase limits, identify noisy service
└── Thursday: Post-incident review, update runbooks
```

This is real. Some months are quiet; others feel like you're constantly firefighting. On average, expect **8-15 hours per week** of active attention from someone on your team, plus **occasional intense incidents** that consume entire days.

### Specific Operational Tasks You'll Own

Let me break down exactly what "operational responsibility" means in practice:

**Daily/Automated (but you still need to check):**
- Health check alerts firing or not firing
- Disk space trending (all components)
- Consumer lag in Kafka (processors keeping up?)
- Error rates in collector exports

**Weekly:**
- Review collector metrics for anomalies
- Check query performance trends
- Verify backup jobs completed
- Review resource utilization vs. limits

**Monthly:**
- Capacity planning review
- Security vulnerability scanning
- Cost optimization review (right-sized instances?)
- Documentation updates

**Quarterly:**
- Component version upgrades
- Backup restoration testing
- Disaster recovery drills
- Performance baseline comparison

**Annually:**
- Major version migrations (Kafka 3.x → 4.x, etc.)
- Architecture review (still right-sized?)
- Retention policy review
- Cost model validation

### The Skills You Need On Your Team

This isn't just "someone who knows Docker." You need:

| Skill | Why It's Needed | Minimum Competency |
|-------|-----------------|-------------------|
| **Linux systems** | Debugging, performance tuning | Comfortable with strace, iostat, memory analysis |
| **Networking** | Connectivity issues, load balancing | DNS, TCP/IP, TLS certificates, firewalls |
| **Kafka** | The most operationally complex component | Topic management, consumer groups, broker operations |
| **Prometheus/PromQL** | Query optimization, cardinality issues | Write and debug complex queries |
| **Grafana** | Dashboard design, alerting rules | Create dashboards, manage data sources |
| **Object storage** | Cost optimization, lifecycle policies | S3 API, IAM policies |
| **Kubernetes** (Phase 3) | Everything gets more complex | Deployments, HPA, PDBs, debugging |

If no one on your team has these skills, you're either going to develop them (6-12 months to competency) or hire for them.

### The Incidents You'll Face

Here are real incidents I've seen teams deal with. Each one took hours to days to resolve:

**"Disk filled up overnight"**
- Cause: A deployment bug caused one service to log at 10x normal rate
- Impact: Loki stopped ingesting, missed 4 hours of logs
- Resolution time: 3 hours (identify, fix, recover)
- Prevention: Better rate limiting, faster alerting

**"Queries timing out"**
- Cause: High-cardinality metric (user_id as label) created 2M time series
- Impact: Prometheus OOM, dashboards broken for 2 hours
- Resolution time: 6 hours (identify culprit, relabel, compact)
- Prevention: Cardinality monitoring, label review process

**"Data loss during upgrade"**
- Cause: Kafka broker upgrade went wrong, partition leadership issues
- Impact: Lost 30 minutes of traces during recovery
- Resolution time: 4 hours
- Prevention: Better upgrade runbook, staging environment testing

**"Can't correlate traces and logs"**
- Cause: Clock skew between application servers and collectors
- Impact: Debugging efficiency dropped significantly
- Resolution time: 8 hours to identify, 2 hours to fix NTP
- Prevention: Clock monitoring, NTP hardening

**"Grafana is slow"**
- Cause: Dashboard with 50 panels, each querying 30 days of data
- Impact: Grafana unusable during business hours
- Resolution time: 2 days (query optimization, dashboard redesign)
- Prevention: Dashboard review process, query guidelines

These aren't rare events. Expect 1-2 significant incidents per quarter minimum.

### What You Give Up vs. Commercial Solutions

Let me compare specific features, not just price:

| Capability | Self-Hosted | Datadog | Dynatrace | New Relic |
|------------|-------------|---------|-----------|-----------|
| **Setup time** | 2-4 weeks | Hours | Hours | Hours |
| **AI/ML anomaly detection** | DIY or none | Built-in | Industry-leading | Good |
| **Auto-instrumentation** | Manual config | Agent-based (excellent) | Best in class | Good |
| **APM correlation** | Manual | Automatic | Automatic | Automatic |
| **RUM (Real User Monitoring)** | Separate tool | Included | Included | Included |
| **Synthetic monitoring** | Separate tool | Included | Included | Included |
| **Log pattern analysis** | Manual | ML-powered | ML-powered | ML-powered |
| **Mobile APM** | Not available | Included | Included | Included |
| **Infrastructure maps** | Basic | Beautiful | Excellent | Good |
| **Database monitoring** | DIY | Included | Deep integration | Included |
| **SLO management** | Manual | Built-in | Built-in | Built-in |
| **Incident management** | Integrate PagerDuty | Built-in | Built-in | Built-in |
| **On-call support** | Community/forums | 24/7 enterprise | 24/7 enterprise | 24/7 enterprise |
| **Compliance certs** | You manage | SOC2, HIPAA, etc. | SOC2, HIPAA, etc. | SOC2, HIPAA, etc. |

**The honest truth:** Commercial tools are genuinely better in many ways. They have hundreds of engineers building features. Their auto-instrumentation is magical. Their ML catches things you'd never notice. If budget weren't a constraint, many of these tools would be the right choice.

### Total Cost of Ownership: The Full Picture

Let's build a realistic TCO model for a medium-scale deployment (50K events/sec):

**Commercial Solution (Datadog as example):**

| Cost Category | Annual Cost |
|---------------|-------------|
| APM (traces) | $120,000 |
| Infrastructure monitoring | $48,000 |
| Log management (100GB/day) | $180,000 |
| Synthetics, RUM, etc. | $24,000 |
| **Total** | **$372,000/year** |

*Note: These are rough estimates. Actual Datadog pricing varies significantly based on negotiation, commitment, and usage patterns.*

**Self-Hosted Solution:**

| Cost Category | Annual Cost |
|---------------|-------------|
| Infrastructure (AWS) | $22,000 |
| Engineering time (0.5 FTE × $180K) | $90,000 |
| Training (one-time, amortized over 3 years) | $10,000 |
| Incident response time (50 hrs × $100/hr) | $5,000 |
| Opportunity cost (features not built) | Hard to quantify |
| **Total quantifiable** | **~$127,000/year** |

**The math:** Self-hosted saves ~$245,000/year in this scenario. That's real money—enough to hire two additional engineers.

**But consider:**
- What if that 0.5 FTE was building product features instead?
- What if an incident causes customer-facing impact?
- What if key infrastructure person leaves?
- What's the cost of slower debugging without ML features?

These are the questions you need to answer for your specific situation.

### The Hidden Advantages of Commercial Solutions

In fairness to Datadog, Dynatrace, and others, here's what they do exceptionally well:

**1. Time to Value**
- Install agent, see data in minutes
- Pre-built dashboards for every common technology
- No architecture decisions required

**2. Continuous Innovation**
- New features every month
- You benefit without any work
- AI/ML capabilities improving constantly

**3. Unified Experience**
- One tool for everything (APM, infra, logs, RUM, synthetics)
- Consistent UI/UX across all features
- Single vendor relationship

**4. Enterprise Features**
- SSO/SAML integration out of the box
- Role-based access control
- Audit logging
- Compliance certifications

**5. Support**
- Someone to call when things break
- Professional services for complex setups
- Training and certification programs

### When Commercial Solutions Are the Right Choice

Be honest with yourself. Choose a commercial solution if:

**Your team is small (<5 engineers)**
The operational overhead will consume too much of your capacity. You need those people building product.

**Observability isn't core to your business**
If you're a fintech building payment products, your competitive advantage isn't in running Kafka clusters. Let someone else do it.

**You need enterprise compliance**
SOC2, HIPAA, PCI compliance for your observability platform requires significant additional work when self-hosting.

**Time to market is critical**
A commercial solution is production-ready in days. Self-hosted takes weeks to months.

**You don't have infrastructure expertise**
Learning on production observability systems is painful. If no one on the team knows Kafka, this is a hard path.

### When Self-Hosted Is the Right Choice

Conversely, self-hosted makes sense when:

**Cost is a significant concern**
The savings are real. $200K-400K/year can fund multiple engineering positions.

**Data residency matters**
Some industries and regions require data to stay on-premises or in specific geographic locations.

**You need deep customization**
Commercial tools are opinionated. If you need custom sampling logic, unusual retention policies, or specific processing rules, self-hosted gives you full control.

**You have infrastructure expertise**
If your team already runs Kubernetes, Kafka, and other complex systems, the marginal effort for observability is lower.

**You're at massive scale**
At very high volumes (millions of events/second), commercial pricing becomes astronomical. Self-hosted cost scales more linearly.

**You're already committed to open source**
If OpenTelemetry is your standard and you want to avoid any vendor lock-in, self-hosted is the pure path.

---

## The Trade-Offs We Accept

Every architecture involves trade-offs. Here's what we're trading away in exchange for cost savings:

### What We Give Up

| Trade-off | Impact | Mitigation |
|-----------|--------|------------|
| **No vendor support** | You're on your own for troubleshooting | Active community, good documentation |
| **Operational responsibility** | You manage upgrades, scaling | Automate with IaC, good runbooks |
| **Feature development** | New features come from community | Most observability needs are stable |
| **Learning curve** | Team needs to learn new tools | OTel is becoming industry standard |
| **Initial setup time** | Weeks instead of hours | One-time investment |

### What We Get

| Benefit | Value |
|---------|-------|
| **97% cost savings** | $200K+/year for mid-size deployments |
| **Full data ownership** | Telemetry never leaves your infrastructure |
| **Unlimited customization** | Sampling, retention, processing rules |
| **No vendor lock-in** | Switch backends without changing app code |
| **Unlimited scale** | Object storage grows without limit |
| **Learning investment** | Skills transfer to any OTel-compatible tool |

### When This Architecture Is Wrong

Be honest with yourself about whether this is right for your situation:

**Don't use this if:**
- Your team has no capacity for infrastructure work
- You need enterprise support contracts for compliance
- Observability isn't core to your business and you'd rather outsource it
- Your scale is very small (<1K events/sec) and you just need something quick

**Do use this if:**
- Observability costs are a significant line item you want to control
- Data residency or privacy requirements prevent using SaaS solutions
- You want complete control over retention, sampling, and processing
- Your team has infrastructure skills and capacity

---

## Evolution Path: Start Simple, Scale When Needed

A common mistake is over-engineering from the start. Here's our recommended path:

```
Start Here                When You Need It              Eventually
────────────              ──────────────────            ──────────
Phase 1:                  Phase 2:                      Phase 3+:
Single Node               Add Kafka & HA                Kubernetes
                          
┌─────────────┐           ┌─────────────┐              ┌─────────────┐
│ All-in-one  │           │ Multi-node  │              │ K8s cluster │
│ Docker      │    ──→    │ + Kafka     │      ──→     │ Operators   │
│ Compose     │           │ + LB        │              │ Auto-scale  │
└─────────────┘           └─────────────┘              └─────────────┘
     
Triggers:                 Triggers:                     Triggers:
• >50K events/sec        • K8s standardization        • Multi-region
• Need HA                 • >100K events/sec           • Enterprise scale
                          • GitOps workflows
```

**Phase 1 is production-ready.** Don't let anyone tell you that you need Kafka and Kubernetes to run observability in production. Many teams successfully run Phase 1 for years.

**Phase 2 is when you hit limits.** If you're consistently at capacity, experiencing issues during backend maintenance, or need formal HA SLAs, it's time.

**Phase 3 is for K8s-native teams.** If your organization has standardized on Kubernetes and you want observability to follow the same deployment patterns, migrate then.

### What Phase 3 (Kubernetes) Actually Looks Like

Since we mention Kubernetes as Phase 3 but don't detail it, here's what changes:

**Same architecture, different orchestration.** The five layers remain identical. What changes is how you deploy and manage the components.

**Helm charts for everything.** Grafana Labs provides Helm charts for Tempo, Mimir, Loki, and Grafana. The OTel Collector has an official Helm chart. You describe your desired state, Helm deploys it.

**Auto-scaling with HPA.** Instead of manually adding gateway instances, you define a HorizontalPodAutoscaler. Kubernetes automatically adds pods when CPU or custom metrics exceed thresholds.

```yaml
# Example: Scale gateways based on CPU
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: otel-gateway
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: otel-gateway
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Operators for Kafka.** Running Kafka on Kubernetes is simplified with Strimzi (the Kafka operator). It handles broker deployment, configuration, rolling updates, and cluster scaling.

**Pod Disruption Budgets for reliability.** PDBs ensure Kubernetes doesn't accidentally take down too many pods during maintenance.

**GitOps workflows.** ArgoCD or Flux watches your Git repository and automatically applies changes to the cluster. Infrastructure changes go through pull requests just like code.

**Service mesh integration (optional).** If you're running Istio or Linkerd, the OTel Collector can receive telemetry from the mesh, giving you detailed service-to-service visibility without application changes.

The operational model shifts from "SSH to servers, run docker-compose" to "commit YAML, let GitOps deploy." This requires Kubernetes expertise but unlocks powerful automation.

---

## Final Thoughts

Observability shouldn't be a luxury reserved for companies with large budgets. Every engineering team deserves the ability to understand what their software is doing.

This architecture represents years of learning from running observability at scale. It's not perfect—no architecture is—but it's practical, proven, and dramatically more affordable than commercial alternatives.

The key insights:

1. **OpenTelemetry is the right foundation.** Instrument once, send anywhere.
2. **Object storage changes the economics.** Cheap, durable, unlimited.
3. **Sampling is essential at scale.** Keep what matters, sample the rest.
4. **Start simple.** Single-node is production-ready for many teams.
5. **Scale when you need to.** The architecture grows with your needs.

When you're ready to build, the [Implementation Guide](./implementation-guide.md) walks you through every step.

Good luck, and happy debugging.

---

## Quick Reference

For those times when you just need to look something up quickly, here are the key facts from this document.

### Architecture Summary (One Sentence Per Layer)

| Layer | Components | Purpose |
|-------|------------|---------|
| **Ingestion** | Load Balancer + Gateway Collectors | Accept telemetry, handle scale |
| **Buffering** | Kafka | Decouple ingestion from processing, durability |
| **Processing** | Processor Collectors | Sample, filter, enrich, route |
| **Storage** | Tempo, Mimir, Loki + Object Storage | Query-able, long-term retention |
| **Visualization** | Grafana + PostgreSQL | Dashboards, exploration, alerting |

### Capacity Guidelines

| Scale | Events/sec | Setup | Cost/month |
|-------|------------|-------|------------|
| Small | <10K | Single node | $100-200 |
| Medium | 10K-50K | Multi-node + Kafka | $500-2,000 |
| Large | 50K-200K | Kubernetes | $2,000-8,000 |
| Enterprise | >200K | Multi-cluster | $8,000+ |

### Port Reference

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| OTel Collector | 4317 | gRPC | OTLP ingestion |
| OTel Collector | 4318 | HTTP | OTLP ingestion |
| OTel Collector | 13133 | HTTP | Health check |
| Prometheus/Mimir | 9090 | HTTP | API and UI |
| Tempo | 3200 | HTTP | API |
| Loki | 3100 | HTTP | API |
| Grafana | 3000 | HTTP | UI |
| Kafka | 9092 | TCP | Client connections |

### Related Documents

| Document | Description |
|----------|-------------|
| [Implementation Guide](./implementation-guide.md) | Step-by-step deployment instructions |
| [Config Files](./configs/) | All configuration files |
| [Main README](../../README.md) | Project overview |

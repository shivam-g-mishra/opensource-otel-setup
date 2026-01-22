# =============================================================================
# OpenTelemetry Observability Stack - Makefile
# =============================================================================
# Simple commands to manage the observability stack
#
# Usage:
#   make help     - Show available commands
#   make up       - Start the stack
#   make down     - Stop the stack
#   make status   - Check service health
# =============================================================================

.PHONY: help up up-seq up-full down stop start restart status logs clean ps backup restore deploy
.PHONY: deploy-quick deploy-pull restore-latest validate pull update alerts metrics
.PHONY: logs-collector logs-jaeger logs-loki logs-prometheus shell-collector shell-prometheus
.PHONY: _health-check

# Default target
.DEFAULT_GOAL := help

# Colors for terminal output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

## help: Show this help message
help:
	@echo ""
	@echo "$(BLUE)OpenTelemetry Observability Stack$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC)"
	@echo "  make $(GREEN)<command>$(NC)"
	@echo ""
	@echo "$(YELLOW)Core Commands:$(NC)"
	@echo "  $(GREEN)up$(NC)              Start the stack"
	@echo "  $(GREEN)down$(NC)            Stop the stack (preserves data)"
	@echo "  $(GREEN)restart$(NC)         Restart all services"
	@echo "  $(GREEN)status$(NC)          Check service health"
	@echo "  $(GREEN)logs$(NC)            View logs from all services"
	@echo ""
	@echo "$(YELLOW)Operations:$(NC)"
	@echo "  $(GREEN)deploy$(NC)          Zero-downtime deployment"
	@echo "  $(GREEN)backup$(NC)          Backup all data and configs"
	@echo "  $(GREEN)restore$(NC)         Restore from backup"
	@echo "  $(GREEN)clean$(NC)           Remove all data (destructive!)"
	@echo ""
	@echo "$(YELLOW)Development:$(NC)"
	@echo "  $(GREEN)up-seq$(NC)          Start with Seq (for .NET)"
	@echo "  $(GREEN)validate$(NC)        Validate configurations"
	@echo "  $(GREEN)pull$(NC)            Pull latest images"
	@echo "  $(GREEN)logs-collector$(NC)  View collector logs"
	@echo ""
	@echo "$(YELLOW)Quick Start:$(NC)"
	@echo "  make up        # Start everything"
	@echo "  make status    # Check if services are healthy"
	@echo "  make down      # Stop everything"
	@echo ""

# =============================================================================
# Core Commands
# =============================================================================

## up: Start the observability stack
up:
	@echo "$(BLUE)Starting OpenTelemetry Stack...$(NC)"
	@docker compose up -d
	@echo ""
	@echo "$(GREEN)✓ Stack started!$(NC)"
	@echo ""
	@echo "$(YELLOW)Access URLs:$(NC)"
	@echo "  Grafana:    $(GREEN)http://localhost:3000$(NC)  (admin/admin)"
	@echo "  Jaeger:     $(GREEN)http://localhost:16686$(NC)"
	@echo "  Prometheus: $(GREEN)http://localhost:9090$(NC)"
	@echo ""
	@echo "$(YELLOW)Send telemetry to:$(NC)"
	@echo "  OTLP gRPC:  $(GREEN)localhost:4317$(NC)"
	@echo "  OTLP HTTP:  $(GREEN)localhost:4318$(NC)"
	@echo ""

## up-seq: Start stack with Seq (for .NET apps)
up-seq:
	@echo "$(BLUE)Starting OpenTelemetry Stack with Seq...$(NC)"
	@docker compose --profile seq up -d
	@echo "$(GREEN)✓ Stack started with Seq!$(NC)"
	@echo "  Seq UI: $(GREEN)http://localhost:5380$(NC)"

## up-full: Start all services including Seq
up-full:
	@echo "$(BLUE)Starting full OpenTelemetry Stack...$(NC)"
	@docker compose --profile full up -d
	@echo "$(GREEN)✓ Full stack started!$(NC)"

## down: Stop all services (preserves data)
down:
	@echo "$(BLUE)Stopping OpenTelemetry Stack...$(NC)"
	@docker compose --profile full down
	@echo "$(GREEN)✓ Stack stopped (data preserved)$(NC)"

## stop: Alias for 'down'
stop: down

## start: Alias for 'up'
start: up

## restart: Restart all services
restart: down up

## status: Check health of all services
status:
	@echo "$(BLUE)Service Status:$(NC)"
	@echo ""
	@docker compose --profile full ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps
	@echo ""
	@echo "$(BLUE)Health Checks:$(NC)"
	@./scripts/status.sh 2>/dev/null || $(MAKE) _health-check

_health-check:
	@curl -sf http://localhost:16686 > /dev/null && echo "  $(GREEN)✓$(NC) Jaeger" || echo "  $(RED)✗$(NC) Jaeger"
	@curl -sf http://localhost:3000/api/health > /dev/null && echo "  $(GREEN)✓$(NC) Grafana" || echo "  $(RED)✗$(NC) Grafana"
	@curl -sf http://localhost:9090/-/healthy > /dev/null && echo "  $(GREEN)✓$(NC) Prometheus" || echo "  $(RED)✗$(NC) Prometheus"
	@curl -sf http://localhost:3100/ready > /dev/null && echo "  $(GREEN)✓$(NC) Loki" || echo "  $(RED)✗$(NC) Loki"
	@curl -sf http://localhost:13133/health > /dev/null && echo "  $(GREEN)✓$(NC) OTel Collector" || echo "  $(RED)✗$(NC) OTel Collector"
	@curl -sf http://localhost:9100/metrics > /dev/null && echo "  $(GREEN)✓$(NC) Node Exporter" || echo "  $(RED)✗$(NC) Node Exporter"

## ps: Show running containers
ps:
	@docker compose --profile full ps

## logs: View logs from all services
logs:
	@docker compose --profile full logs -f

## logs-collector: View OTel Collector logs
logs-collector:
	@docker compose logs -f otel-collector

## logs-jaeger: View Jaeger logs
logs-jaeger:
	@docker compose logs -f jaeger

## logs-loki: View Loki logs
logs-loki:
	@docker compose logs -f loki

## logs-prometheus: View Prometheus logs
logs-prometheus:
	@docker compose logs -f prometheus

# =============================================================================
# Operations Commands
# =============================================================================

## deploy: Zero-downtime deployment
deploy:
	@./scripts/deploy.sh

## deploy-quick: Quick deployment (skip backup)
deploy-quick:
	@./scripts/deploy.sh --quick

## deploy-pull: Deploy with image updates
deploy-pull:
	@./scripts/deploy.sh --pull

## backup: Backup all data and configurations
backup:
	@./scripts/backup.sh

## restore: Restore from backup (interactive)
restore:
	@echo "$(YELLOW)Available backups:$(NC)"
	@ls -1 ./backups/ 2>/dev/null || echo "  No backups found"
	@echo ""
	@echo "Usage: ./scripts/restore.sh <backup_path>"
	@echo "Example: ./scripts/restore.sh ./backups/20260122_020000"

## restore-latest: Restore from most recent backup
restore-latest:
	@latest=$$(ls -1t ./backups/ 2>/dev/null | head -1); \
	if [ -n "$$latest" ]; then \
		./scripts/restore.sh "./backups/$$latest" --force; \
	else \
		echo "$(RED)No backups found$(NC)"; \
	fi

## clean: Stop services and remove all data volumes
clean:
	@echo "$(RED)WARNING: This will delete all stored data!$(NC)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "$(BLUE)Stopping services and removing volumes...$(NC)"
	@docker compose --profile full down -v
	@echo "$(GREEN)✓ All data removed$(NC)"

# =============================================================================
# Development Commands
# =============================================================================

## shell-collector: Open shell in OTel Collector container
shell-collector:
	@docker compose exec otel-collector sh

## shell-prometheus: Open shell in Prometheus container
shell-prometheus:
	@docker compose exec prometheus sh

## validate: Validate configuration files
validate:
	@echo "$(BLUE)Validating configurations...$(NC)"
	@docker compose config -q && echo "  $(GREEN)✓$(NC) docker-compose.yml is valid"
	@echo "$(GREEN)✓ All configurations valid$(NC)"

## pull: Pull latest images
pull:
	@echo "$(BLUE)Pulling latest images...$(NC)"
	@docker compose pull
	@echo "$(GREEN)✓ Images updated$(NC)"

## update: Pull latest images and restart
update: pull restart

## alerts: View active Prometheus alerts
alerts:
	@echo "$(BLUE)Active Alerts:$(NC)"
	@curl -s http://localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname): \(.annotations.summary)"' 2>/dev/null || \
		echo "  Unable to fetch alerts (is Prometheus running?)"

## metrics: Show collector throughput metrics
metrics:
	@echo "$(BLUE)Collector Throughput:$(NC)"
	@echo ""
	@echo "Spans received (last 5m):"
	@curl -s 'http://localhost:9090/api/v1/query?query=rate(otelcol_receiver_accepted_spans[5m])' | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "  N/A"
	@echo ""
	@echo "Metrics received (last 5m):"
	@curl -s 'http://localhost:9090/api/v1/query?query=rate(otelcol_receiver_accepted_metric_points[5m])' | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "  N/A"
	@echo ""
	@echo "Logs received (last 5m):"
	@curl -s 'http://localhost:9090/api/v1/query?query=rate(otelcol_receiver_accepted_log_records[5m])' | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "  N/A"

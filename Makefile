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

.PHONY: help up down stop start restart status logs clean ps shell

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
	@echo "$(YELLOW)Commands:$(NC)"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/## /  /' | awk -F': ' '{printf "$(GREEN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Quick Start:$(NC)"
	@echo "  make up        # Start everything"
	@echo "  make status    # Check if services are healthy"
	@echo "  make down      # Stop everything"
	@echo ""

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

## clean: Stop services and remove all data volumes
clean:
	@echo "$(RED)WARNING: This will delete all stored data!$(NC)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "$(BLUE)Stopping services and removing volumes...$(NC)"
	@docker compose --profile full down -v
	@echo "$(GREEN)✓ All data removed$(NC)"

## shell-collector: Open shell in OTel Collector container
shell-collector:
	@docker compose exec otel-collector sh

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

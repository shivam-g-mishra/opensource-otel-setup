#!/bin/bash
# =============================================================================
# Health Check Script for Observability Stack
# =============================================================================
#
# Checks all components and reports status
#
# Usage:
#   ./health-check.sh           # Check all
#   ./health-check.sh --json    # JSON output for automation

set -euo pipefail

# Configuration
OTEL_GATEWAY=${OTEL_GATEWAY:-localhost:4317}
OTEL_HTTP=${OTEL_HTTP:-localhost:4318}
PROMETHEUS=${PROMETHEUS:-localhost:9090}
JAEGER=${JAEGER:-localhost:16686}
TEMPO=${TEMPO:-localhost:3200}
LOKI=${LOKI:-localhost:3100}
GRAFANA=${GRAFANA:-localhost:3000}
KAFKA=${KAFKA:-localhost:9092}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

JSON_OUTPUT=false
[[ "${1:-}" == "--json" ]] && JSON_OUTPUT=true

# Track overall status
OVERALL_STATUS=0
declare -A RESULTS

check_http() {
  local name=$1
  local url=$2
  local expected=${3:-200}
  
  if curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "$expected"; then
    RESULTS[$name]="healthy"
    return 0
  else
    RESULTS[$name]="unhealthy"
    OVERALL_STATUS=1
    return 1
  fi
}

check_tcp() {
  local name=$1
  local host=$2
  local port=$3
  
  if nc -z -w 2 "$host" "$port" 2>/dev/null; then
    RESULTS[$name]="healthy"
    return 0
  else
    RESULTS[$name]="unhealthy"
    OVERALL_STATUS=1
    return 1
  fi
}

print_status() {
  local name=$1
  local status=${RESULTS[$name]}
  
  if [[ "$status" == "healthy" ]]; then
    echo -e "  ${GREEN}✓${NC} $name"
  else
    echo -e "  ${RED}✗${NC} $name"
  fi
}

# Run checks
echo "Checking observability stack health..."
echo ""

# OTel Collector
check_http "otel-collector-health" "http://localhost:13133/health" || true
check_tcp "otel-grpc" "localhost" "4317" || true
check_tcp "otel-http" "localhost" "4318" || true

# Storage backends
check_http "prometheus" "http://${PROMETHEUS}/-/healthy" || true
check_http "jaeger" "http://${JAEGER}" || true
check_http "tempo" "http://${TEMPO}/ready" || true
check_http "loki" "http://${LOKI}/ready" || true

# Visualization
check_http "grafana" "http://${GRAFANA}/api/health" || true

# Kafka (if running)
check_tcp "kafka" "localhost" "9092" 2>/dev/null || RESULTS["kafka"]="not-running"

# Output results
if [[ "$JSON_OUTPUT" == true ]]; then
  # JSON output
  echo "{"
  echo "  \"timestamp\": \"$(date -Iseconds)\","
  echo "  \"status\": \"$([ $OVERALL_STATUS -eq 0 ] && echo 'healthy' || echo 'degraded')\","
  echo "  \"components\": {"
  first=true
  for name in "${!RESULTS[@]}"; do
    [[ "$first" == true ]] || echo ","
    echo -n "    \"$name\": \"${RESULTS[$name]}\""
    first=false
  done
  echo ""
  echo "  }"
  echo "}"
else
  # Human-readable output
  echo "Component Status:"
  echo "================="
  
  echo ""
  echo "Ingestion:"
  print_status "otel-collector-health"
  print_status "otel-grpc"
  print_status "otel-http"
  
  echo ""
  echo "Storage:"
  print_status "prometheus"
  [[ -n "${RESULTS[jaeger]:-}" ]] && print_status "jaeger"
  [[ -n "${RESULTS[tempo]:-}" ]] && print_status "tempo"
  print_status "loki"
  
  echo ""
  echo "Queue:"
  [[ -n "${RESULTS[kafka]:-}" ]] && print_status "kafka"
  
  echo ""
  echo "Visualization:"
  print_status "grafana"
  
  echo ""
  echo "========================================"
  if [[ $OVERALL_STATUS -eq 0 ]]; then
    echo -e "${GREEN}All systems operational${NC}"
  else
    echo -e "${YELLOW}Some components are degraded${NC}"
  fi
fi

exit $OVERALL_STATUS

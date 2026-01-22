#!/bin/bash
# =============================================================================
# Check Status of OpenTelemetry Observability Stack
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  OpenTelemetry Stack Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Show container status
docker compose --profile full ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo -e "${BLUE}Health Checks:${NC}"

# Check each service
check_service() {
    local name=$1
    local url=$2
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$url" 2>/dev/null || echo "000")
    
    if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
        echo -e "  ${GREEN}✓${NC} $name: OK"
    else
        echo -e "  ${RED}✗${NC} $name: Not responding (HTTP $status)"
    fi
}

check_service "Jaeger" "http://localhost:${JAEGER_UI_PORT:-16686}"
check_service "Grafana" "http://localhost:${GRAFANA_PORT:-3000}/api/health"
check_service "Prometheus" "http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy"
check_service "OTel Collector" "http://localhost:13133/health"

# Check if Seq is running
if docker ps --format '{{.Names}}' | grep -q 'otel-seq'; then
    check_service "Seq" "http://localhost:${SEQ_UI_PORT:-5380}"
fi

echo ""

#!/bin/bash
# =============================================================================
# Start OpenTelemetry Observability Stack
# =============================================================================
# Usage:
#   ./scripts/start.sh           # Start core services
#   ./scripts/start.sh --full    # Start all services including Seq
#   ./scripts/start.sh --seq     # Start with Seq (for .NET apps)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Starting OpenTelemetry Stack${NC}"
echo -e "${BLUE}========================================${NC}"

# Parse arguments
PROFILE=""
if [[ "$1" == "--full" ]]; then
    PROFILE="--profile full"
    echo -e "${YELLOW}Starting full stack (including Seq)...${NC}"
elif [[ "$1" == "--seq" ]]; then
    PROFILE="--profile seq"
    echo -e "${YELLOW}Starting with Seq...${NC}"
else
    echo -e "${YELLOW}Starting core services...${NC}"
fi

# Start services
docker compose $PROFILE up -d

# Wait for services to be healthy
echo -e "${YELLOW}Waiting for services to be healthy...${NC}"
sleep 10

# Check status
echo ""
echo -e "${GREEN}✓ Services started!${NC}"
echo ""
echo -e "${BLUE}Access URLs:${NC}"
echo -e "  📊 Jaeger (Traces):     ${GREEN}http://localhost:${JAEGER_UI_PORT:-16686}${NC}"
echo -e "  📈 Grafana (Dashboards): ${GREEN}http://localhost:${GRAFANA_PORT:-3000}${NC}  (admin/admin)"
echo -e "  🔍 Prometheus (Metrics): ${GREEN}http://localhost:${PROMETHEUS_PORT:-9090}${NC}"

if [[ "$1" == "--full" ]] || [[ "$1" == "--seq" ]]; then
    echo -e "  📝 Seq (Logs):          ${GREEN}http://localhost:${SEQ_UI_PORT:-5380}${NC}"
fi

echo ""
echo -e "${BLUE}Send telemetry to:${NC}"
echo -e "  OTLP gRPC: ${GREEN}localhost:${OTEL_GRPC_PORT:-4317}${NC}"
echo -e "  OTLP HTTP: ${GREEN}localhost:${OTEL_HTTP_PORT:-4318}${NC}"
echo ""

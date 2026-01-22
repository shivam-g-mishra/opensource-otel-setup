#!/bin/bash
# =============================================================================
# Stop OpenTelemetry Observability Stack
# =============================================================================
# Usage:
#   ./scripts/stop.sh              # Stop all services
#   ./scripts/stop.sh --clean      # Stop and remove volumes
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
echo -e "${BLUE}  Stopping OpenTelemetry Stack${NC}"
echo -e "${BLUE}========================================${NC}"

if [[ "$1" == "--clean" ]]; then
    echo -e "${YELLOW}Stopping services and removing volumes...${NC}"
    docker compose --profile full down -v
    echo -e "${GREEN}✓ Services stopped and volumes removed${NC}"
else
    echo -e "${YELLOW}Stopping services...${NC}"
    docker compose --profile full down
    echo -e "${GREEN}✓ Services stopped (data preserved)${NC}"
fi

echo ""
